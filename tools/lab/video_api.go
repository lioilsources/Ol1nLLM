package main

import (
	"context"
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/lioilsources/ol1n-lab/internal/video"
)

// The video studio's API (docs/plan-video-studio.md §9). Everything is local:
// the collection comes from build/lab, recipes and videos live in
// build/lab/_video/<name>/.

type videoAPI struct {
	labDir string

	mu       sync.Mutex
	col      *video.Collection
	loadedAt time.Time
	plans    map[string]*video.Storyboard // by id, the last few
	planIDs  []string

	jobsMu sync.Mutex
	jobs   map[string]*renderJob
	order  []string
	queue  chan *renderJob
}

type renderJob struct {
	ID      string         `json:"id"`
	Name    string         `json:"name"`
	Status  string         `json:"status"` // queued | running | done | failed | cancelled
	Error   string         `json:"error,omitempty"`
	Parts   int            `json:"parts"`
	Seconds float64        `json:"seconds"`
	Created time.Time      `json:"created"`
	Prog    video.Progress `json:"progress"`
	Done    []video.Done   `json:"done,omitempty"`
	Dir     string         `json:"dir"`

	sb     *video.Storyboard
	only   []string
	draft  bool
	cancel context.CancelFunc
	subs   map[chan renderJob]struct{}
}

func newVideoAPI(labDir string) *videoAPI {
	a := &videoAPI{labDir: labDir, plans: map[string]*video.Storyboard{}, jobs: map[string]*renderJob{},
		queue: make(chan *renderJob, 64)}
	go a.worker()
	return a
}

func (a *videoAPI) routes(mux *http.ServeMux, guard func(http.HandlerFunc) http.HandlerFunc) {
	mux.HandleFunc("/api/video/index", guard(a.handleIndex))
	mux.HandleFunc("/api/video/coverage", guard(a.handleCoverage))
	mux.HandleFunc("/api/video/suggest", guard(a.handleSuggest))
	mux.HandleFunc("/api/video/template", guard(a.handleTemplate))
	mux.HandleFunc("/api/video/yaml", guard(a.handleYAML))
	mux.HandleFunc("/api/video/parse", guard(a.handleParse))
	mux.HandleFunc("/api/video/plan", guard(a.handlePlan))
	mux.HandleFunc("/api/video/plans/", guard(a.handlePlanSlides))
	mux.HandleFunc("/api/video/recipes", guard(a.handleRecipes))
	mux.HandleFunc("/api/video/recipes/", guard(a.handleRecipe))
	mux.HandleFunc("/api/video/render", guard(a.handleRender))
	mux.HandleFunc("/api/video/jobs", guard(a.handleJobs))
	mux.HandleFunc("/api/video/jobs/", guard(a.handleJob))
	mux.HandleFunc("/api/video/outputs", guard(a.handleOutputs))
	mux.HandleFunc("/api/video/reveal", guard(a.handleReveal))
}

// collection reloads the index when asked or when older than 20 s: a run
// drawing in the background keeps adding pictures.
func (a *videoAPI) collection(refresh bool) (*video.Collection, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if refresh {
		_ = video.ClearCache(a.labDir)
	}
	if a.col == nil || refresh || time.Since(a.loadedAt) > 20*time.Second {
		col, err := video.Load(a.labDir)
		if err != nil {
			return nil, err
		}
		a.col, a.loadedAt = col, time.Now()
	}
	return a.col, nil
}

func decode(r *http.Request, v any) error {
	if r.Method != http.MethodPost && r.Method != http.MethodPut {
		return fmt.Errorf("čekám POST")
	}
	return json.NewDecoder(io.LimitReader(r.Body, 4<<20)).Decode(v)
}

func apiErr(w http.ResponseWriter, status int, err error) {
	var pe *video.PlanError
	if errors.As(err, &pe) {
		writeJSON(w, 422, map[string]any{"error": pe.Error(), "problems": pe.Problems, "missing": pe.Missing})
		return
	}
	writeJSON(w, status, map[string]string{"error": err.Error()})
}

// ── index ───────────────────────────────────────────────────

type runView struct {
	ID          string            `json:"id"`
	Title       string            `json:"title"`
	Status      string            `json:"status"`
	Created     time.Time         `json:"created"`
	Total       int               `json:"total"`
	Pics        int               `json:"pics"`
	Empty       int               `json:"empty"`
	Family      string            `json:"family"`
	Styles      int               `json:"styles"`
	Placeholder bool              `json:"placeholder,omitempty"`
	Models      []video.Labelled  `json:"models"`
	Flows       map[string]int    `json:"flows"`
	Setup       map[string]string `json:"-"`
}

func viewRun(r *video.Run) runView {
	v := runView{ID: r.ID, Title: r.Title, Status: r.Status, Created: r.Created, Total: r.Total,
		Pics: len(r.Pics), Empty: r.Empty, Family: r.Family, Styles: r.StyleCount(),
		Placeholder: r.Placeholder, Flows: map[string]int{}}
	label := map[string]string{}
	for _, m := range r.Models {
		label[m.ID] = m.Label
	}
	count := map[string]int{}
	var order []string
	for _, p := range r.Pics {
		if count[p.Model] == 0 {
			order = append(order, p.Model)
		}
		count[p.Model]++
		v.Flows[p.Flow]++
	}
	for _, m := range order {
		l := label[m]
		if l == "" {
			l = m
		}
		v.Models = append(v.Models, video.Labelled{ID: m, Label: l, N: count[m]})
	}
	return v
}

func (a *videoAPI) handleIndex(w http.ResponseWriter, r *http.Request) {
	col, err := a.collection(r.URL.Query().Get("refresh") == "1")
	if err != nil {
		apiErr(w, 500, err)
		return
	}
	var runs []runView
	for _, run := range col.Runs {
		if len(run.Pics) > 0 {
			runs = append(runs, viewRun(run))
		}
	}
	sort.Slice(runs, func(i, j int) bool { return runs[i].ID > runs[j].ID })
	type tmpl struct{ ID, Name, What string }
	var tmpls []tmpl
	for _, t := range video.Templates {
		tmpls = append(tmpls, tmpl{t.ID, t.Name, t.What})
	}
	writeJSON(w, 200, map[string]any{
		"families": col.Families(1), "runs": runs, "errors": col.Errors, "templates": tmpls,
		"axes": video.AllAxes, "axisNames": axisNames(), "audio": a.tracks(),
	})
}

// audioTrack: a track for time.sync, from build/lab/_video/_audio.
type audioTrack struct {
	Path  string `json:"path"` // relative to build/lab, as the recipe takes it
	Name  string `json:"name"`
	URL   string `json:"url"`
	Bytes int64  `json:"bytes"`
}

func (a *videoAPI) tracks() []audioTrack {
	out := []audioTrack{}
	entries, err := os.ReadDir(filepath.Join(a.videoDir(), "_audio"))
	if err != nil {
		return out
	}
	for _, e := range entries {
		ext := strings.ToLower(filepath.Ext(e.Name()))
		if e.IsDir() || strings.HasPrefix(e.Name(), ".") || !audioExt[ext] {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		rel := "_video/_audio/" + e.Name()
		out = append(out, audioTrack{Path: rel, Name: strings.TrimSuffix(e.Name(), filepath.Ext(e.Name())),
			URL: "/media/" + rel, Bytes: info.Size()})
	}
	return out
}

var audioExt = map[string]bool{".mp3": true, ".wav": true, ".flac": true, ".m4a": true, ".aac": true, ".ogg": true}

func axisNames() map[string]string {
	out := map[string]string{}
	for _, a := range video.AllAxes {
		out[a] = video.AxisName(a)
	}
	return out
}

// ── pool-based questions ────────────────────────────────────

type poolReq struct {
	Source video.Source     `json:"source"`
	Select video.SelectSpec `json:"select"`
}

func (a *videoAPI) pool(req poolReq) (*video.Pool, error) {
	col, err := a.collection(false)
	if err != nil {
		return nil, err
	}
	r := video.Recipe{Source: req.Source}
	r.Defaults()
	runs, err := sourceRuns(col, req.Source)
	if err != nil {
		return nil, err
	}
	p, err := video.NewPool(runs, req.Source.PromptIdentity, r.Source.Prefer)
	if err != nil {
		return nil, err
	}
	sel := video.Selection{Only: map[string][]string{}, Not: map[string][]string{}}
	for axis, f := range req.Select {
		if axis == video.MinReaction {
			continue // a filter on pictures, not an axis; the plan applies it
		}
		if len(f.Only) > 0 {
			sel.Only[axis] = f.Only
		}
		if len(f.Not) > 0 {
			sel.Not[axis] = f.Not
		}
		sel.Kinds = append(sel.Kinds, f.Kind...)
	}
	return p.Select(sel), nil
}

func sourceRuns(col *video.Collection, s video.Source) ([]*video.Run, error) {
	if s.Family != "" {
		if runs := col.FamilyOf(s.Family); runs != nil {
			return runs, nil
		}
		return nil, fmt.Errorf("běh %s není nebo nemá obrázky", s.Family)
	}
	if len(s.Runs) == 0 {
		return nil, fmt.Errorf("vyber aspoň jeden běh")
	}
	var runs []*video.Run
	for _, id := range s.Runs {
		r := col.Run(id)
		if r == nil {
			return nil, fmt.Errorf("běh %s v build/lab není", id)
		}
		runs = append(runs, r)
	}
	return runs, nil
}

func (a *videoAPI) handleCoverage(w http.ResponseWriter, r *http.Request) {
	var req struct {
		poolReq
		Rows, Cols, Count string
	}
	if err := decode(r, &req); err != nil {
		apiErr(w, 400, err)
		return
	}
	p, err := a.pool(req.poolReq)
	if err != nil {
		apiErr(w, 400, err)
		return
	}
	cov, err := p.Coverage(orStr(req.Rows, video.AxModel), orStr(req.Cols, video.AxStyle), orStr(req.Count, video.AxPrompt))
	if err != nil {
		apiErr(w, 400, err)
		return
	}
	// Everything the pool holds, for the selection chips.
	axes := map[string][]video.Labelled{}
	for _, ax := range video.ContentAxes {
		vals := p.Values(ax)
		var out []video.Labelled
		for _, v := range vals {
			l := video.Labelled{ID: v, Label: p.Label(ax, v)}
			if ax == video.AxStyle {
				l.Kind = p.Style(v).Kind
			}
			out = append(out, l)
		}
		axes[ax] = out
	}
	writeJSON(w, 200, map[string]any{"coverage": cov, "axes": axes, "pictures": len(p.Pics),
		"collisions": len(p.Collisions), "differentSetups": p.DifferentSetups, "identity": p.Identity})
}

func (a *videoAPI) handleSuggest(w http.ResponseWriter, r *http.Request) {
	var req struct {
		poolReq
		Tiles string   `json:"tiles"`
		Loose []string `json:"loose"`
		K     int      `json:"k"`
		Top   int      `json:"top"`
	}
	if err := decode(r, &req); err != nil {
		apiErr(w, 400, err)
		return
	}
	p, err := a.pool(req.poolReq)
	if err != nil {
		apiErr(w, 400, err)
		return
	}
	// Suggestions choose the tile values themselves: drop the selection of
	// the tile axis.
	sg, err := p.Suggest(orStr(req.Tiles, video.AxModel), req.Loose, req.K, req.Top)
	if err != nil {
		apiErr(w, 400, err)
		return
	}
	type kRow struct {
		K       int                `json:"k"`
		Strict  []video.Suggestion `json:"strict"`
		ByLoose []video.Suggestion `json:"loose"`
	}
	var rows []kRow
	for _, k := range sg.Ks() {
		rows = append(rows, kRow{K: k, Strict: sg.ByK[k], ByLoose: sg.ByLoose[k]})
	}
	writeJSON(w, 200, map[string]any{"values": sg.Values, "rows": rows, "note": sg.Note})
}

func (a *videoAPI) handleTemplate(w http.ResponseWriter, r *http.Request) {
	var req struct {
		poolReq
		Template string `json:"template"`
		Name     string `json:"name"`
	}
	if err := decode(r, &req); err != nil {
		apiErr(w, 400, err)
		return
	}
	id, err := video.TemplateID(req.Template)
	if err != nil {
		apiErr(w, 400, err)
		return
	}
	p, err := a.pool(req.poolReq)
	if err != nil {
		apiErr(w, 400, err)
		return
	}
	name := req.Name
	if name == "" {
		name = id
	}
	rec, notes := video.FromTemplate(id, name, req.Source, p)
	for axis, f := range req.Select {
		if rec.Select == nil {
			rec.Select = video.SelectSpec{}
		}
		if _, set := rec.Select[axis]; !set {
			rec.Select[axis] = f
		}
	}
	rec.Defaults()
	writeJSON(w, 200, map[string]any{"recipe": rec, "notes": notes})
}

// ── recipes as YAML ─────────────────────────────────────────

// recipeIn is a recipe as the studio sends it: the structured object, or
// YAML text (the editor tab).
type recipeIn struct {
	Recipe *video.Recipe `json:"recipe"`
	YAML   string        `json:"yaml"`
}

func (in recipeIn) parse() (video.Recipe, error) {
	if in.YAML != "" {
		rs, err := video.ParseRecipes([]byte(in.YAML))
		if err != nil {
			return video.Recipe{}, err
		}
		if len(rs) > 1 {
			return video.Recipe{}, fmt.Errorf("studio pracuje s jedním receptem, soubor jich má %d", len(rs))
		}
		return rs[0], nil
	}
	if in.Recipe == nil {
		return video.Recipe{}, fmt.Errorf("chybí recept")
	}
	r := *in.Recipe
	r.Defaults()
	return r, r.Validate()
}

func (a *videoAPI) handleYAML(w http.ResponseWriter, r *http.Request) {
	var in recipeIn
	if err := decode(r, &in); err != nil {
		apiErr(w, 400, err)
		return
	}
	if in.Recipe == nil {
		apiErr(w, 400, fmt.Errorf("chybí recept"))
		return
	}
	rec := *in.Recipe
	rec.Defaults()
	y, err := video.MarshalRecipe(rec)
	if err != nil {
		apiErr(w, 500, err)
		return
	}
	writeJSON(w, 200, map[string]string{"yaml": string(y)})
}

func (a *videoAPI) handleParse(w http.ResponseWriter, r *http.Request) {
	var in recipeIn
	if err := decode(r, &in); err != nil {
		apiErr(w, 400, err)
		return
	}
	rec, err := in.parse()
	if err != nil {
		apiErr(w, 422, err)
		return
	}
	writeJSON(w, 200, map[string]any{"recipe": rec})
}

// ── plan ────────────────────────────────────────────────────

func (a *videoAPI) handlePlan(w http.ResponseWriter, r *http.Request) {
	var in recipeIn
	if err := decode(r, &in); err != nil {
		apiErr(w, 400, err)
		return
	}
	rec, err := in.parse()
	if err != nil {
		apiErr(w, 422, err)
		return
	}
	col, err := a.collection(false)
	if err != nil {
		apiErr(w, 500, err)
		return
	}
	sb, err := video.PlanSynced(r.Context(), col, rec, a.labDir, "")
	if err != nil {
		apiErr(w, 422, err)
		return
	}
	id := a.keepPlan(sb)
	summary := *sb
	summary.Slides = nil
	writeJSON(w, 200, map[string]any{"id": id, "storyboard": summary, "slides": len(sb.Slides)})
}

func (a *videoAPI) keepPlan(sb *video.Storyboard) string {
	data, _ := json.Marshal(sb.Recipe)
	sum := sha1.Sum(append(data, []byte(a.loadedAt.String())...))
	id := hex.EncodeToString(sum[:])[:12]
	a.mu.Lock()
	defer a.mu.Unlock()
	if _, ok := a.plans[id]; !ok {
		a.planIDs = append(a.planIDs, id)
		if len(a.planIDs) > 8 {
			delete(a.plans, a.planIDs[0])
			a.planIDs = a.planIDs[1:]
		}
	}
	a.plans[id] = sb
	return id
}

// GET /api/video/plans/{id}/slides?from=&to=
func (a *videoAPI) handlePlanSlides(w http.ResponseWriter, r *http.Request) {
	rest := strings.TrimPrefix(r.URL.Path, "/api/video/plans/")
	id, tail, _ := strings.Cut(rest, "/")
	if tail != "slides" {
		http.NotFound(w, r)
		return
	}
	a.mu.Lock()
	sb := a.plans[id]
	a.mu.Unlock()
	if sb == nil {
		apiErr(w, 404, fmt.Errorf("plán vypršel — naplánuj znovu"))
		return
	}
	from, _ := strconv.Atoi(r.URL.Query().Get("from"))
	to, err := strconv.Atoi(r.URL.Query().Get("to"))
	if err != nil || to > len(sb.Slides) {
		to = len(sb.Slides)
	}
	from = max(0, min(from, to))
	writeJSON(w, 200, map[string]any{"from": from, "to": to, "slides": sb.Slides[from:to]})
}

// ── saved recipes ───────────────────────────────────────────

func (a *videoAPI) videoDir() string { return filepath.Join(a.labDir, "_video") }

func (a *videoAPI) handleRecipes(w http.ResponseWriter, r *http.Request) {
	entries, _ := os.ReadDir(a.videoDir())
	type item struct {
		Name     string    `json:"name"`
		Modified time.Time `json:"modified"`
		Videos   int       `json:"videos"`
	}
	var out []item
	for _, e := range entries {
		if !e.IsDir() || strings.HasPrefix(e.Name(), ".") {
			continue
		}
		st, err := os.Stat(filepath.Join(a.videoDir(), e.Name(), "recipe.yaml"))
		if err != nil {
			continue
		}
		mp4s, _ := filepath.Glob(filepath.Join(a.videoDir(), e.Name(), "*.mp4"))
		n := 0
		for _, m := range mp4s {
			if !strings.HasSuffix(m, ".part.mp4") {
				n++
			}
		}
		out = append(out, item{Name: e.Name(), Modified: st.ModTime(), Videos: n})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Modified.After(out[j].Modified) })
	writeJSON(w, 200, out)
}

func validName(n string) bool {
	if n == "" || strings.HasPrefix(n, ".") || strings.ContainsAny(n, "/\\") {
		return false
	}
	return filepath.Base(n) == n
}

// GET/PUT/DELETE /api/video/recipes/{name}
func (a *videoAPI) handleRecipe(w http.ResponseWriter, r *http.Request) {
	name := strings.TrimPrefix(r.URL.Path, "/api/video/recipes/")
	if !validName(name) {
		apiErr(w, 400, fmt.Errorf("neplatné jméno receptu"))
		return
	}
	path := filepath.Join(a.videoDir(), name, "recipe.yaml")
	switch r.Method {
	case http.MethodGet:
		data, err := os.ReadFile(path)
		if err != nil {
			apiErr(w, 404, fmt.Errorf("recept %s není", name))
			return
		}
		rs, err := video.ParseRecipes(data)
		if err != nil {
			writeJSON(w, 200, map[string]any{"yaml": string(data), "error": err.Error()})
			return
		}
		writeJSON(w, 200, map[string]any{"yaml": string(data), "recipe": rs[0]})
	case http.MethodPut:
		var in recipeIn
		if err := decode(r, &in); err != nil {
			apiErr(w, 400, err)
			return
		}
		rec, err := in.parse()
		if err != nil {
			apiErr(w, 422, err)
			return
		}
		rec.Name = name
		y, err := video.MarshalRecipe(rec)
		if err != nil {
			apiErr(w, 500, err)
			return
		}
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			apiErr(w, 500, err)
			return
		}
		if err := os.WriteFile(path, y, 0o644); err != nil {
			apiErr(w, 500, err)
			return
		}
		writeJSON(w, 200, map[string]any{"name": name, "yaml": string(y)})
	case http.MethodDelete:
		// Only the recipe: the videos next to it stay until removed by hand.
		if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
			apiErr(w, 500, err)
			return
		}
		writeJSON(w, 200, map[string]string{"deleted": name})
	default:
		http.Error(w, "GET/PUT/DELETE", http.StatusMethodNotAllowed)
	}
}

// ── render queue ────────────────────────────────────────────

func (a *videoAPI) handleRender(w http.ResponseWriter, r *http.Request) {
	var in struct {
		recipeIn
		Only  []string `json:"only"`
		Draft bool     `json:"draft"`
	}
	if err := decode(r, &in); err != nil {
		apiErr(w, 400, err)
		return
	}
	rec, err := in.parse()
	if err != nil {
		apiErr(w, 422, err)
		return
	}
	col, err := a.collection(false)
	if err != nil {
		apiErr(w, 500, err)
		return
	}
	sb, err := video.PlanSynced(r.Context(), col, rec, a.labDir, "")
	if err != nil {
		apiErr(w, 422, err)
		return
	}
	parts := 0
	secs := 0.0
	for _, v := range sb.Videos {
		if len(in.Only) == 0 || hasString(in.Only, v.Name) {
			parts++
			secs += v.Seconds
		}
	}
	if parts == 0 {
		apiErr(w, 400, fmt.Errorf("žádný díl ke zpracování"))
		return
	}
	job := &renderJob{
		ID: strconv.FormatInt(time.Now().UnixNano(), 36), Name: sb.Recipe.Name, Status: "queued",
		Parts: parts, Seconds: secs, Created: time.Now(), sb: sb, only: in.Only, draft: in.Draft,
		Dir: filepath.Join(a.videoDir(), sb.Recipe.Name), subs: map[chan renderJob]struct{}{},
	}
	a.jobsMu.Lock()
	a.jobs[job.ID] = job
	a.order = append(a.order, job.ID)
	a.jobsMu.Unlock()
	a.queue <- job
	writeJSON(w, 200, job.snapshot(&a.jobsMu))
}

func (j *renderJob) snapshot(mu *sync.Mutex) renderJob {
	mu.Lock()
	defer mu.Unlock()
	return j.copy()
}

func (j *renderJob) copy() renderJob {
	c := *j
	c.sb, c.cancel, c.subs = nil, nil, nil
	c.Done = append([]video.Done{}, j.Done...)
	return c
}

func (a *videoAPI) update(j *renderJob, f func(*renderJob)) {
	a.jobsMu.Lock()
	f(j)
	snap := j.copy()
	subs := make([]chan renderJob, 0, len(j.subs))
	for ch := range j.subs {
		subs = append(subs, ch)
	}
	a.jobsMu.Unlock()
	for _, ch := range subs {
		select {
		case ch <- snap:
		default: // a slow listener misses an intermediate state, not the last one
		}
	}
}

// worker renders one job at a time: the encoder takes the whole machine.
func (a *videoAPI) worker() {
	for job := range a.queue {
		a.jobsMu.Lock()
		cancelled := job.Status == "cancelled"
		a.jobsMu.Unlock()
		if cancelled {
			continue
		}
		ctx, cancel := context.WithCancel(context.Background())
		a.update(job, func(j *renderJob) { j.Status, j.cancel = "running", cancel })
		done, err := video.Render(ctx, job.sb, video.RenderOptions{
			LabDir: a.labDir, OutDir: job.Dir, Only: job.only, Thumbs: job.draft,
			Progress: func(p video.Progress) { a.update(job, func(j *renderJob) { j.Prog = p }) },
		})
		cancel()
		a.update(job, func(j *renderJob) {
			j.Done = done
			switch {
			case ctx.Err() != nil:
				j.Status = "cancelled"
			case err != nil:
				j.Status, j.Error = "failed", err.Error()
			default:
				j.Status = "done"
			}
		})
	}
}

func (a *videoAPI) handleJobs(w http.ResponseWriter, r *http.Request) {
	a.jobsMu.Lock()
	out := make([]renderJob, 0, len(a.order))
	for i := len(a.order) - 1; i >= 0; i-- {
		out = append(out, a.jobs[a.order[i]].copy())
	}
	a.jobsMu.Unlock()
	writeJSON(w, 200, out)
}

// GET /api/video/jobs/{id} — server-sent events until the job ends;
// DELETE cancels it.
func (a *videoAPI) handleJob(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/api/video/jobs/")
	a.jobsMu.Lock()
	job := a.jobs[id]
	a.jobsMu.Unlock()
	if job == nil {
		apiErr(w, 404, fmt.Errorf("úloha %s není", id))
		return
	}
	if r.Method == http.MethodDelete {
		a.update(job, func(j *renderJob) {
			if j.cancel != nil {
				j.cancel()
			}
			if j.Status == "queued" {
				j.Status = "cancelled"
			}
		})
		writeJSON(w, 200, job.snapshot(&a.jobsMu))
		return
	}
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeJSON(w, 200, job.snapshot(&a.jobsMu))
		return
	}
	ch := make(chan renderJob, 8)
	a.jobsMu.Lock()
	job.subs[ch] = struct{}{}
	first := job.copy()
	a.jobsMu.Unlock()
	defer func() {
		a.jobsMu.Lock()
		delete(job.subs, ch)
		a.jobsMu.Unlock()
	}()
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	send := func(j renderJob) bool {
		data, _ := json.Marshal(j)
		_, _ = fmt.Fprintf(w, "data: %s\n\n", data)
		flusher.Flush()
		return j.Status == "done" || j.Status == "failed" || j.Status == "cancelled"
	}
	if send(first) {
		return
	}
	for {
		select {
		case <-r.Context().Done():
			return
		case j := <-ch:
			if send(j) {
				return
			}
		case <-time.After(20 * time.Second):
			_, _ = io.WriteString(w, ": ping\n\n")
			flusher.Flush()
		}
	}
}

// ── outputs ─────────────────────────────────────────────────

func (a *videoAPI) handleOutputs(w http.ResponseWriter, r *http.Request) {
	type file struct {
		Name    string    `json:"name"`
		URL     string    `json:"url"`
		Bytes   int64     `json:"bytes"`
		Seconds float64   `json:"seconds"`
		Mod     time.Time `json:"modified"`
	}
	type set struct {
		Name  string `json:"name"`
		Files []file `json:"files"`
	}
	var out []set
	entries, _ := os.ReadDir(a.videoDir())
	for _, e := range entries {
		if !e.IsDir() || strings.HasPrefix(e.Name(), ".") {
			continue
		}
		dir := filepath.Join(a.videoDir(), e.Name())
		seconds := map[string]float64{}
		if data, err := os.ReadFile(filepath.Join(dir, "storyboard.json")); err == nil {
			var sb video.Storyboard
			if json.Unmarshal(data, &sb) == nil {
				for _, v := range sb.Videos {
					seconds[v.Name+".mp4"] = v.Seconds
				}
			}
		}
		s := set{Name: e.Name()}
		_ = filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
			if err != nil || d.IsDir() || !strings.HasSuffix(p, ".mp4") || strings.HasSuffix(p, ".part.mp4") {
				return nil
			}
			info, err := d.Info()
			if err != nil {
				return nil
			}
			rel, _ := filepath.Rel(a.labDir, p)
			s.Files = append(s.Files, file{Name: d.Name(), Bytes: info.Size(), Mod: info.ModTime(),
				Seconds: seconds[d.Name()],
				URL:     "/media/" + filepath.ToSlash(rel) + "?v=" + strconv.FormatInt(info.ModTime().UnixNano(), 36)})
			return nil
		})
		if len(s.Files) > 0 {
			out = append(out, s)
		}
	}
	writeJSON(w, 200, out)
}

// POST /api/video/reveal {"path": "<name>/<file>.mp4"} — Finder, only inside _video.
func (a *videoAPI) handleReveal(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Path string `json:"path"`
	}
	if err := decode(r, &in); err != nil {
		apiErr(w, 400, err)
		return
	}
	base := a.videoDir()
	full := filepath.Join(base, filepath.Clean("/"+in.Path))
	if !strings.HasPrefix(full, base+string(os.PathSeparator)) {
		apiErr(w, 400, fmt.Errorf("mimo build/lab/_video"))
		return
	}
	if _, err := os.Stat(full); err != nil {
		apiErr(w, 404, err)
		return
	}
	if err := exec.Command("open", "-R", full).Start(); err != nil {
		apiErr(w, 500, err)
		return
	}
	writeJSON(w, 200, map[string]string{"revealed": in.Path})
}

func orStr(s, def string) string {
	if s == "" {
		return def
	}
	return s
}
