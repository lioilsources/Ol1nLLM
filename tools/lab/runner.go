package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

type CellStatus string

const (
	CellPending CellStatus = "pending"
	CellRunning CellStatus = "running"
	CellDone    CellStatus = "done"
	CellFailed  CellStatus = "failed"
)

type CellState struct {
	ID          string     `json:"id"`
	Status      CellStatus `json:"status"`
	PromptID    string     `json:"promptId,omitempty"`
	Error       string     `json:"error,omitempty"`
	Seconds     float64    `json:"seconds,omitempty"`
	Placeholder bool       `json:"placeholder,omitempty"`
}

type RunState struct {
	ID        string               `json:"id"`
	Title     string               `json:"title"`
	CreatedAt time.Time            `json:"createdAt"`
	Status    string               `json:"status"` // planning|dumped|running|done|failed|stalled|cancelled
	Message   string               `json:"message,omitempty"`
	Dry       bool                 `json:"dry"`
	Version   int                  `json:"version"`
	Cells     map[string]CellState `json:"cells"`
	Queue     QueueState           `json:"queue"`
	Done      int                  `json:"done"`
	Failed    int                  `json:"failed"`
	Total     int                  `json:"total"`
}

// Run owns one experiment directory. Everything the UI needs is mirrored to
// state.json, so a browser reload — or a server restart — costs nothing.
type Run struct {
	Dir    string
	Spec   *Spec
	env    *Env
	mu     sync.Mutex
	state  RunState
	man    *Manifest
	cancel context.CancelFunc
	subs   map[chan RunState]struct{}
}

func NewRun(env *Env, dir string, spec *Spec) *Run {
	return &Run{
		Dir: dir, Spec: spec, env: env,
		state: RunState{
			ID: filepath.Base(dir), Title: spec.Title, CreatedAt: time.Now(),
			Status: "planning", Dry: spec.Dry, Cells: map[string]CellState{},
		},
		subs: map[chan RunState]struct{}{},
	}
}

// RunSummary is what the run list needs — deliberately without the cell map.
type RunSummary struct {
	ID        string    `json:"id"`
	Title     string    `json:"title"`
	CreatedAt time.Time `json:"createdAt"`
	Status    string    `json:"status"`
	Message   string    `json:"message,omitempty"`
	Dry       bool      `json:"dry"`
	Done      int       `json:"done"`
	Failed    int       `json:"failed"`
	Total     int       `json:"total"`
}

func (r *Run) Summary() RunSummary {
	s := r.State()
	return RunSummary{
		ID: s.ID, Title: s.Title, CreatedAt: s.CreatedAt, Status: s.Status,
		Message: s.Message, Dry: s.Dry, Done: s.Done, Failed: s.Failed, Total: s.Total,
	}
}

// clone deep-copies the cell map. A shallow copy shares it with the live
// state, so a subscriber serialising a snapshot while the run mutates its
// cells is a data race — and eventually a "concurrent map iteration and map
// write" crash.
func (s RunState) clone() RunState {
	c := s
	c.Cells = make(map[string]CellState, len(s.Cells))
	for k, v := range s.Cells {
		c.Cells[k] = v
	}
	return c
}

func (r *Run) State() RunState {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.state.clone()
}

func (r *Run) Manifest() *Manifest {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.man
}

func (r *Run) Subscribe() (chan RunState, func()) {
	ch := make(chan RunState, 8)
	r.mu.Lock()
	r.subs[ch] = struct{}{}
	snapshot := r.state.clone()
	r.mu.Unlock()
	ch <- snapshot
	return ch, func() {
		r.mu.Lock()
		delete(r.subs, ch)
		close(ch)
		r.mu.Unlock()
	}
}

// update mutates state under the lock, bumps the version, persists and fans
// out. Every state change goes through here so no subscriber can miss one.
func (r *Run) update(fn func(*RunState)) {
	r.mu.Lock()
	fn(&r.state)
	r.state.Version++
	snapshot := r.state.clone()
	// The sends happen under the same lock that guards subs. Doing them after
	// releasing it leaves exactly the window where an unsubscribing SSE client
	// closes its channel between the copy and the send — "send on closed
	// channel", which takes the whole server down mid-run. The sends are
	// non-blocking, so holding the lock costs nothing.
	for ch := range r.subs {
		select {
		case ch <- snapshot:
		default: // a slow reader must never stall the run
		}
	}
	r.mu.Unlock()
	r.persist(snapshot)
}

func (r *Run) persist(s RunState) {
	data, err := json.MarshalIndent(s, "", " ")
	if err != nil {
		return
	}
	tmp := filepath.Join(r.Dir, "state.json.tmp")
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return
	}
	_ = os.Rename(tmp, filepath.Join(r.Dir, "state.json"))
}

// Dump builds the workflows through the app's own code. It is free of GPU cost,
// so it always runs first and its manifest — not an estimate — is what the
// table and the confirmation are built from.
func (r *Run) Dump() error {
	r.update(func(s *RunState) { s.Status = "planning"; s.Message = "generuji workflow…" })
	if !r.env.FlutterOK {
		return r.fail("dump", fmt.Errorf("flutter není použitelný: %s", r.env.FlutterMsg))
	}
	if err := os.MkdirAll(filepath.Join(r.Dir, "wf"), 0o755); err != nil {
		return err
	}
	env, err := r.Spec.DumpEnv(r.Dir)
	if err != nil {
		return r.fail("dump", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, "flutter", "test", "tools/lab/dump.dart")
	cmd.Dir = r.env.RepoRoot
	cmd.Env = env
	out, err := cmd.CombinedOutput()
	_ = os.WriteFile(filepath.Join(r.Dir, "dump.log"), out, 0o644)
	manPath := filepath.Join(r.Dir, "wf", "manifest.json")
	if err != nil {
		if _, statErr := os.Stat(manPath); statErr != nil {
			return r.fail("dump", fmt.Errorf("%v — poslední řádky: %s", err, tailLines(string(out), 6)))
		}
	}
	man, err := ReadManifest(manPath)
	if err != nil {
		return r.fail("dump", fmt.Errorf("manifest: %w", err))
	}
	r.update(func(s *RunState) {
		s.Status = "dumped"
		s.Message = fmt.Sprintf("%d buněk připraveno", len(man.Cells))
		s.Total = len(man.Cells)
		for _, c := range man.Cells {
			if _, ok := s.Cells[c.ID]; !ok {
				s.Cells[c.ID] = CellState{ID: c.ID, Status: CellPending}
			}
		}
	})
	r.mu.Lock()
	r.man = man
	r.mu.Unlock()
	specJSON, _ := json.MarshalIndent(r.Spec, "", " ")
	_ = os.WriteFile(filepath.Join(r.Dir, "spec.json"), specJSON, 0o644)
	return nil
}

func (r *Run) fail(phase string, err error) error {
	r.update(func(s *RunState) {
		s.Status = "failed"
		s.Message = phase + ": " + err.Error()
	})
	return err
}

// Generate spends the GPU. Resumable by construction: a cell whose PNG is
// already on disk is skipped, so cancel/resume and a server restart are free.
func (r *Run) Generate() {
	ctx, cancel := context.WithCancel(context.Background())
	r.mu.Lock()
	r.cancel = cancel
	man := r.man
	r.mu.Unlock()
	defer cancel()
	if man == nil {
		_ = r.fail("run", fmt.Errorf("chybí manifest — nejdřív dump"))
		return
	}
	_ = os.MkdirAll(filepath.Join(r.Dir, "img"), 0o755)
	_ = os.MkdirAll(filepath.Join(r.Dir, "thumb"), 0o755)

	// Grouped by model so each checkpoint loads once instead of once per style.
	cells := append([]ManifestCell{}, man.Cells...)
	sort.SliceStable(cells, func(i, j int) bool { return cells[i].Model < cells[j].Model })

	r.update(func(s *RunState) { s.Status = "running"; s.Message = "" })
	authFails := 0
	for _, c := range cells {
		select {
		case <-ctx.Done():
			r.update(func(s *RunState) { s.Status = "cancelled"; s.Message = "zrušeno" })
			return
		default:
		}
		if _, err := os.Stat(r.imgPath(c.ID)); err == nil {
			r.update(func(s *RunState) { r.markDone(s, c.ID, 0, false) })
			continue
		}
		start := time.Now()
		r.update(func(s *RunState) {
			cs := s.Cells[c.ID]
			cs.Status = CellRunning
			s.Cells[c.ID] = cs
		})
		err := r.generateCell(ctx, c)
		if err != nil {
			var he *HTTPError
			if asHTTPError(err, &he) && he.IsAuth() {
				authFails++
				// Three in a row means the token is wrong, not that one cell is
				// unlucky — failing 400 cells one by one helps nobody.
				if authFails >= 3 {
					_ = r.fail("run", fmt.Errorf("CF Access odmítá požadavky (%v) — zkontroluj .env.local", he))
					return
				}
			} else {
				authFails = 0
			}
			r.update(func(s *RunState) {
				cs := s.Cells[c.ID]
				cs.Status = CellFailed
				cs.Error = err.Error()
				s.Cells[c.ID] = cs
				s.Failed++
			})
			continue
		}
		authFails = 0
		secs := time.Since(start).Seconds()
		r.update(func(s *RunState) { r.markDone(s, c.ID, secs, r.Spec.Dry) })
	}
	r.computeMetrics()
	r.update(func(s *RunState) {
		s.Status = "done"
		s.Message = fmt.Sprintf("hotovo: %d ok, %d chyb", s.Done, s.Failed)
	})
}

func (r *Run) markDone(s *RunState, id string, secs float64, placeholder bool) {
	cs := s.Cells[id]
	if cs.Status != CellDone {
		s.Done++
	}
	cs.Status = CellDone
	cs.Seconds = secs
	cs.Placeholder = placeholder
	s.Cells[id] = cs
}

func (r *Run) imgPath(id string) string   { return filepath.Join(r.Dir, "img", id+".png") }
func (r *Run) thumbPath(id string) string { return filepath.Join(r.Dir, "thumb", id+".jpg") }

func (r *Run) generateCell(ctx context.Context, c ManifestCell) error {
	if r.Spec.Dry {
		data := Placeholder(832, 1216, c.ID)
		if err := writeFile(r.imgPath(c.ID), data); err != nil {
			return err
		}
		return writeFile(r.thumbPath(c.ID), Placeholder(213, 320, c.ID))
	}
	raw, err := os.ReadFile(filepath.Join(r.Dir, "wf", c.ID+".json"))
	if err != nil {
		return err
	}
	var wf map[string]any
	if err := json.Unmarshal(raw, &wf); err != nil {
		return err
	}
	promptID, err := r.env.Comfy.Submit(wf, "lab-"+r.state.ID)
	if err != nil {
		return err
	}
	r.update(func(s *RunState) {
		cs := s.Cells[c.ID]
		cs.PromptID = promptID
		s.Cells[c.ID] = cs
	})
	deadline := time.Now().Add(30 * time.Minute)
	for {
		select {
		case <-ctx.Done():
			return fmt.Errorf("zrušeno")
		case <-time.After(3 * time.Second):
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("timeout: %s se nedokončil do 30 min", promptID)
		}
		hist, err := r.env.Comfy.History(promptID)
		if err != nil {
			return err
		}
		if hist == nil {
			if q, qerr := r.env.Comfy.Queue(); qerr == nil {
				r.update(func(s *RunState) { s.Queue = q })
			}
			continue
		}
		if hist.Status.StatusStr == "error" {
			return fmt.Errorf("ComfyUI: běh skončil chybou")
		}
		images := hist.SavedImages()
		if len(images) == 0 {
			continue
		}
		data, err := r.env.Comfy.Download(images[0])
		if err != nil {
			return err
		}
		if err := writeFile(r.imgPath(c.ID), data); err != nil {
			return err
		}
		thumb, err := Thumbnail(data, thumbMax)
		if err != nil {
			return err
		}
		return writeFile(r.thumbPath(c.ID), thumb)
	}
}

func (r *Run) computeMetrics() {
	man := r.Manifest()
	if man == nil {
		return
	}
	hist := map[string][]float64{}
	for _, c := range man.Cells {
		data, err := os.ReadFile(r.imgPath(c.ID))
		if err != nil {
			continue
		}
		h, err := Histogram(data)
		if err != nil {
			continue
		}
		hist[c.ID] = h
	}
	m := ComputeMetrics(man.Cells, hist)
	data, _ := json.MarshalIndent(m, "", " ")
	_ = os.WriteFile(filepath.Join(r.Dir, "metrics.json"), data, 0o644)
}

// Reconcile rebuilds cell state from what is actually on disk. A run killed
// mid-flight (server restart, Ctrl+C) leaves cells marked "running" that never
// finished, and the counters have to come from the images, not from memory.
func (r *Run) Reconcile() {
	man := r.Manifest()
	if man == nil {
		return
	}
	r.update(func(s *RunState) {
		s.Cells = make(map[string]CellState, len(man.Cells))
		s.Done, s.Failed = 0, 0
		s.Total = len(man.Cells)
		for _, c := range man.Cells {
			if _, err := os.Stat(r.imgPath(c.ID)); err == nil {
				s.Cells[c.ID] = CellState{ID: c.ID, Status: CellDone}
				s.Done++
			} else {
				s.Cells[c.ID] = CellState{ID: c.ID, Status: CellPending}
			}
		}
		s.Message = fmt.Sprintf("navazuji — %d z %d už hotovo", s.Done, s.Total)
	})
}

// Resume re-enters the pipeline. Cells with an image on disk are skipped, so
// picking a run back up costs only what is genuinely missing.
func (r *Run) Resume() {
	if r.Manifest() == nil {
		if err := r.Dump(); err != nil {
			return
		}
	}
	r.Reconcile()
	r.Generate()
}

func (r *Run) Cancel() {
	r.mu.Lock()
	c := r.cancel
	r.mu.Unlock()
	if c != nil {
		c()
	}
}

func asHTTPError(err error, out **HTTPError) bool {
	he, ok := err.(*HTTPError)
	if ok {
		*out = he
	}
	return ok
}

func tailLines(s string, n int) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return strings.Join(lines, " / ")
}
