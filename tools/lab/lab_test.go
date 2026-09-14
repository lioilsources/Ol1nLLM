package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func repoRootForTest(t *testing.T) string {
	t.Helper()
	dir, err := filepath.Abs("../..")
	if err != nil {
		t.Fatal(err)
	}
	return dir
}

func TestEstimateBlocksBeforeSpendingGPU(t *testing.T) {
	models := []ManifestModel{
		{ID: "a", Label: "A", Preset: map[string]any{"steps": 30.0}},
		{ID: "b", Label: "B", Preset: map[string]any{"steps": 6.0}},
	}
	base := Spec{
		Models: []string{"a", "b"}, Prompts: []string{"x"},
		Flows: []string{"txt2img"}, Styles: []string{"ukiyoe"},
	}
	e := base.Estimate(&Manifest{Models: models}, nil)
	// 2 models × 1 prompt × (1 style + baseline) × 1 flow
	if e.Cells != 4 {
		t.Fatalf("cells = %d, want 4", e.Cells)
	}
	if len(e.Blockers) != 0 {
		t.Fatalf("nečekaný blocker: %v", e.Blockers)
	}

	// No prompt ⇒ the dump loops over nothing and reports "0 ok, 0 chyb" as
	// if it had run. Must block, not estimate one cell.
	noPrompt := base
	noPrompt.Prompts = nil
	if got := noPrompt.Estimate(&Manifest{Models: models}, nil); len(got.Blockers) == 0 {
		t.Fatal("prázdné prompty musí blokovat start")
	}

	// A run that needs a reference must not start without one.
	needRef := base
	needRef.Flows = []string{"repose"}
	if got := needRef.Estimate(&Manifest{Models: models}, nil); len(got.Blockers) == 0 {
		t.Fatal("repose bez reference musí blokovat start")
	}

	// The ceiling exists because 600 cells took 3h40m once; an accidental
	// sweep must hit a wall, not the GPU.
	big := base
	big.Prompts = make([]string, 200)
	for i := range big.Prompts {
		big.Prompts[i] = "p"
	}
	if got := big.Estimate(&Manifest{Models: models}, nil); len(got.Blockers) == 0 {
		t.Fatalf("nad stropem %d musí blokovat (bylo %d buněk)", MaxCells, got.Cells)
	}
}

func TestEstimateCountsTheCandidatesFile(t *testing.T) {
	// A candidates run without --styles renders the whole file. Counted as a
	// baseline-only run, 54 artists × five models sailed past the ceiling —
	// and the real file carries keys the plan knows nothing about (booru,
	// prose, artist), which must not trip it either.
	models := []ManifestModel{{ID: "a", Preset: map[string]any{}}}
	man := &Manifest{Models: models}
	s := Spec{
		Models: []string{"a"}, Prompts: []string{"x"}, Flows: []string{"txt2img"},
		StylesFile: filepath.Join("candidates", "artists.json"),
	}
	data, err := os.ReadFile(s.StylesFile)
	if err != nil {
		t.Fatal(err)
	}
	var list []map[string]any
	if err := json.Unmarshal(data, &list); err != nil {
		t.Fatal(err)
	}
	e := s.Estimate(man, nil)
	if len(e.Blockers) != 0 {
		t.Fatalf("kandidáti s klíči navíc neprošli plánem: %v", e.Blockers)
	}
	if e.Cells != len(list)+1 {
		t.Fatalf("cells = %d, want %d (kandidáti + baseline)", e.Cells, len(list)+1)
	}

	// --styles narrows the file, the same as in the dump.
	narrow := s
	narrow.Styles = []string{"monet", "impressionist"}
	if got := narrow.Estimate(man, nil).Cells; got != 3 {
		t.Fatalf("zúžený běh: cells = %d, want 3", got)
	}

	// A file that does not parse blocks before the GPU instead of failing the
	// dump after it.
	bad := filepath.Join(t.TempDir(), "bad.json")
	if err := os.WriteFile(bad, []byte(`[{"label":"bez id","block":"x"}]`), 0o644); err != nil {
		t.Fatal(err)
	}
	broken := s
	broken.StylesFile = bad
	if got := broken.Estimate(man, nil); len(got.Blockers) == 0 {
		t.Fatal("kandidát bez id musí blokovat start")
	}
}

func TestResumeCLINeverDumpsAgain(t *testing.T) {
	// A run killed mid-flight picks up without the dump — the one heavy step,
	// and the one whose output a started matrix must not swap. Flutter is
	// unusable here on purpose: a resume that tried to re-dump would fail.
	dir := t.TempDir()
	must := func(err error) {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
	}
	must(os.MkdirAll(filepath.Join(dir, "wf"), 0o755))
	must(os.MkdirAll(filepath.Join(dir, "img"), 0o755))
	man, _ := json.Marshal(Manifest{Cells: []ManifestCell{
		{ID: "repose__m____baseline", Flow: "repose", Model: "m", Style: "__baseline"},
		{ID: "repose__m__ukiyoe", Flow: "repose", Model: "m", Style: "ukiyoe"},
	}})
	must(os.WriteFile(filepath.Join(dir, "wf", "manifest.json"), man, 0o644))
	spec, _ := json.Marshal(Spec{Dry: true})
	must(os.WriteFile(filepath.Join(dir, "spec.json"), spec, 0o644))
	// Left "running" by the kill, with one cell already on disk.
	st, _ := json.Marshal(RunState{ID: "r", Status: "running", Total: 2,
		Cells: map[string]CellState{}})
	must(os.WriteFile(filepath.Join(dir, "state.json"), st, 0o644))
	kept := Placeholder(64, 96, "hotová buňka")
	must(os.WriteFile(filepath.Join(dir, "img", "repose__m____baseline.png"), kept, 0o644))

	env := &Env{Comfy: NewComfy("", "", ""), FlutterMsg: "v testu vypnutý"}
	must(resumeCLI(env, []string{dir}))

	if _, err := os.Stat(filepath.Join(dir, "img", "repose__m__ukiyoe.png")); err != nil {
		t.Fatalf("chybějící buňka se nedopočítala: %v", err)
	}
	if got, _ := os.ReadFile(filepath.Join(dir, "img", "repose__m____baseline.png")); string(got) != string(kept) {
		t.Fatal("hotová buňka se generovala znovu")
	}
	var final RunState
	data, err := os.ReadFile(filepath.Join(dir, "state.json"))
	must(err)
	must(json.Unmarshal(data, &final))
	if final.Status != "done" || final.Done != 2 {
		t.Fatalf("stav = %s %d/%d, want done 2/2", final.Status, final.Done, final.Total)
	}
}

func TestEstimateWarnsAboutPresetOverrideAndFluxSweep(t *testing.T) {
	flux := ManifestModel{ID: "flux-manga", Label: "FLUX manga", CkptName: nil,
		Preset: map[string]any{"steps": 20.0}}
	s := Spec{
		Models: []string{"flux-manga"}, Prompts: []string{"x"},
		Flows: []string{"txt2img"}, Sweep: "KSampler.cfg=5|6",
	}
	e := s.Estimate(&Manifest{Models: []ManifestModel{flux}}, nil)
	if !strings.Contains(strings.Join(e.Warnings, " "), "zapečený") {
		t.Fatalf("sweep KSampleru přes flux-manga musí varovat, že přepíše zapečený sampler, dostal jsem %v", e.Warnings)
	}
	if strings.Contains(strings.Join(e.Warnings, " "), "se přeskočí") {
		t.Fatalf("flux-manga KSampler má, buňky se nepřeskočí — varování to nesmí tvrdit: %v", e.Warnings)
	}
	if e.Variants != 2 {
		t.Fatalf("variants = %d, want 2", e.Variants)
	}

	// A flow parameter reaches flux-manga like any other model: nothing to warn.
	for _, sweep := range []string{"param.seed=1|2", "?KSamplerAdvanced.cfg=1|2"} {
		s.Sweep = sweep
		e = s.Estimate(&Manifest{Models: []ManifestModel{flux}}, nil)
		if strings.Contains(strings.Join(e.Warnings, " "), "zapečený") {
			t.Fatalf("%s na flux-manga nesmí varovat o sampleru: %v", sweep, e.Warnings)
		}
	}
}

func TestEstimateWarnsWhenLatentFightsDepth(t *testing.T) {
	// _prepare derives the repose latent from the reference; a manual size
	// silently re-crops the depth hint.
	s := Spec{
		Models: []string{"a"}, Prompts: []string{"x"}, Flows: []string{"txt2img"},
		PoseMode: "depth", RefName: "r.png", Latent: "1024x1024",
	}
	e := s.Estimate(&Manifest{Models: []ManifestModel{{ID: "a", Preset: map[string]any{}}}}, nil)
	if !strings.Contains(strings.Join(e.Warnings, " "), "ořízne hloubkovou mapu") {
		t.Fatalf("chybí varování o latentu, dostal jsem %v", e.Warnings)
	}
}

func TestMediaRejectsPathTraversal(t *testing.T) {
	root := t.TempDir()
	secret := filepath.Join(root, "secret.txt")
	if err := os.WriteFile(secret, []byte("token"), 0o644); err != nil {
		t.Fatal(err)
	}
	runDir := filepath.Join(root, "build", "lab", "run1")
	if err := os.MkdirAll(runDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(runDir, "ok.txt"), []byte("hi"), 0o644); err != nil {
		t.Fatal(err)
	}
	s := &Server{env: &Env{RepoRoot: root}, runs: map[string]*Run{}, token: "t"}

	rec := httptest.NewRecorder()
	s.handleMedia(rec, httptest.NewRequest("GET", "/media/run1/ok.txt", nil))
	if rec.Code != 200 || rec.Body.String() != "hi" {
		t.Fatalf("legitimní soubor: %d %q", rec.Code, rec.Body.String())
	}

	for _, evil := range []string{
		"/media/../../secret.txt",
		"/media/run1/../../../secret.txt",
		"/media/..%2f..%2fsecret.txt",
	} {
		rec := httptest.NewRecorder()
		s.handleMedia(rec, httptest.NewRequest("GET", evil, nil))
		if rec.Code == 200 && strings.Contains(rec.Body.String(), "token") {
			t.Fatalf("%s prolezlo ven z build/lab", evil)
		}
	}
}

func TestGuardRejectsForeignOriginAndMissingToken(t *testing.T) {
	// The server holds CF Access credentials, so any page in the browser
	// getting to POST here would be a real problem.
	s := &Server{env: &Env{}, runs: map[string]*Run{}, token: "secret"}
	h := s.guard(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(204) })

	req := httptest.NewRequest("POST", "/api/runs", nil)
	rec := httptest.NewRecorder()
	h(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("POST bez tokenu prošel: %d", rec.Code)
	}

	req = httptest.NewRequest("GET", "/api/config", nil)
	req.Header.Set("Origin", "https://evil.example")
	rec = httptest.NewRecorder()
	h(rec, req)
	if rec.Code != http.StatusForbidden {
		t.Fatalf("cizí origin prošel: %d", rec.Code)
	}

	req = httptest.NewRequest("POST", "/api/runs", nil)
	req.Header.Set("X-Lab-Token", "secret")
	rec = httptest.NewRecorder()
	h(rec, req)
	if rec.Code != 204 {
		t.Fatalf("platný požadavek odmítnut: %d", rec.Code)
	}
}

func TestExplainReadsTheRealWorkflowAssets(t *testing.T) {
	root := repoRootForTest(t)
	for _, name := range []string{"sdxl_txt2img.api.json", "sdxl_img2img.api.json"} {
		data, err := os.ReadFile(filepath.Join(root, "assets", "comfyui", name))
		if err != nil {
			t.Fatal(err)
		}
		var wf map[string]any
		if err := json.Unmarshal(data, &wf); err != nil {
			t.Fatal(err)
		}
		steps := Explain(wf)
		if len(steps) < 5 {
			t.Fatalf("%s: řetěz má jen %d kroků", name, len(steps))
		}
		if steps[len(steps)-1].Class != "SaveImage" {
			t.Fatalf("%s: řetěz nekončí uložením, ale %s", name, steps[len(steps)-1].Class)
		}
		var sampler *Step
		for i := range steps {
			if steps[i].Class == "KSampler" {
				sampler = &steps[i]
			}
			if steps[i].Injected {
				t.Fatalf("%s: čistá šablona nesmí mít vložené uzly (%s)", name, steps[i].NodeID)
			}
		}
		if sampler == nil {
			t.Fatalf("%s: v řetězu chybí sampler", name)
		}
		if _, ok := sampler.Values["denoise"]; !ok {
			t.Fatalf("%s: sampler neukazuje denoise", name)
		}
		if sampler.Note == "" {
			t.Fatalf("%s: sampler nemá vysvětlivku", name)
		}
	}
}

func TestExplainMarksInjectedNodes(t *testing.T) {
	wf := map[string]any{
		"1": map[string]any{"class_type": "CheckpointLoaderSimple",
			"inputs": map[string]any{"ckpt_name": "x"}},
		"__cn_apply__": map[string]any{"class_type": "ControlNetApplyAdvanced",
			"inputs": map[string]any{"strength": 0.75, "end_percent": 0.9,
				"positive": []any{"1", 0}}},
		"5": map[string]any{"class_type": "KSampler",
			"inputs": map[string]any{"denoise": 1.0, "positive": []any{"__cn_apply__", 0}}},
		"9": map[string]any{"class_type": "SaveImage",
			"inputs": map[string]any{"images": []any{"5", 0}}},
	}
	var cn *Step
	for _, s := range Explain(wf) {
		if s.NodeID == "__cn_apply__" {
			cn = &s
		}
	}
	if cn == nil || !cn.Injected {
		t.Fatal("__cn_apply__ musí být označený jako vložený appkou")
	}
	if !strings.Contains(cn.Note, "0.75") {
		t.Fatalf("vysvětlivka neuvádí sílu: %q", cn.Note)
	}
}

func TestExplainLabelsTheFaceChain(t *testing.T) {
	// The panel exists to say what is wired; an unlabelled node shows up as a
	// raw class name and the reader has to guess which knob it is.
	wf := map[string]any{
		"1": map[string]any{"class_type": "CheckpointLoaderSimple",
			"inputs": map[string]any{"ckpt_name": "x"}},
		"__depth_src__": map[string]any{"class_type": "LoadImage",
			"inputs": map[string]any{"image": "ref.png"}},
		"__face_id__": map[string]any{"class_type": "InstantIDModelLoader",
			"inputs": map[string]any{"instantid_file": "ip-adapter.bin"}},
		"__face_analysis__": map[string]any{"class_type": "InstantIDFaceAnalysis",
			"inputs": map[string]any{"provider": "CPU"}},
		"__face_apply__": map[string]any{"class_type": "ApplyInstantIDAdvanced",
			"inputs": map[string]any{"ip_weight": 0.6, "cn_strength": 0.8, "end_at": 1.0,
				"model": []any{"1", 0}, "image": []any{"__depth_src__", 0},
				"instantid":   []any{"__face_id__", 0},
				"insightface": []any{"__face_analysis__", 0}}},
		"5": map[string]any{"class_type": "KSampler",
			"inputs": map[string]any{"denoise": 1.0, "model": []any{"__face_apply__", 0}}},
		"6": map[string]any{"class_type": "VAEDecode",
			"inputs": map[string]any{"samples": []any{"5", 0}}},
		"__detail_bbox__": map[string]any{"class_type": "UltralyticsDetectorProvider",
			"inputs": map[string]any{"model_name": "bbox/face_yolov8m.pt"}},
		"__face_detail__": map[string]any{"class_type": "FaceDetailer",
			"inputs": map[string]any{"denoise": 0.4, "image": []any{"6", 0},
				"model":         []any{"__face_apply__", 0},
				"bbox_detector": []any{"__detail_bbox__", 0}}},
		"9": map[string]any{"class_type": "SaveImage",
			"inputs": map[string]any{"images": []any{"__face_detail__", 0}}},
	}
	steps := map[string]Step{}
	for _, st := range Explain(wf) {
		steps[st.NodeID] = st
	}
	for _, id := range []string{"__face_id__", "__face_analysis__", "__face_apply__",
		"__detail_bbox__", "__face_detail__"} {
		st, ok := steps[id]
		if !ok {
			t.Fatalf("%s se do řetězu nedostal", id)
		}
		if !st.Injected {
			t.Fatalf("%s musí být označený jako vložený appkou", id)
		}
		if st.Label == st.Class {
			t.Fatalf("%s nemá český popisek", id)
		}
	}
	if !strings.Contains(steps["__face_apply__"].Note, "předlohy") {
		t.Fatalf("tvář nemá vysvětlivku: %q", steps["__face_apply__"].Note)
	}
	if got := steps["__face_apply__"].Values["ip_weight"]; got != 0.6 {
		t.Fatalf("panel neukazuje sílu embeddingu tváře: %v", got)
	}
	if got := steps["__face_apply__"].Values["cn_strength"]; got != 0.8 {
		t.Fatalf("panel neukazuje sílu klíčových bodů tváře: %v", got)
	}
	if got := steps["__face_detail__"].Values["denoise"]; got != 0.4 {
		t.Fatalf("panel neukazuje sílu dotažení: %v", got)
	}
}

func TestMetricsSeparateReactionFromSpread(t *testing.T) {
	base := Placeholder(64, 64, "baseline")
	same := Placeholder(64, 64, "baseline")
	other := Placeholder(64, 64, "úplně jiná buňka")
	hb, _ := Histogram(base)
	hs, _ := Histogram(same)
	ho, _ := Histogram(other)
	if d := CosDist(hb, hs); d > 1e-9 {
		t.Fatalf("stejný obrázek má mít vzdálenost 0, má %v", d)
	}
	if d := CosDist(hb, ho); d < 1e-6 {
		t.Fatalf("různé obrázky mají mít nenulovou vzdálenost, mají %v", d)
	}

	cells := []ManifestCell{
		{ID: "b", Flow: "repose", Model: "m", Style: "__baseline"},
		{ID: "s1", Flow: "repose", Model: "m", Style: "ukiyoe"},
		{ID: "s2", Flow: "repose", Model: "m", Style: "baroque"},
	}
	m := ComputeMetrics(cells, map[string][]float64{"b": hb, "s1": ho, "s2": hs})
	if m.Cells["s1"].Reaction == nil {
		t.Fatal("stylová buňka musí mít reakci vůči baseline")
	}
	if m.Cells["b"].Reaction != nil {
		t.Fatal("baseline nemá reakci sám na sebe")
	}
	if len(m.Groups) != 1 {
		t.Fatalf("skupin = %d, want 1", len(m.Groups))
	}
}

func TestDumpEnvCarriesTheContract(t *testing.T) {
	dir := t.TempDir()
	s := &Spec{
		Prompts: []string{"a", "b"}, Models: []string{"pony"}, Flows: []string{"repose"},
		Styles: []string{"ukiyoe"}, Seed: 42, Batch: 2, PoseMode: "template",
		PoseName: "ol3.png", Sweep: "__cn_apply__.strength=0.5|0.75", EditDenoise: 0.9,
	}
	env, err := s.DumpEnv(dir)
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{
		"MANIFEST": "1", "SEED": "42", "BATCH": "2", "FLOWS": "repose",
		"MODELS": "pony", "STYLES": "ukiyoe", "POSE_MODE": "template",
		"POSE_NAME": "ol3.png", "SWEEP": "__cn_apply__.strength=0.5|0.75",
		"EDIT_DENOISE": "0.9",
	}
	got := map[string]string{}
	for _, kv := range env {
		if k, v, ok := strings.Cut(kv, "="); ok {
			got[k] = v
		}
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("%s = %q, want %q", k, got[k], v)
		}
	}
	data, err := os.ReadFile(got["PROMPTS_FILE"])
	if err != nil {
		t.Fatal(err)
	}
	if strings.TrimSpace(string(data)) != "a\nb" {
		t.Fatalf("prompts.txt = %q", data)
	}
}

func TestThumbnailShrinksAndStaysDecodable(t *testing.T) {
	big := Placeholder(832, 1216, "cell")
	thumb, err := Thumbnail(big, 320)
	if err != nil {
		t.Fatal(err)
	}
	if len(thumb) >= len(big) {
		t.Fatalf("náhled není menší: %d vs %d", len(thumb), len(big))
	}
	if _, err := Histogram(thumb); err != nil {
		t.Fatalf("náhled nejde dekódovat: %v", err)
	}
}

func TestEstimateNeverSerialisesNullLists(t *testing.T) {
	// encoding/json renders a nil slice as null, and the UI then blows up on
	// blockers.length. The API shape must not depend on whether anything was
	// appended.
	s := Spec{Models: []string{"a"}, Prompts: []string{"x"}, Flows: []string{"txt2img"}}
	data, err := json.Marshal(s.Estimate(&Manifest{Models: []ManifestModel{{ID: "a", Preset: map[string]any{}}}}, nil))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(data), "null") {
		t.Fatalf("odhad obsahuje null: %s", data)
	}
	var out map[string]any
	if err := json.Unmarshal(data, &out); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"warnings", "blockers"} {
		if _, ok := out[key].([]any); !ok {
			t.Fatalf("%s není pole: %#v", key, out[key])
		}
	}
}

func TestExplainReturnsEmptyNotNil(t *testing.T) {
	steps := Explain(map[string]any{"1": map[string]any{"class_type": "KSampler"}})
	if steps == nil {
		t.Fatal("Explain bez SaveImage musí vrátit prázdný seznam, ne nil")
	}
	data, _ := json.Marshal(steps)
	if string(data) == "null" {
		t.Fatal("prázdný řetěz se serializuje jako null")
	}
}

func TestMediaServesPoseAssetsAndStillBlocksTraversal(t *testing.T) {
	// Pose thumbnails come from the package assets, not from a run directory.
	root := repoRootForTest(t)
	s := &Server{env: &Env{RepoRoot: root}, runs: map[string]*Run{}, token: "t"}

	rec := httptest.NewRecorder()
	s.handleMedia(rec, httptest.NewRequest("GET", "/media/_poses/ol3.png", nil))
	if rec.Code != 200 || rec.Body.Len() < 1000 {
		t.Fatalf("šablona pózy se nenačetla: %d, %d B", rec.Code, rec.Body.Len())
	}

	rec = httptest.NewRecorder()
	s.handleMedia(rec, httptest.NewRequest("GET", "/media/_poses/../../pubspec.yaml", nil))
	if rec.Code == 200 && strings.Contains(rec.Body.String(), "name: ol1n_llm") {
		t.Fatal("cesta pro pózy pustila ven z assets/poses")
	}
}

func TestDumpEnvPassesAbsolutePaths(t *testing.T) {
	// The dump subprocess runs from the package root, not from wherever lab was
	// started, so a relative --out silently broke the whole run.
	dir := t.TempDir()
	rel, err := filepath.Rel(mustGetwd(t), dir)
	if err != nil {
		t.Skip("tempdir není relativní k cwd")
	}
	s := &Spec{Prompts: []string{"x"}, Flows: []string{"txt2img"},
		StylesFile: "kandidati.json", RefFile: "foto.png"}
	env, err := s.DumpEnv(rel)
	if err != nil {
		t.Fatal(err)
	}
	for _, kv := range env {
		k, v, _ := strings.Cut(kv, "=")
		switch k {
		case "OUT_DIR", "PROMPTS_FILE", "STYLES_FILE", "REF_FILE":
			if !filepath.IsAbs(v) {
				t.Errorf("%s není absolutní: %q", k, v)
			}
		}
	}
}

func mustGetwd(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	return wd
}

func TestUpdateSurvivesSubscribersComingAndGoing(t *testing.T) {
	// An SSE client disconnecting mid-run used to panic the whole server with
	// "send on closed channel": update copied the subscriber list, released the
	// lock, and only then sent. Run with -race.
	r := &Run{
		Dir:   t.TempDir(),
		state: RunState{ID: "t", Cells: map[string]CellState{}},
		subs:  map[chan RunState]struct{}{},
	}
	var wg sync.WaitGroup
	stop := make(chan struct{})

	wg.Add(1)
	go func() { // the run, changing cell state as fast as it can
		defer wg.Done()
		for i := 0; ; i++ {
			select {
			case <-stop:
				return
			default:
			}
			id := "cell" + itoa(i%20)
			r.update(func(s *RunState) { s.Cells[id] = CellState{ID: id, Status: CellDone} })
		}
	}()

	for i := 0; i < 40; i++ { // browsers opening and closing the event stream
		wg.Add(1)
		go func() {
			defer wg.Done()
			ch, unsub := r.Subscribe()
			<-ch
			unsub()
		}()
	}
	for i := 0; i < 40; i++ { // and readers serialising snapshots meanwhile
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := json.Marshal(r.State()); err != nil {
				t.Error(err)
			}
		}()
	}
	time.Sleep(150 * time.Millisecond)
	close(stop)
	wg.Wait()
}

// ── LoRA trigger words ─────────────────────────────────────
// Fixtures are trimmed copies of real headers read off the server, so the
// thresholds stay calibrated against the files the lab actually offers.

func triggerWords(in []LoraTrigger) []string {
	out := make([]string, 0, len(in))
	for _, t := range in {
		out = append(out, t.Word)
	}
	return out
}

func TestTriggersFromFullCoverageTags(t *testing.T) {
	// style-anime-screencap: captions on all 160 images, then the dataset's
	// incidental subjects. "school uniform" is on four fifths of them —
	// frequent, specific, and still not a trigger.
	meta := map[string]string{
		"ss_dataset_dirs": `{"dataset": {"n_repeats": 1, "img_count": 160}}`,
		"ss_tag_frequency": `{"dataset": {"anime screencap": 160, "anime coloring": 160,
			"school uniform": 130, "1girl": 94, "solo": 88}}`,
	}
	got, src := extractTriggers(meta)
	if src != "tagy" {
		t.Fatalf("zdroj = %q, čekáno tagy", src)
	}
	words := strings.Join(triggerWords(got), ", ")
	if !strings.Contains(words, "anime screencap") {
		t.Errorf("chybí trigger: %s", words)
	}
	if strings.Contains(words, "school uniform") {
		t.Errorf("tag na 81 %% obrázků není trigger: %s", words)
	}
	if strings.Contains(words, "1girl") {
		t.Errorf("booru boilerplate není trigger ani na 100 %%: %s", words)
	}
	if got[0].Cover != "160/160" {
		t.Errorf("pokrytí = %q", got[0].Cover)
	}
}

func TestTriggersDropGenericTagsEvenAtFullCoverage(t *testing.T) {
	// style-gothic-niji: everything that covers the dataset is boilerplate,
	// so the honest answer is "no trigger words", not "1girl".
	meta := map[string]string{
		"ss_dataset_dirs": `{"img": {"n_repeats": 7, "img_count": 29}}`,
		"ss_tag_frequency": `{"img": {"1girl": 29, "solo": 29, "looking at viewer": 29,
			"lips": 28, "breasts": 27}}`,
	}
	if got, src := extractTriggers(meta); got != nil {
		t.Errorf("čekáno nic, dostal jsem %v (%s)", triggerWords(got), src)
	}
}

func TestTriggersIgnoreTinyFolders(t *testing.T) {
	// npm-v11t has folders of 4 and 99 images; what all four share is
	// coincidence, so only the big folder may speak.
	meta := map[string]string{
		"ss_dataset_dirs": `{"11_np": {"img_count": 4}, "4_np": {"img_count": 99}}`,
		"ss_tag_frequency": `{"11_np": {"happy": 4, "hidden privates": 4},
			"4_np": {"hidden privates": 99, "1girl": 90}}`,
	}
	got, _ := extractTriggers(meta)
	if w := triggerWords(got); len(w) != 1 || w[0] != "hidden privates" {
		t.Errorf("dostal jsem %v", w)
	}
}

func TestTriggersExplicitFieldWinsOverTags(t *testing.T) {
	meta := map[string]string{
		"avatar_trigger":   "ohwxtestface person",
		"ss_dataset_dirs":  `{"img": {"img_count": 20}}`,
		"ss_tag_frequency": `{"img": {"something": 20}}`,
	}
	got, src := extractTriggers(meta)
	if src != "metadata" || len(got) != 1 || got[0].Word != "ohwxtestface person" {
		t.Fatalf("got %v (%s)", triggerWords(got), src)
	}
}

func TestTriggersFallBackToFolderNames(t *testing.T) {
	// NakedHoodieV1: no captions at all, but the folder names the concept.
	// The notebook checkpoint folder holds no images and must not appear.
	meta := map[string]string{
		"ss_dataset_dirs": `{"7_hoodie": {"n_repeats": 7, "img_count": 35},
			".ipynb_checkpoints": {"n_repeats": 0, "img_count": 0}}`,
	}
	got, src := extractTriggers(meta)
	if src != "dataset" || len(got) != 1 || got[0].Word != "hoodie" {
		t.Fatalf("got %v (%s)", triggerWords(got), src)
	}
}

func TestTriggersEmptyHeaderIsAnAnswer(t *testing.T) {
	if got, src := extractTriggers(map[string]string{}); got != nil || src != "" {
		t.Errorf("got %v (%s)", got, src)
	}
	// A folder called "img" says nothing; guessing "img" would be worse than
	// admitting we do not know.
	if got, _ := extractTriggers(map[string]string{
		"ss_dataset_dirs": `{"img": {"img_count": 40}}`,
	}); got != nil {
		t.Errorf("got %v", triggerWords(got))
	}
}

func TestTriggerCacheSurvivesRestart(t *testing.T) {
	path := filepath.Join(t.TempDir(), "lora-triggers.json")
	c := NewTriggerCache(path)
	c.byName["a.safetensors"] = cachedLora{
		Triggers: []LoraTrigger{{Word: "zap", Cover: "10/10"}},
		Source:   "tagy", Base: "sdxl",
	}
	c.save()

	// A fresh cache with no ComfyUI behind it still answers from disk, which
	// is what makes the picker instant on boot.
	got := NewTriggerCache(path).Fill(nil, []string{"a.safetensors", "b.safetensors"})
	if len(got) != 2 {
		t.Fatalf("got %d položek", len(got))
	}
	if got[0].TriggerSource != "tagy" || got[0].Triggers[0].Word != "zap" {
		t.Errorf("a = %+v", got[0])
	}
	// An unknown file is listed anyway: unusable trigger words are not a
	// reason to hide a LoRA you can still run.
	if got[1].Name != "b.safetensors" || len(got[1].Triggers) != 0 {
		t.Errorf("b = %+v", got[1])
	}
}

func TestEstimateFlagsLoraThatCannotApply(t *testing.T) {
	man := &Manifest{
		Models: []ManifestModel{
			{ID: "illu", Label: "Illustrious", Preset: map[string]any{}},
			{ID: "flux", Label: "Flux", Preset: map[string]any{}},
		},
		Loras: []ManifestLora{{
			Name: "x.safetensors", Family: "illustrious", FamilyLabel: "Illustrious",
			Fit: map[string]string{"illu": "native", "flux": "incompatible"},
		}},
	}
	s := Spec{Models: []string{"illu", "flux"}, Prompts: []string{"p"},
		Flows: []string{"txt2img"}, Lora: "x.safetensors"}
	e := s.Estimate(man, nil)
	if len(e.Blockers) != 0 {
		t.Errorf("part of the run still works, blokovat se nemá: %v", e.Blockers)
	}
	if !strings.Contains(strings.Join(e.Warnings, " "), "Flux") {
		t.Errorf("varování o Fluxu chybí: %v", e.Warnings)
	}

	// Nothing left to run — that is a blocker, before any GPU time.
	only := Spec{Models: []string{"flux"}, Prompts: []string{"p"},
		Flows: []string{"txt2img"}, Lora: "x.safetensors"}
	if got := only.Estimate(man, nil); len(got.Blockers) == 0 {
		t.Errorf("čekán blocker, dostal jsem %+v", got)
	}
}

func TestDumpEnvCarriesTheFaceFlags(t *testing.T) {
	dir := t.TempDir()
	s := &Spec{
		Prompts: []string{"a"}, Models: []string{"pony"}, Flows: []string{"repose"},
		FaceIdentity: "both", FaceDetail: true,
	}
	env, err := s.DumpEnv(dir)
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]string{}
	for _, kv := range env {
		if k, v, ok := strings.Cut(kv, "="); ok {
			got[k] = v
		}
	}
	if got["FACE_IDENTITY"] != "both" || got["FACE_DETAIL"] != "1" {
		t.Fatalf("FACE_IDENTITY=%q FACE_DETAIL=%q", got["FACE_IDENTITY"], got["FACE_DETAIL"])
	}

	// Off is the default on the dump side, so nothing needs to travel — and a
	// stale FACE_DETAIL from the parent environment must not leak in either.
	off := &Spec{Prompts: []string{"a"}, Models: []string{"pony"}, Flows: []string{"repose"}}
	env, err = off.DumpEnv(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	for _, kv := range env {
		if strings.HasPrefix(kv, "FACE_IDENTITY=") || strings.HasPrefix(kv, "FACE_DETAIL=") {
			t.Fatalf("vypnutá tvář nemá co posílat, dostal jsem %q", kv)
		}
	}
}

func TestEstimateWarnsWhenTheFaceToggleWouldDoNothing(t *testing.T) {
	man := &Manifest{Models: []ManifestModel{
		{ID: "pony", Label: "Pony", SupportsPose: true,
			CkptName: strptr("p.safetensors"), Preset: map[string]any{}},
	}}
	const quiet = "neprojeví"
	// txt2img without a depth pose injects no reference, so the face toggle
	// would do nothing and the run would look like a plain one.
	s := Spec{
		Models: []string{"pony"}, Prompts: []string{"x"}, Flows: []string{"txt2img"},
		PoseMode: "none", FaceIdentity: "instantid",
	}
	if got := strings.Join(s.Estimate(man, nil).Warnings, " "); !strings.Contains(got, quiet) {
		t.Fatalf("chybí varování o nepoužité tváři: %v", got)
	}

	// Every way a `__depth_src__` can appear is a legitimate run — no noise.
	for _, ok := range []Spec{
		{Flows: []string{"repose"}, PoseMode: "none"},
		{Flows: []string{"txt2img"}, PoseMode: "depth"},
		// The one that is easy to get wrong: img2img on an SDXL model carries
		// the source's structure over by itself, so the face lands without
		// anyone picking a pose.
		{Flows: []string{"img2img"}, PoseMode: "none"},
	} {
		ok.Models = []string{"pony"}
		ok.Prompts = []string{"x"}
		ok.RefName = "ref.png"
		ok.FaceIdentity = "instantid"
		if got := strings.Join(ok.Estimate(man, nil).Warnings, " "); strings.Contains(got, quiet) {
			t.Fatalf("%v/%s: nečekané varování: %v", ok.Flows, ok.PoseMode, got)
		}
	}

	// …but a skeleton is a pose, not a photo: no face to read there.
	skel := Spec{
		Models: []string{"pony"}, Prompts: []string{"x"}, Flows: []string{"img2img"},
		RefName: "ref.png", PoseMode: "template", PoseID: "ol1", FaceIdentity: "instantid",
	}
	if got := strings.Join(skel.Estimate(man, nil).Warnings, " "); !strings.Contains(got, quiet) {
		t.Fatalf("šablona kostry nemá odkud číst tvář, mělo varovat: %v", got)
	}

	// The detail pass alone has no identity to hold onto.
	lone := Spec{
		Models: []string{"pony"}, Prompts: []string{"x"}, Flows: []string{"repose"},
		RefName: "ref.png", FaceDetail: true,
	}
	if got := strings.Join(lone.Estimate(man, nil).Warnings, " "); !strings.Contains(got, "zapnutou identitou") {
		t.Fatalf("chybí varování o samotném detaileru: %v", got)
	}
}

func TestEstimateSaysFluxRunsPulid(t *testing.T) {
	man := &Manifest{Models: []ManifestModel{
		{ID: "flux-manga", Label: "FLUX manga", CkptName: nil, Preset: map[string]any{}},
	}}
	s := Spec{
		Models: []string{"flux-manga"}, Prompts: []string{"x"}, Flows: []string{"repose"},
		RefName: "ref.png", FaceIdentity: "faceid",
	}
	if got := strings.Join(s.Estimate(man, nil).Warnings, " "); !strings.Contains(got, "PuLID") {
		t.Fatalf("chybí varování o PuLID na FLUXu: %v", got)
	}
}

func strptr(s string) *string { return &s }

func TestDumpEnvKeepsZeroLoraStrength(t *testing.T) {
	zero := 0.0
	s := Spec{Prompts: []string{"p"}, Lora: "x.safetensors", LoraStrength: &zero}
	env, err := s.DumpEnv(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	joined := strings.Join(env, "\n")
	if !strings.Contains(joined, "LORA_STRENGTH=0\n") &&
		!strings.HasSuffix(joined, "LORA_STRENGTH=0") {
		t.Errorf("nulová síla se ztratila: %s", tailLines(joined, 4))
	}
	// Without a LoRA the strength is noise and must not reach the dump.
	none := Spec{Prompts: []string{"p"}, LoraStrength: &zero}
	env2, _ := none.DumpEnv(t.TempDir())
	if strings.Contains(strings.Join(env2, "\n"), "LORA_STRENGTH") {
		t.Error("LORA_STRENGTH bez LORA")
	}
}

// ── FINETUNE export ────────────────────────────────────────

// fakeGallery is the ingest protocol as the real backend implements it:
// content-addressed, so it only asks for blobs it does not have, and
// idempotent, so a second export of the same run asks for nothing.
type fakeGallery struct {
	blobs     map[string][]byte
	manifests [][]byte
	finalized int
	putFails  int // fail the first N PUTs with a network-ish 503
}

func newFakeGallery() *fakeGallery {
	return &fakeGallery{blobs: map[string][]byte{}}
}

func (g *fakeGallery) server(t *testing.T) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/api/meta", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"models":[{"id":"illustrious-xl"},{"id":"pony"}]}`))
	})
	mux.HandleFunc("/api/ingest/manifest", func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		g.manifests = append(g.manifests, body)
		var in struct {
			Nodes []struct {
				Images []struct {
					SHA string `json:"sha256"`
				} `json:"images"`
			} `json:"nodes"`
		}
		if err := json.Unmarshal(body, &in); err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		needed := []string{}
		for _, n := range in.Nodes {
			for _, im := range n.Images {
				if _, have := g.blobs[im.SHA]; !have {
					needed = append(needed, im.SHA)
				}
			}
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"needed": needed})
	})
	mux.HandleFunc("/api/ingest/images/", func(w http.ResponseWriter, r *http.Request) {
		if g.putFails > 0 {
			g.putFails--
			http.Error(w, `{"error":"nope"}`, 503)
			return
		}
		body, _ := io.ReadAll(r.Body)
		g.blobs[strings.TrimPrefix(r.URL.Path, "/api/ingest/images/")] = body
		w.WriteHeader(201)
	})
	mux.HandleFunc("/api/ingest/sessions/", func(w http.ResponseWriter, r *http.Request) {
		g.finalized++
		_, _ = w.Write([]byte(fmt.Sprintf(`{"images":%d,"newBlobs":%d}`,
			len(g.blobs), len(g.blobs))))
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv
}

// fakeRun writes a run directory the way the runner would: a manifest, images
// on disk, and a state that says which cells finished.
func fakeRun(t *testing.T, dry bool) *Run {
	t.Helper()
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "img"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "wf"), 0o755); err != nil {
		t.Fatal(err)
	}
	neg := "bad hands"
	man := &Manifest{
		Models: []ManifestModel{{ID: "illustrious-xl", Label: "Illustrious",
			Preset: map[string]any{"positivePrefix": "masterpiece"}}},
		Cells: []ManifestCell{
			{ID: "txt2img__illustrious-xl__ukiyoe", Flow: "txt2img",
				Model: "illustrious-xl", Style: "ukiyoe",
				Prompt: strPtr("a ballerina, ukiyo-e"), Negative: &neg,
				Params: map[string]any{"seed": 777.0, "lora": "x.safetensors",
					"loraStrength": 0.65}},
			{ID: "txt2img__illustrious-xl____baseline", Flow: "txt2img",
				Model: "illustrious-xl", Style: "__baseline",
				Prompt: strPtr("a ballerina"),
				Params: map[string]any{"seed": 777.0}},
			{ID: "txt2img__illustrious-xl__nedokonceno", Flow: "txt2img",
				Model: "illustrious-xl", Style: "baroque",
				Prompt: strPtr("a ballerina, baroque"), Params: map[string]any{}},
		},
	}
	state := RunState{ID: "20260826-000000", Title: "a ballerina", Dry: dry,
		Cells: map[string]CellState{}, Done: 2, Total: 3}
	for i, c := range man.Cells[:2] {
		if err := os.WriteFile(filepath.Join(dir, "img", c.ID+".png"),
			Placeholder(64, 96, fmt.Sprintf("cell-%d", i)), 0o644); err != nil {
			t.Fatal(err)
		}
		state.Cells[c.ID] = CellState{ID: c.ID, Status: CellDone, Placeholder: dry}
	}
	// The third cell never produced an image; nothing to send for it.
	state.Cells[man.Cells[2].ID] = CellState{ID: man.Cells[2].ID, Status: CellPending}

	if err := os.WriteFile(filepath.Join(dir, "wf",
		man.Cells[0].ID+".json"), []byte(`{"5":{"class_type":"KSampler","inputs":
		{"steps":30,"cfg":6.0,"denoise":1.0,"sampler_name":"dpmpp_2m","scheduler":"karras"}}}`),
		0o644); err != nil {
		t.Fatal(err)
	}
	return &Run{Dir: dir, Spec: &Spec{}, man: man, state: state,
		subs: map[chan RunState]struct{}{}}
}

func strPtr(s string) *string { return &s }

func TestExportMapsCellsOntoGalleryNodes(t *testing.T) {
	run := fakeRun(t, false)
	plan, err := run.BuildExport()
	if err != nil {
		t.Fatal(err)
	}
	if plan.Images != 2 || plan.Cells != 2 || plan.Skipped != 1 {
		t.Fatalf("plán = %d obrázků / %d buněk / %d přeskočeno", plan.Images, plan.Cells, plan.Skipped)
	}
	var body struct {
		Session map[string]any   `json:"session"`
		Nodes   []map[string]any `json:"nodes"`
	}
	if err := json.Unmarshal(plan.Body, &body); err != nil {
		t.Fatal(err)
	}
	if body.Session["modelId"] != "illustrious-xl" {
		t.Errorf("session modelId = %v", body.Session["modelId"])
	}
	byPrompt := map[string]map[string]any{}
	for _, n := range body.Nodes {
		byPrompt[n["prompt"].(string)] = n
	}
	styled := byPrompt["a ballerina, ukiyo-e"]
	if styled == nil {
		t.Fatal("chybí uzel se stylem")
	}
	// Sampler settings come from the graph that was sent, not from a preset.
	for k, want := range map[string]any{
		"styleId": "ukiyoe", "loraName": "x.safetensors", "loraStrength": 0.65,
		"seed": 777.0, "negativePrompt": "bad hands", "modelId": "illustrious-xl",
		"steps": 30.0, "cfg": 6.0, "samplerName": "dpmpp_2m", "scheduler": "karras",
		"positivePrefix": "masterpiece",
	} {
		if got := styled[k]; got != want {
			t.Errorf("%s = %v (čekáno %v)", k, got, want)
		}
	}
	// __baseline is the lab's marker for "no style", not a preset id.
	if base := byPrompt["a ballerina"]; base["styleId"] != nil {
		t.Errorf("baseline dostal styleId %v", base["styleId"])
	}
	// Every id must be a plausible UUID, and the same run must produce the
	// same ids twice — otherwise a re-export duplicates the whole session.
	again, err := run.BuildExport()
	if err != nil {
		t.Fatal(err)
	}
	if again.SessionID != plan.SessionID {
		t.Errorf("session id se změnil: %s vs %s", plan.SessionID, again.SessionID)
	}
	if len(plan.SessionID) != 36 || plan.SessionID[14] != '5' {
		t.Errorf("session id není UUIDv5: %q", plan.SessionID)
	}
}

func TestExportRefusesPlaceholders(t *testing.T) {
	if _, err := fakeRun(t, true).BuildExport(); err == nil {
		t.Fatal("běh nanečisto se nesmí dát odeslat — jsou to šrafy, ne výsledky")
	}
}

func TestExportUploadsOnlyWhatTheServerLacks(t *testing.T) {
	g := newFakeGallery()
	srv := g.server(t)
	ft := NewFinetune(srv.URL, "id", "secret")
	run := fakeRun(t, false)

	sum, err := run.ExportToFinetune(ft, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(g.blobs) != 2 || g.finalized != 1 {
		t.Fatalf("nahráno %d blobů, finalize %d×", len(g.blobs), g.finalized)
	}
	if sum.Images != 2 {
		t.Errorf("summary = %+v", sum)
	}

	// Second export of an unchanged run: the manifest still goes (the metadata
	// may have changed), but not a single byte of image data.
	before := len(g.blobs)
	if _, err := run.ExportToFinetune(ft, nil); err != nil {
		t.Fatal(err)
	}
	if len(g.blobs) != before {
		t.Errorf("re-export nahrál znovu: %d → %d", before, len(g.blobs))
	}
	if len(g.manifests) != 2 {
		t.Errorf("manifestů %d", len(g.manifests))
	}
}

func TestExportReportsModelsTheGalleryDoesNotKnow(t *testing.T) {
	g := newFakeGallery()
	ft := NewFinetune(g.server(t).URL, "id", "secret")
	known, err := ft.KnownModels()
	if err != nil {
		t.Fatal(err)
	}
	plan := &ExportPlan{Models: []string{"illustrious-xl", "noobai-xl", "wai-illustrious"}}
	got := unknownModels(plan, known)
	if len(got) != 2 || got[0] != "noobai-xl" || got[1] != "wai-illustrious" {
		t.Errorf("neznámé modely = %v", got)
	}
}

func TestExportFailsLoudlyOnServerRejection(t *testing.T) {
	g := newFakeGallery()
	g.putFails = 1
	ft := NewFinetune(g.server(t).URL, "id", "secret")
	// A 503 from the gallery is the gallery refusing, not the network
	// flaking — retrying it three times only delays the bad news.
	if _, err := fakeRun(t, false).ExportToFinetune(ft, nil); err == nil {
		t.Fatal("čekána chyba")
	} else if !strings.Contains(err.Error(), "503") {
		t.Errorf("chyba neříká co se stalo: %v", err)
	}
}

func TestExportNeedsCredentials(t *testing.T) {
	if _, err := fakeRun(t, false).StartExport(NewFinetune("", "", "")); err == nil {
		t.Fatal("bez CF Access creds se nesmí tvářit, že odesílá")
	}
}

func TestExportCLIFlagsSurviveTrailingPosition(t *testing.T) {
	// `lab export DIR --send`: Go's flag package stops at DIR, so without
	// reordering the flag that decides whether 200 MB leaves the machine
	// would be silently dropped. It was — once, live.
	got := flagsFirst([]string{"/run/dir", "--send"})
	if len(got) != 2 || got[0] != "--send" || got[1] != "/run/dir" {
		t.Fatalf("got %v", got)
	}
	fs := flag.NewFlagSet("export", flag.ContinueOnError)
	send := fs.Bool("send", false, "")
	if err := fs.Parse(got); err != nil {
		t.Fatal(err)
	}
	if !*send || fs.Arg(0) != "/run/dir" {
		t.Errorf("send=%v dir=%q", *send, fs.Arg(0))
	}
}

func TestProgressLineMeasuresBytesNotImages(t *testing.T) {
	// Half the bytes through, but only a quarter of the images: cells differ in
	// size, and a bar driven by the image count would sit at 25 % while the
	// upload is actually half done.
	line := progressLine(25, 100, 500<<20, 1000<<20, 50*time.Second)
	if !strings.Contains(line, "25/100") {
		t.Errorf("chybí počet položek: %s", line)
	}
	if !strings.Contains(line, "500 MB / 1000 MB") {
		t.Errorf("chybí bajty: %s", line)
	}
	// 500 MB in 50 s = 10 MB/s, so the remaining 500 MB take another 50 s.
	if !strings.Contains(line, "10 MB/s") || !strings.Contains(line, "zbývá 50s") {
		t.Errorf("špatná rychlost/ETA: %s", line)
	}
	half := strings.Count(line, "█")
	if half != 12 {
		t.Errorf("polovina pruhu = %d dílků, čekáno 12: %s", half, line)
	}
}

func TestProgressLineHandlesTheEdges(t *testing.T) {
	// Nothing to send: no division by zero, no bar off the end.
	if got := progressLine(0, 0, 0, 0, time.Second); !strings.Contains(got, "0/0") {
		t.Errorf("prázdný běh: %s", got)
	}
	// Finished: the ETA stops guessing instead of printing 0s forever.
	done := progressLine(10, 10, 100, 100, time.Second)
	if !strings.Contains(done, "zbývá —") {
		t.Errorf("hotovo má mít prázdné ETA: %s", done)
	}
	if strings.Count(done, "·") != 0 {
		t.Errorf("hotový pruh má být plný: %s", done)
	}
}

func TestHumanBytes(t *testing.T) {
	for in, want := range map[int64]string{
		0: "0 B", 999: "999 B", 2048: "2 kB", 5 << 20: "5 MB", 3 << 30: "3.0 GB",
	} {
		if got := humanBytes(in); got != want {
			t.Errorf("humanBytes(%d) = %q, čekáno %q", in, got, want)
		}
	}
}

func TestDumpErrorSaysWhatFailed(t *testing.T) {
	// A real failed dump. Its last lines are the runner's summary, so the old
	// tail showed everything except the reason.
	out := `Got dependencies!
00:00 +0: loading /repo/tools/lab/dump.dart
00:00 +0: dump matrix workflows
00:00 +0 -1: dump matrix workflows [E]
  Bad state: POSE_MODE=template vyžaduje POSE_NAME
  tools/lab/dump.dart 158:19  main.<fn>.emit
  tools/lab/dump.dart 379:15  main.<fn>


00:00 +0 -1: Some tests failed.

Failing tests:
  /repo/tools/lab/dump.dart: dump matrix workflows
`
	if got := dumpError(out); got != "Bad state: POSE_MODE=template vyžaduje POSE_NAME" {
		t.Fatalf("dumpError = %q", got)
	}

	// An expect() failure spans several lines before the blank one.
	expectOut := `00:00 +0 -1: dump matrix workflows [E]
  Expected: a value greater than <0>
    Actual: <0>
  dump nevyrobil žádné workflow

  package:matcher  expect
`
	if got := dumpError(expectOut); got !=
		"Expected: a value greater than <0> / Actual: <0> / dump nevyrobil žádné workflow" {
		t.Fatalf("expect: %q", got)
	}

	// No marker (pub failed before any test ran): keep the tail.
	if got := dumpError("Resolving dependencies...\nversion solving failed."); !strings.Contains(got, "version solving failed") {
		t.Fatalf("bez [E] se ztratil konec: %q", got)
	}
}

func TestResolvePoseNamesTheSkeleton(t *testing.T) {
	env := &Env{RepoRoot: repoRootForTest(t)}
	// What the browser sends: the id, never the file name.
	s := &Spec{PoseMode: "template", PoseID: "ol3", Dry: true}
	if err := s.resolvePose(env); err != nil {
		t.Fatal(err)
	}
	if s.PoseName != "ol3.png" {
		t.Fatalf("PoseName = %q, čekáno ol3.png", s.PoseName)
	}
	for _, id := range []string{"", "../../pubspec", "ol99", ".hidden"} {
		bad := &Spec{PoseMode: "template", PoseID: id, Dry: true}
		if err := bad.resolvePose(env); err == nil {
			t.Errorf("id %q prošlo", id)
		}
	}
	// Other modes have nothing to resolve and must not touch the name.
	depth := &Spec{PoseMode: "depth", PoseName: "keep"}
	if err := depth.resolvePose(env); err != nil || depth.PoseName != "keep" {
		t.Fatalf("depth: %v, %q", err, depth.PoseName)
	}
}

func TestResolvePoseUploadsUnderTheAppsName(t *testing.T) {
	names := make(chan string, 1)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, fh, err := r.FormFile("image")
		if r.URL.Path != "/upload/image" || err != nil {
			http.Error(w, "bad upload", 400)
			return
		}
		names <- fh.Filename
		fmt.Fprintf(w, `{"name":%q,"subfolder":""}`, fh.Filename)
	}))
	defer srv.Close()

	env := &Env{RepoRoot: repoRootForTest(t), Comfy: NewComfy(srv.URL, "id", "secret")}
	s := &Spec{PoseMode: "template", PoseID: "ol3"}
	if err := s.resolvePose(env); err != nil {
		t.Fatal(err)
	}
	if got := <-names; got != "ol1n_pose_ol3.png" {
		t.Fatalf("nahráno jako %q", got)
	}
	if s.PoseName != "ol1n_pose_ol3.png" {
		t.Fatalf("PoseName = %q", s.PoseName)
	}
}

func TestStartRunResolvesThePoseTheBrowserOnlyNamesByID(t *testing.T) {
	// The spec exactly as app.js posts it: poseId, no poseName. The server used
	// to pass that straight on, and the dump died on a missing POSE_NAME.
	root := t.TempDir()
	poses := filepath.Join(root, "assets", "poses")
	if err := os.MkdirAll(poses, 0o755); err != nil {
		t.Fatal(err)
	}
	png, err := os.ReadFile(filepath.Join(repoRootForTest(t), "assets", "poses", "ol3.png"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(poses, "ol3.png"), png, 0o644); err != nil {
		t.Fatal(err)
	}
	// No flutter: the registry probe fails (so no estimate) and the dump fails
	// fast — the run itself is not what this test is about.
	s := &Server{
		env:  &Env{RepoRoot: root, Comfy: NewComfy("http://127.0.0.1:1", "", "")},
		runs: map[string]*Run{}, token: "t",
	}
	post := func(body string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		s.startRun(rec, httptest.NewRequest("POST", "/api/runs", strings.NewReader(body)))
		return rec
	}

	rec := post(`{"models":["pony"],"prompts":["x"],"flows":["txt2img"],` +
		`"poseMode":"template","poseId":"ol3","dry":true}`)
	if rec.Code != 200 {
		t.Fatalf("start: %d %s", rec.Code, rec.Body)
	}
	var resp struct {
		RunID string `json:"runId"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	run := s.run(resp.RunID)
	if run == nil {
		t.Fatalf("běh %q nevznikl", resp.RunID)
	}
	if run.Spec.PoseName != "ol3.png" {
		t.Fatalf("PoseName = %q — dump by spadl na POSE_NAME", run.Spec.PoseName)
	}
	// Let the doomed dump settle before TempDir cleanup removes its directory.
	deadline := time.Now().Add(5 * time.Second)
	for run.State().Status == "planning" && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}

	// An id the assets do not have is refused before any run directory exists.
	before := len(s.runs)
	if rec := post(`{"models":["pony"],"prompts":["x"],"flows":["txt2img"],` +
		`"poseMode":"template","poseId":"ol99","dry":true}`); rec.Code == 200 {
		t.Fatalf("neznámá šablona prošla: %s", rec.Body)
	}
	if len(s.runs) != before {
		t.Fatal("neznámá šablona založila běh")
	}
}

func TestIdentityScoresCellsOnceAndExplainsWhenItCannot(t *testing.T) {
	// ArcFace runs out of process; a fake interpreter stands in for it and
	// counts how often it is called, so the cache is what gets tested.
	dir := t.TempDir()
	must := func(err error) {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
	}
	must(os.MkdirAll(filepath.Join(dir, "wf"), 0o755))
	must(os.MkdirAll(filepath.Join(dir, "img"), 0o755))
	man := &Manifest{Cells: []ManifestCell{
		{ID: "repose__m____baseline", Flow: "repose", Model: "m", Style: "__baseline"},
		{ID: "repose__m__ukiyoe", Flow: "repose", Model: "m", Style: "ukiyoe"},
	}}
	for _, c := range man.Cells {
		must(os.WriteFile(filepath.Join(dir, "img", c.ID+".png"), Placeholder(64, 96, c.ID), 0o644))
	}
	ref := filepath.Join(dir, "ref.png")
	must(os.WriteFile(ref, Placeholder(64, 96, "ref"), 0o644))
	calls := filepath.Join(dir, "calls")
	fake := filepath.Join(dir, "fakepython")
	must(os.WriteFile(fake, []byte(`#!/bin/sh
cat > /dev/null
echo x >> `+calls+`
echo '{"cells":{"repose__m____baseline":{"identity":0.71,"faces":1,"face":212},"repose__m__ukiyoe":{"identity":null,"faces":0}}}'
`), 0o755))
	t.Setenv("LAB_ARCFACE_PYTHON", fake)

	env := &Env{RepoRoot: dir}
	read := func() Metrics {
		t.Helper()
		data, err := os.ReadFile(filepath.Join(dir, "metrics.json"))
		must(err)
		var m Metrics
		must(json.Unmarshal(data, &m))
		return m
	}
	run := &Run{Dir: dir, env: env, man: man, Spec: &Spec{RefFile: ref}}
	run.computeMetrics()
	m := read()
	base, styled := m.Cells["repose__m____baseline"], m.Cells["repose__m__ukiyoe"]
	if base.Identity == nil || *base.Identity != 0.71 || base.Faces == nil || *base.Faces != 1 || base.FacePx != 212 {
		t.Fatalf("baseline = %+v, want identity 0.71, 1 tvář, 212 px", base)
	}
	if styled.Identity != nil || styled.Faces == nil || *styled.Faces != 0 {
		t.Fatalf("buňka bez tváře = %+v, want identity nil a 0 tváří", styled)
	}
	if !strings.Contains(m.IdentityNote, "ArcFace") {
		t.Fatalf("poznámka = %q, má vysvětlit stupnici", m.IdentityNote)
	}

	run.computeMetrics()
	if n, _ := os.ReadFile(calls); strings.Count(string(n), "x") != 1 {
		t.Fatalf("arcface volán %d×, nezměněné buňky se mají brát z identity.json", strings.Count(string(n), "x"))
	}
	if read().Cells["repose__m____baseline"].Identity == nil {
		t.Fatal("skóre z cache se do metrik nepropsalo")
	}

	// Without the setup, and for a dry run, the run still gets its metrics —
	// only with a note saying why the face numbers are missing.
	must(os.Remove(filepath.Join(dir, "identity.json")))
	t.Setenv("LAB_ARCFACE_PYTHON", filepath.Join(dir, "chybi"))
	run.computeMetrics()
	m = read()
	if m.Cells["repose__m____baseline"].Faces != nil || !strings.Contains(m.IdentityNote, "make lab-arcface") {
		t.Fatalf("bez ArcFace: cell=%+v note=%q", m.Cells["repose__m____baseline"], m.IdentityNote)
	}
	run.Spec.Dry = true
	run.computeMetrics()
	if note := read().IdentityNote; !strings.Contains(note, "nanečisto") {
		t.Fatalf("nanečisto: note=%q", note)
	}
}

func TestResolveRunDirTakesIdPathOrNewest(t *testing.T) {
	root := t.TempDir()
	base := filepath.Join(root, "build", "lab")
	for _, id := range []string{"20260913-100000", "20260914-200437", "_refs"} {
		if err := os.MkdirAll(filepath.Join(base, id), 0o755); err != nil {
			t.Fatal(err)
		}
		if id != "_refs" {
			if err := os.WriteFile(filepath.Join(base, id, "state.json"), []byte("{}"), 0o644); err != nil {
				t.Fatal(err)
			}
		}
	}
	// A newer directory without state.json is a run still being planned, not "last".
	if err := os.MkdirAll(filepath.Join(base, "20260915-000000"), 0o755); err != nil {
		t.Fatal(err)
	}
	env := &Env{RepoRoot: root}
	for arg, want := range map[string]string{
		"":                                     "20260914-200437",
		"last":                                 "20260914-200437",
		"20260913-100000":                      "20260913-100000",
		filepath.Join(base, "20260913-100000"): "20260913-100000",
	} {
		got, err := resolveRunDir(env, arg)
		if err != nil || filepath.Base(got) != want {
			t.Fatalf("resolveRunDir(%q) = %q, %v; want …/%s", arg, got, err, want)
		}
	}
	if _, err := resolveRunDir(env, "20990101-000000"); err == nil {
		t.Fatal("neexistující běh musí být chyba")
	}
}
