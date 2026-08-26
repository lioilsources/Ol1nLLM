package main

import (
	"crypto/rand"
	"embed"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

//go:embed static
var staticFS embed.FS

type Server struct {
	env      *Env
	forceDry bool
	token    string
	mu       sync.Mutex
	runs     map[string]*Run
	active   string
	cache    struct {
		checkpoints []string
		samplers    []string
		schedulers  []string
		at          time.Time
	}
}

func serve(env *Env, port int, open, forceDry bool) error {
	s := &Server{env: env, forceDry: forceDry, runs: map[string]*Run{}, token: newToken()}
	s.loadRuns()

	mux := http.NewServeMux()
	sub, _ := fs.Sub(staticFS, "static")
	mux.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.FS(sub))))
	mux.HandleFunc("/", s.guard(s.handleIndex))
	mux.HandleFunc("/api/health", s.guard(s.handleHealth))
	mux.HandleFunc("/api/config", s.guard(s.handleConfig))
	mux.HandleFunc("/api/estimate", s.guard(s.handleEstimate))
	mux.HandleFunc("/api/upload-ref", s.guard(s.handleUploadRef))
	mux.HandleFunc("/api/runs", s.guard(s.handleRuns))
	mux.HandleFunc("/api/runs/", s.guard(s.handleRun))
	mux.HandleFunc("/media/", s.guard(s.handleMedia))

	addr := fmt.Sprintf("127.0.0.1:%d", port)
	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return fmt.Errorf("%s", bindHelp(addr, port, err))
	}
	url := fmt.Sprintf("http://%s/?t=%s", addr, s.token)
	fmt.Printf("lab běží na %s\n", url)
	if !env.Comfy.HasCreds() {
		fmt.Println("  (bez CF Access creds — dry-run funguje, ostrý běh ne)")
	}
	if open {
		_ = exec.Command("open", url).Start()
	}
	srv := &http.Server{Handler: mux, ReadHeaderTimeout: 10 * time.Second}
	return srv.Serve(ln)
}

// bindHelp turns "address already in use" into something actionable: usually
// it is another lab still running, and the useful answer is its URL, not the
// syscall error.
func bindHelp(addr string, port int, err error) string {
	if !strings.Contains(err.Error(), "in use") {
		return fmt.Sprintf("port %d: %v", port, err)
	}
	client := &http.Client{Timeout: 2 * time.Second}
	resp, herr := client.Get("http://" + addr + "/api/health")
	if herr == nil {
		defer resp.Body.Close()
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
		if strings.Contains(string(body), "repoRoot") {
			return fmt.Sprintf("na portu %d už jeden lab běží — otevři http://%s/ "+
				"(token vypsala ta instance), ukonči ji, nebo zvol --port %d",
				port, addr, port+1)
		}
	}
	return fmt.Sprintf("port %d obsazený něčím jiným — zvol --port %d "+
		"(kdo port drží: lsof -nP -iTCP:%d -sTCP:LISTEN)", port, port+1, port)
}

func newToken() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// guard keeps a page on some other origin from driving this server — it holds
// CF Access credentials, and any tab in the browser can POST to localhost.
func (s *Server) guard(h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if origin := r.Header.Get("Origin"); origin != "" {
			if !strings.HasSuffix(origin, r.Host) {
				http.Error(w, "cizí origin", http.StatusForbidden)
				return
			}
		}
		if r.Method != http.MethodGet && r.Header.Get("X-Lab-Token") != s.token {
			http.Error(w, "chybí X-Lab-Token", http.StatusForbidden)
			return
		}
		h(w, r)
	}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	data, err := json.Marshal(v)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Content-Length", fmt.Sprint(len(data)))
	w.WriteHeader(status)
	_, _ = w.Write(data)
}

func (s *Server) handleIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	data, err := staticFS.ReadFile("static/index.html")
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	body := strings.ReplaceAll(string(data), "__LAB_TOKEN__", s.token)
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Content-Length", fmt.Sprint(len(body)))
	_, _ = io.WriteString(w, body)
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	out := map[string]any{
		"flutter":  map[string]any{"ok": s.env.FlutterOK, "msg": s.env.FlutterMsg},
		"cfAccess": s.env.Comfy.HasCreds(),
		"comfyUrl": s.env.ComfyURL,
		"forceDry": s.forceDry,
		"repoRoot": s.env.RepoRoot,
	}
	if s.env.Comfy.HasCreds() {
		if q, err := s.env.Comfy.Queue(); err == nil {
			out["queue"] = q
			out["comfyOk"] = true
		} else {
			out["comfyOk"] = false
			out["comfyErr"] = err.Error()
		}
	}
	writeJSON(w, 200, out)
}

// handleConfig ships the registries. They come from dump.dart's manifest, so
// Dart stays the single source of truth for models, styles and poses.
func (s *Server) handleConfig(w http.ResponseWriter, r *http.Request) {
	man, err := s.registries()
	if err != nil {
		writeJSON(w, 500, map[string]string{"error": err.Error()})
		return
	}
	s.refreshOptions()
	writeJSON(w, 200, map[string]any{
		"models":     man.Models,
		"styles":     man.Styles,
		"poses":      man.Poses,
		"buckets":    man.Buckets,
		"samplers":   s.cache.samplers,
		"schedulers": s.cache.schedulers,
		"copy":       copyCS,
		"maxCells":   MaxCells,
		"confirm":    ConfirmCells,
	})
}

// registries runs a one-cell dump purely to read the app's registries back.
func (s *Server) registries() (*Manifest, error) {
	dir := filepath.Join(s.env.RepoRoot, "build", "lab", "_registry")
	manPath := filepath.Join(dir, "wf", "manifest.json")
	if st, err := os.Stat(manPath); err == nil && time.Since(st.ModTime()) < time.Hour {
		return ReadManifest(manPath)
	}
	if !s.env.FlutterOK {
		return nil, fmt.Errorf("flutter není použitelný: %s", s.env.FlutterMsg)
	}
	_ = os.MkdirAll(filepath.Join(dir, "wf"), 0o755)
	// No MODELS/STYLES filter: the manifest's registries are the point, and
	// LIMIT keeps it to a single emitted workflow so the probe stays cheap.
	spec := &Spec{
		Prompts: []string{"registry probe"}, Flows: []string{"txt2img"},
		Seed: 1, Batch: 1,
	}
	env, err := spec.DumpEnv(dir)
	if err != nil {
		return nil, err
	}
	env = append(env, "LIMIT=1")
	// Prune to what the server can actually run, so the picker never offers a
	// model whose checkpoint is missing.
	s.refreshOptions()
	if len(s.cache.checkpoints) > 0 {
		ckPath := filepath.Join(dir, "ckpts.txt")
		if err := os.WriteFile(ckPath,
			[]byte(strings.Join(s.cache.checkpoints, "\n")), 0o644); err == nil {
			env = append(env, "CKPTS="+ckPath)
		}
	}
	cmd := exec.Command("flutter", "test", "tools/lab/dump.dart")
	cmd.Dir = s.env.RepoRoot
	cmd.Env = env
	if out, err := cmd.CombinedOutput(); err != nil {
		if _, statErr := os.Stat(manPath); statErr != nil {
			return nil, fmt.Errorf("registry dump: %v — %s", err, tailLines(string(out), 4))
		}
	}
	return ReadManifest(manPath)
}

func (s *Server) refreshOptions() {
	if time.Since(s.cache.at) < 5*time.Minute || !s.env.Comfy.HasCreds() {
		return
	}
	if ck, err := s.env.Comfy.Checkpoints(); err == nil {
		s.cache.checkpoints = ck
	}
	if sa, sc, err := s.env.Comfy.Samplers(); err == nil {
		s.cache.samplers, s.cache.schedulers = sa, sc
	}
	s.cache.at = time.Now()
}

func (s *Server) handleEstimate(w http.ResponseWriter, r *http.Request) {
	var spec Spec
	if err := json.NewDecoder(r.Body).Decode(&spec); err != nil {
		writeJSON(w, 400, map[string]string{"error": err.Error()})
		return
	}
	man, err := s.registries()
	if err != nil {
		writeJSON(w, 500, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, 200, spec.Estimate(man.Models, s.timings()))
}

// timings feeds the estimate from what this machine actually measured, falling
// back to conservative defaults on the first run.
func (s *Server) timings() map[string]float64 {
	out := map[string]float64{}
	path := filepath.Join(s.env.RepoRoot, "build", "lab", "timings.json")
	if data, err := os.ReadFile(path); err == nil {
		_ = json.Unmarshal(data, &out)
	}
	return out
}

func (s *Server) handleUploadRef(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPut {
		http.Error(w, "PUT", http.StatusMethodNotAllowed)
		return
	}
	data, err := io.ReadAll(io.LimitReader(r.Body, 32<<20))
	if err != nil {
		writeJSON(w, 400, map[string]string{"error": err.Error()})
		return
	}
	dir := filepath.Join(s.env.RepoRoot, "build", "lab", "_refs")
	_ = os.MkdirAll(dir, 0o755)
	local := filepath.Join(dir, fmt.Sprintf("ref-%d.png", time.Now().UnixNano()))
	if err := os.WriteFile(local, data, 0o644); err != nil {
		writeJSON(w, 500, map[string]string{"error": err.Error()})
		return
	}
	out := map[string]any{"localPath": local}
	if s.env.Comfy.HasCreds() {
		name, err := s.env.Comfy.Upload(local, "lab_ref_"+filepath.Base(local))
		if err != nil {
			writeJSON(w, 502, map[string]string{"error": err.Error()})
			return
		}
		out["refName"] = name
	}
	if thumb, err := Thumbnail(data, 480); err == nil {
		_ = writeFile(local+".thumb.jpg", thumb)
		out["thumb"] = "/media/_refs/" + filepath.Base(local) + ".thumb.jpg"
	}
	writeJSON(w, 200, out)
}

func (s *Server) handleRuns(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.mu.Lock()
		list := make([]RunState, 0, len(s.runs))
		for _, run := range s.runs {
			list = append(list, run.State())
		}
		s.mu.Unlock()
		sort.Slice(list, func(i, j int) bool {
			return list[i].CreatedAt.After(list[j].CreatedAt)
		})
		writeJSON(w, 200, list)
	case http.MethodPost:
		s.startRun(w, r)
	default:
		http.Error(w, "GET/POST", http.StatusMethodNotAllowed)
	}
}

func (s *Server) startRun(w http.ResponseWriter, r *http.Request) {
	var spec Spec
	if err := json.NewDecoder(r.Body).Decode(&spec); err != nil {
		writeJSON(w, 400, map[string]string{"error": err.Error()})
		return
	}
	if s.forceDry {
		spec.Dry = true
	}
	if !spec.Dry && !s.env.Comfy.HasCreds() {
		writeJSON(w, 412, map[string]string{
			"error": "chybí CF_ACCESS_CLIENT_ID / CF_ACCESS_CLIENT_SECRET v .env.local — " +
				"dry-run funguje i tak",
		})
		return
	}
	s.mu.Lock()
	if s.active != "" {
		if run, ok := s.runs[s.active]; ok {
			st := run.State()
			if st.Status == "running" || st.Status == "planning" {
				s.mu.Unlock()
				writeJSON(w, 409, map[string]string{"error": "jeden běh už jede: " + st.ID})
				return
			}
		}
	}
	s.mu.Unlock()

	id := time.Now().Format("20060102-150405")
	dir := filepath.Join(s.env.RepoRoot, "build", "lab", id)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		writeJSON(w, 500, map[string]string{"error": err.Error()})
		return
	}
	run := NewRun(s.env, dir, &spec)
	s.mu.Lock()
	s.runs[id] = run
	s.active = id
	s.mu.Unlock()

	go func() {
		if err := run.Dump(); err != nil {
			return
		}
		run.Generate()
	}()
	writeJSON(w, 200, map[string]string{"runId": id})
}

func (s *Server) handleRun(w http.ResponseWriter, r *http.Request) {
	rest := strings.TrimPrefix(r.URL.Path, "/api/runs/")
	parts := strings.Split(rest, "/")
	run := s.run(parts[0])
	if run == nil {
		writeJSON(w, 404, map[string]string{"error": "běh neexistuje"})
		return
	}
	if len(parts) == 1 {
		writeJSON(w, 200, map[string]any{
			"state": run.State(), "manifest": run.Manifest(),
			"metrics": readJSONFile(filepath.Join(run.Dir, "metrics.json")),
			"spec":    run.Spec,
		})
		return
	}
	switch parts[1] {
	case "events":
		s.streamEvents(w, r, run)
	case "cancel":
		run.Cancel()
		writeJSON(w, 200, map[string]string{"status": "cancelling"})
	case "cell":
		if len(parts) < 3 {
			writeJSON(w, 400, map[string]string{"error": "chybí id buňky"})
			return
		}
		s.handleCell(w, run, parts[2])
	default:
		writeJSON(w, 404, map[string]string{"error": "neznámá akce"})
	}
}

// streamEvents is server-sent events: the run state is already durable on
// disk, so a dropped connection just reconnects and gets a fresh snapshot.
func (s *Server) streamEvents(w http.ResponseWriter, r *http.Request, run *Run) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeJSON(w, 500, map[string]string{"error": "streaming není k dispozici"})
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	ch, stop := run.Subscribe()
	defer stop()
	enc := json.NewEncoder(w)
	for {
		select {
		case <-r.Context().Done():
			return
		case st := <-ch:
			_, _ = io.WriteString(w, "data: ")
			_ = enc.Encode(st)
			_, _ = io.WriteString(w, "\n")
			flusher.Flush()
			if st.Status == "done" || st.Status == "failed" || st.Status == "cancelled" {
				return
			}
		case <-time.After(20 * time.Second):
			_, _ = io.WriteString(w, ": ping\n\n")
			flusher.Flush()
		}
	}
}

func (s *Server) handleCell(w http.ResponseWriter, run *Run, id string) {
	man := run.Manifest()
	if man == nil {
		writeJSON(w, 404, map[string]string{"error": "chybí manifest"})
		return
	}
	var cell *ManifestCell
	for i := range man.Cells {
		if man.Cells[i].ID == id {
			cell = &man.Cells[i]
			break
		}
	}
	if cell == nil {
		writeJSON(w, 404, map[string]string{"error": "buňka neexistuje"})
		return
	}
	raw, err := os.ReadFile(filepath.Join(run.Dir, "wf", id+".json"))
	if err != nil {
		writeJSON(w, 404, map[string]string{"error": err.Error()})
		return
	}
	var wf map[string]any
	_ = json.Unmarshal(raw, &wf)
	writeJSON(w, 200, map[string]any{
		"cell": cell, "workflow": wf, "explain": Explain(wf),
	})
}

// handleMedia serves run artefacts. Every path is resolved and rejected unless
// it stays under build/lab — a served directory plus user-supplied names is the
// classic traversal hole.
func (s *Server) handleMedia(w http.ResponseWriter, r *http.Request) {
	rel := strings.TrimPrefix(r.URL.Path, "/media/")
	// Pose skeletons are app assets, not run artefacts — they live in the
	// package, so they get their own root rather than a copy per run.
	base := filepath.Join(s.env.RepoRoot, "build", "lab")
	if after, ok := strings.CutPrefix(rel, "_poses/"); ok {
		base = filepath.Join(s.env.RepoRoot, "assets", "poses")
		rel = after
	}
	full := filepath.Join(base, filepath.Clean("/"+rel))
	real, err := filepath.Abs(full)
	if err != nil || !strings.HasPrefix(real, base+string(os.PathSeparator)) {
		http.Error(w, "mimo adresář běhů", http.StatusForbidden)
		return
	}
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	http.ServeFile(w, r, real)
}

func (s *Server) run(id string) *Run {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.runs[id]
}

// loadRuns rebuilds the run list from disk so a restart does not lose history;
// a run left "running" by a kill is honestly relabelled.
func (s *Server) loadRuns() {
	base := filepath.Join(s.env.RepoRoot, "build", "lab")
	entries, err := os.ReadDir(base)
	if err != nil {
		return
	}
	for _, e := range entries {
		if !e.IsDir() || strings.HasPrefix(e.Name(), "_") {
			continue
		}
		dir := filepath.Join(base, e.Name())
		data, err := os.ReadFile(filepath.Join(dir, "state.json"))
		if err != nil {
			continue
		}
		var st RunState
		if err := json.Unmarshal(data, &st); err != nil {
			continue
		}
		if st.Status == "running" || st.Status == "planning" {
			st.Status = "interrupted"
			st.Message = "přerušeno restartem serveru — lze navázat"
		}
		spec := &Spec{}
		if sd, err := os.ReadFile(filepath.Join(dir, "spec.json")); err == nil {
			_ = json.Unmarshal(sd, spec)
		}
		run := NewRun(s.env, dir, spec)
		run.state = st
		if man, err := ReadManifest(filepath.Join(dir, "wf", "manifest.json")); err == nil {
			run.man = man
		}
		s.runs[e.Name()] = run
	}
}

func readJSONFile(path string) any {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var v any
	if err := json.Unmarshal(data, &v); err != nil {
		return nil
	}
	return v
}
