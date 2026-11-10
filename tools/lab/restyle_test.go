package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writePromptFile(t *testing.T, name, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

const promptCSV = `id,juggernaut,pony,flux
standing,"a woman standing, full body","1girl, standing, full body","A full-length photograph of a woman standing."
sitting,"a woman sitting on a chair","1girl, sitting, chair","A photograph of a woman sitting on a chair."
`

func TestPromptCSVReadsFamiliesByColumn(t *testing.T) {
	bodies, err := ParsePromptBodies(writePromptFile(t, "positions.csv", promptCSV))
	if err != nil {
		t.Fatal(err)
	}
	if len(bodies) != 2 || bodies[0].ID != "standing" || bodies[1].ID != "sitting" {
		t.Fatalf("pořadí nebo obsah nesedí: %+v", bodies)
	}
	// `pony` is the name the column has in the sheet; the lab's family for a
	// tag-reading checkpoint is danbooru.
	if got := bodies[0].Texts[FamilyDanbooru]; got != "1girl, standing, full body" {
		t.Fatalf("pony sloupec: %q", got)
	}
	if got := bodies[1].Texts[FamilyFlux]; got != "A photograph of a woman sitting on a chair." {
		t.Fatalf("flux sloupec: %q", got)
	}
}

func TestPromptCSVSurvivesExcel(t *testing.T) {
	// A Czech Excel writes a BOM and semicolons; with semicolons the tag
	// prompts need no quotes at all.
	body := "\xef\xbb\xbfid;pony;juggernaut\r\n" +
		"standing;1girl, standing, full body;a woman standing\r\n"
	bodies, err := ParsePromptBodies(writePromptFile(t, "positions.csv", body))
	if err != nil {
		t.Fatal(err)
	}
	if len(bodies) != 1 || bodies[0].Texts[FamilyDanbooru] != "1girl, standing, full body" {
		t.Fatalf("středníky: %+v", bodies)
	}
	if _, ok := bodies[0].Texts[FamilyFlux]; ok {
		t.Fatal("rodina bez sloupce nesmí dostat text")
	}
}

func TestPromptCSVIsRecognisedByContent(t *testing.T) {
	// The upload handler stores every file under .yaml, so the name cannot be
	// what decides.
	bodies, err := ParsePromptBodies(writePromptFile(t, "prompts-123.yaml", promptCSV))
	if err != nil {
		t.Fatal(err)
	}
	if len(bodies) != 2 {
		t.Fatalf("čekám dva prompty, mám %d", len(bodies))
	}
}

func TestPromptCSVRejectsWhatWouldRenderSilently(t *testing.T) {
	cases := map[string]struct{ body, want string }{
		"neznámý sloupec": {"id,juggernaut,ponny\na,x,y\n", "ponny"},
		"chybí id":        {"juggernaut,pony\nx,y\n", "id"},
		"rodina dvakrát":  {"id,pony,danbooru\na,x,y\n", "dvakrát"},
		// The classic: tags without quotes spill into the next family.
		"čárky bez uvozovek": {"id,pony,flux\na,1girl, standing,A photo.\n", "uvozovek"},
		"prompt dvakrát":     {"id,flux\na,x\na,y\n", "dvakrát"},
		"řádek bez textu":    {"id,flux,pony\na,,\n", "žádný text"},
		"jen hlavička":       {"id,flux\n", "žádné prompty"},
	}
	for name, c := range cases {
		_, err := ParsePromptBodies(writePromptFile(t, "p.csv", c.body))
		if err == nil {
			t.Errorf("%s: čekal jsem chybu", name)
			continue
		}
		if !strings.Contains(err.Error(), c.want) {
			t.Errorf("%s: chyba neříká %q: %v", name, c.want, err)
		}
	}
}

func restyleModels() []ManifestModel {
	ckpt := "x.safetensors"
	yes, no := true, false
	return []ManifestModel{
		{ID: "jug", Label: "Juggernaut", Backend: BackendComfy, SupportsPose: true,
			PromptFamily: FamilyJuggernaut, CkptName: &ckpt, Txt2img: &yes, Preset: map[string]any{}},
		{ID: "illu", Label: "Illustrious", Backend: BackendComfy, SupportsPose: true,
			PromptFamily: FamilyDanbooru, PromptDialect: "booru", CkptName: &ckpt,
			Txt2img: &yes, Preset: map[string]any{}},
		{ID: "manga", Label: "Flux Manga", Backend: BackendComfy,
			PromptFamily: FamilyFlux, Txt2img: &yes, Preset: map[string]any{}},
		{ID: "sd15", Label: "SD 1.5", Backend: BackendComfy,
			PromptFamily: FamilyJuggernaut, CkptName: &ckpt, Txt2img: &yes, Preset: map[string]any{}},
		{ID: "fill", Label: "Flux Fill", Backend: BackendComfy,
			PromptFamily: FamilyFlux, Txt2img: &no, Preset: map[string]any{}},
	}
}

func TestEstimateCountsOnePhotoPerColumnNotPerStyle(t *testing.T) {
	man := &Manifest{Models: restyleModels()}
	s := Spec{
		Models: []string{"illu"}, BaseModel: "jug", Flows: []string{"restyle"},
		PromptsYAML: writePromptFile(t, "positions.csv", promptCSV),
		Characters:  []string{"red hair, green eyes", "", "black hair, brown eyes", "silver hair"},
		Styles:      []string{"ukiyoe", "baroque", "woodcut"},
	}
	e := s.Estimate(man, nil)
	if len(e.Blockers) != 0 {
		t.Fatalf("nečekaný blocker: %v", e.Blockers)
	}
	// 2 positions × 3 characters = 6 columns. Stage 1 is 6 photos; stage 2 is
	// 6 × (3 styles + baseline) restyles over them. The blank line is no
	// character.
	if want := 6 + 6*4; e.Cells != want {
		t.Fatalf("cells = %d, want %d", e.Cells, want)
	}
}

func TestEstimateBlocksARestyleThatHasNothingToDrawOver(t *testing.T) {
	man := &Manifest{Models: restyleModels()}
	base := Spec{
		Models: []string{"illu"}, BaseModel: "jug", Flows: []string{"restyle"},
		Prompts: []string{"a dancer"}, NoStyles: true,
	}
	if e := base.Estimate(man, nil); len(e.Blockers) != 0 {
		t.Fatalf("platný běh nesmí blokovat: %v", e.Blockers)
	}
	// A restyle needs no reference upload — the photo is made by the run.
	blocked := func(name string, mut func(*Spec), want string) {
		t.Helper()
		s := base
		mut(&s)
		e := s.Estimate(man, nil)
		for _, b := range e.Blockers {
			if strings.Contains(b, want) {
				return
			}
		}
		t.Errorf("%s: čekal jsem blocker s %q, mám %v", name, want, e.Blockers)
	}
	blocked("bez modelu pozice", func(s *Spec) { s.BaseModel = "" }, "model pozice")
	blocked("model mimo registr", func(s *Spec) { s.BaseModel = "flux-dev" }, "není v registru")
	blocked("model bez txt2img", func(s *Spec) { s.BaseModel = "fill" }, "neumí txt2img")
	blocked("neznámý hint", func(s *Spec) { s.Hint = "lineart" }, "depth nebo canny")
}

func TestEstimateReadsThePromptFileForThePositionModelToo(t *testing.T) {
	// The position model is not among the picked ones, but it reads the file
	// in its own family — a missing column has to be said before the dump.
	man := &Manifest{Models: restyleModels()}
	s := Spec{
		Models: []string{"illu"}, BaseModel: "manga", Flows: []string{"restyle"},
		PromptsYAML: writePromptFile(t, "p.csv", "id,pony\nstanding,\"1girl, standing\"\n"),
		NoStyles:    true,
	}
	e := s.Estimate(man, nil)
	found := false
	for _, b := range e.Blockers {
		if strings.Contains(b, "Flux Manga") {
			found = true
		}
	}
	if !found {
		t.Fatalf("chybějící text pro model pozice musí blokovat: %v", e.Blockers)
	}
}

func TestEstimateWarnsWhereARestyleWouldBeSkipped(t *testing.T) {
	man := &Manifest{Models: restyleModels()}
	s := Spec{
		Models: []string{"illu", "manga", "sd15"}, BaseModel: "jug",
		Flows: []string{"restyle"}, Prompts: []string{"a dancer"}, NoStyles: true,
		Hint: "canny",
	}
	e := s.Estimate(man, nil)
	joined := strings.Join(e.Warnings, "\n")
	if !strings.Contains(joined, "SD 1.5 nemá ControlNet") {
		t.Errorf("chybí varování o modelu bez ControlNetu: %v", e.Warnings)
	}
	if !strings.Contains(joined, "Flux Manga umí jen hloubkový hint") {
		t.Errorf("chybí varování o canny na FLUXu: %v", e.Warnings)
	}
	if strings.Contains(joined, "Illustrious") {
		t.Errorf("SDXL model s ControlNetem nemá být ve varování: %v", e.Warnings)
	}
}

func TestDumpEnvCarriesTheTwoStageContract(t *testing.T) {
	dir := t.TempDir()
	s := Spec{
		Models: []string{"illu"}, BaseModel: "jug", Flows: []string{"restyle"},
		Prompts: []string{"a dancer"}, Hint: "canny",
		Characters: []string{" red hair, green eyes ", "", "black hair"},
	}
	env, err := s.DumpEnv(dir)
	if err != nil {
		t.Fatal(err)
	}
	get := func(key string) string {
		for _, kv := range env {
			if strings.HasPrefix(kv, key+"=") {
				return strings.TrimPrefix(kv, key+"=")
			}
		}
		return ""
	}
	if get("BASE_MODEL") != "jug" || get("HINT") != "canny" {
		t.Fatalf("BASE_MODEL=%q HINT=%q", get("BASE_MODEL"), get("HINT"))
	}
	path := get("CHARACTERS_FILE")
	if !filepath.IsAbs(path) {
		t.Fatalf("CHARACTERS_FILE musí být absolutní cesta: %q", path)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.TrimSpace(string(data)); got != "red hair, green eyes\nblack hair" {
		t.Fatalf("characters.txt = %q", got)
	}
}

func TestSplitByDependencyPutsPhotosFirst(t *testing.T) {
	cells := []ManifestCell{
		{ID: "restyle__illu__ukiyoe", DependsOn: "position__jug____baseline"},
		{ID: "txt2img__illu__ukiyoe"},
		{ID: "position__jug____baseline"},
		{ID: "restyle__illu____baseline", DependsOn: "position__jug____baseline"},
	}
	first, rest := splitByDependency(cells)
	if len(first) != 1 || first[0].ID != "position__jug____baseline" {
		t.Fatalf("první průchod: %+v", first)
	}
	// Everything else keeps the order it came in — the model grouping.
	want := []string{"restyle__illu__ukiyoe", "txt2img__illu__ukiyoe", "restyle__illu____baseline"}
	if len(rest) != len(want) {
		t.Fatalf("druhý průchod: %+v", rest)
	}
	for i, id := range want {
		if rest[i].ID != id {
			t.Errorf("rest[%d] = %s, want %s", i, rest[i].ID, id)
		}
	}
	// A run without dependencies is one pass, untouched.
	first, rest = splitByDependency(cells[1:3])
	if len(first) != 0 || len(rest) != 2 {
		t.Fatalf("bez závislostí: first=%d rest=%d", len(first), len(rest))
	}
}

func TestPatchHintImageSwapsOnlyThePlaceholder(t *testing.T) {
	var wf map[string]any
	if err := json.Unmarshal([]byte(`{
		"__depth_src__": {"class_type": "LoadImage", "inputs": {"image": "lab_stage1__p.png"}},
		"__pose_img__":  {"class_type": "LoadImage", "inputs": {"image": "ol1n_pose_x.png"}},
		"7": {"class_type": "CLIPTextEncode", "inputs": {"text": "lab_stage1__p.png"}}
	}`), &wf); err != nil {
		t.Fatal(err)
	}
	if n := patchHintImage(wf, "lab_stage1__p.png", "lab_pos_run_p.png"); n != 1 {
		t.Fatalf("patched %d uzlů, want 1", n)
	}
	img := func(key string) any {
		return wf[key].(map[string]any)["inputs"].(map[string]any)["image"]
	}
	if img("__depth_src__") != "lab_pos_run_p.png" {
		t.Errorf("hint nedostal fotku: %v", img("__depth_src__"))
	}
	if img("__pose_img__") != "ol1n_pose_x.png" {
		t.Errorf("cizí LoadImage se nesmí měnit: %v", img("__pose_img__"))
	}
	// A graph that does not read the placeholder is the caller's error, and
	// zero is how it finds out.
	if n := patchHintImage(wf, "lab_stage1__p.png", "again.png"); n != 0 {
		t.Fatalf("podruhé už není co měnit, patched %d", n)
	}
}

func TestStagedImageNameIsSafeAndPerRun(t *testing.T) {
	a := stagedImageName("20261110-101500", "position__jug____baseline__p01")
	if a != "lab_pos_20261110-101500_position__jug____baseline__p01.png" {
		t.Fatalf("name = %q", a)
	}
	// A cell id is built from registry ids, but a sweep value can carry
	// anything; the name becomes a file on the server.
	b := stagedImageName("run", "position@x-../../etc__m")
	if strings.ContainsAny(b, "/@ ") {
		t.Fatalf("jméno není bezpečné: %q", b)
	}
	if stagedImageName("run-a", "c") == stagedImageName("run-b", "c") {
		t.Fatal("dva běhy nesmí sdílet jméno fotky")
	}
}

func TestDryRunMakesThePhotoBeforeItsRestyles(t *testing.T) {
	dir := t.TempDir()
	man := &Manifest{
		Models: []ManifestModel{{ID: "jug", Label: "Juggernaut"}, {ID: "illu", Label: "Illustrious"}},
		Cells: []ManifestCell{
			// Sorted by model the restyles would run first: "illu" < "jug".
			{ID: "position__jug____baseline", Flow: "position", Model: "jug", Style: "__baseline"},
			{ID: "restyle__illu__ukiyoe", Flow: "restyle", Model: "illu", Style: "ukiyoe",
				DependsOn: "position__jug____baseline", HintImage: "lab_stage1__position__jug____baseline.png"},
			{ID: "restyle__illu__orphan", Flow: "restyle", Model: "illu", Style: "baroque",
				DependsOn: "position__jug__missing", HintImage: "lab_stage1__position__jug__missing.png"},
		},
	}
	state := RunState{ID: "run", Dry: true, Cells: map[string]CellState{}, Total: len(man.Cells)}
	for _, c := range man.Cells {
		state.Cells[c.ID] = CellState{ID: c.ID, Status: CellPending}
	}
	r := &Run{Dir: dir, Spec: &Spec{Dry: true}, man: man, state: state,
		subs: map[chan RunState]struct{}{}}
	r.Generate()

	st := r.State()
	if got := st.Cells["position__jug____baseline"].Status; got != CellDone {
		t.Fatalf("fotka pozice: %s", got)
	}
	if got := st.Cells["restyle__illu__ukiyoe"].Status; got != CellDone {
		t.Fatalf("restyle nad hotovou fotkou: %s (%s)", got, st.Cells["restyle__illu__ukiyoe"].Error)
	}
	orphan := st.Cells["restyle__illu__orphan"]
	if orphan.Status != CellFailed || !strings.Contains(orphan.Error, "position__jug__missing") {
		t.Fatalf("restyle bez fotky musí selhat s důvodem: %+v", orphan)
	}
}

func TestExportHangsARestyleOffItsPhoto(t *testing.T) {
	dir := t.TempDir()
	for _, d := range []string{"img", "wf"} {
		if err := os.MkdirAll(filepath.Join(dir, d), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	man := &Manifest{
		Models: []ManifestModel{{ID: "jug", Label: "Juggernaut"}, {ID: "illu", Label: "Illustrious"}},
		Cells: []ManifestCell{
			{ID: "position__jug____baseline", Flow: "position", Model: "jug",
				Style: "__baseline", Prompt: strPtr("a dancer, red hair")},
			{ID: "restyle__illu__ukiyoe", Flow: "restyle", Model: "illu", Style: "ukiyoe",
				Prompt:    strPtr("1girl, dancing, red hair, ukiyo-e"),
				DependsOn: "position__jug____baseline"},
		},
	}
	state := RunState{ID: "20261110-000000", Title: "restyle",
		Cells: map[string]CellState{}, Done: 2, Total: 2}
	for i, c := range man.Cells {
		if err := os.WriteFile(filepath.Join(dir, "img", c.ID+".png"),
			Placeholder(64, 96, fmt.Sprintf("cell-%d", i)), 0o644); err != nil {
			t.Fatal(err)
		}
		state.Cells[c.ID] = CellState{ID: c.ID, Status: CellDone}
	}
	run := &Run{Dir: dir, Spec: &Spec{}, man: man, state: state,
		subs: map[chan RunState]struct{}{}}
	plan, err := run.BuildExport()
	if err != nil {
		t.Fatal(err)
	}
	var body struct {
		Nodes []map[string]any `json:"nodes"`
	}
	if err := json.Unmarshal(plan.Body, &body); err != nil {
		t.Fatal(err)
	}
	byPrompt := map[string]map[string]any{}
	for _, n := range body.Nodes {
		byPrompt[n["prompt"].(string)] = n
	}
	photo, restyle := byPrompt["a dancer, red hair"], byPrompt["1girl, dancing, red hair, ukiyo-e"]
	if photo == nil || restyle == nil {
		t.Fatalf("chybí uzel: %v", body.Nodes)
	}
	if photo["parentId"] != nil {
		t.Errorf("fotka pozice je kořen, ne potomek: %v", photo["parentId"])
	}
	if restyle["parentId"] != photo["id"] {
		t.Errorf("restyle visí pod %v, ne pod fotkou %v", restyle["parentId"], photo["id"])
	}
}
