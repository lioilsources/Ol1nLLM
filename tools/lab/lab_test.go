package main

import (
	"encoding/json"
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

func TestEstimateWarnsAboutPresetOverrideAndFluxSweep(t *testing.T) {
	flux := ManifestModel{ID: "flux-manga", Label: "FLUX manga", CkptName: nil,
		Preset: map[string]any{"steps": 20.0}}
	s := Spec{
		Models: []string{"flux-manga"}, Prompts: []string{"x"},
		Flows: []string{"txt2img"}, Sweep: "KSampler.cfg=5|6",
	}
	e := s.Estimate(&Manifest{Models: []ManifestModel{flux}}, nil)
	if len(e.Warnings) == 0 || !strings.Contains(strings.Join(e.Warnings, " "), "vlastní šabloně") {
		t.Fatalf("sweep přes model bez KSampleru musí varovat, dostal jsem %v", e.Warnings)
	}
	if e.Variants != 2 {
		t.Fatalf("variants = %d, want 2", e.Variants)
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
