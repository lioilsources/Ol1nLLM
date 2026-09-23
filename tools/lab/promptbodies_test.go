package main

import (
	"encoding/json"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

const promptYAML = `# portréty
portrait:
  danbooru: "1girl, solo, looking at viewer"
  juggernaut: "a portrait of a young woman, looking at the camera"
  flux: "A portrait photograph of a young woman looking at the camera."
street:
  danbooru: "1boy, city, night"
  juggernaut: "a man on a city street at night"
  flux: "A photograph of a man on a city street at night."
`

func writePromptYAML(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "prompts.yaml")
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestParsePromptBodiesKeepsFileOrder(t *testing.T) {
	// The index of an entry becomes a column of the run, so document order has
	// to survive the parse — a map would have shuffled it per process.
	bodies, err := ParsePromptBodies(writePromptYAML(t, promptYAML))
	if err != nil {
		t.Fatal(err)
	}
	if len(bodies) != 2 || bodies[0].ID != "portrait" || bodies[1].ID != "street" {
		t.Fatalf("pořadí nebo obsah nesedí: %+v", bodies)
	}
	if bodies[0].Texts[FamilyDanbooru] != "1girl, solo, looking at viewer" {
		t.Fatalf("danbooru text: %q", bodies[0].Texts[FamilyDanbooru])
	}
	if len(bodies[1].Texts) != 3 {
		t.Fatalf("čekám tři rodiny, mám %d", len(bodies[1].Texts))
	}
}

func TestParsePromptBodiesRejectsWhatWouldRenderSilently(t *testing.T) {
	// Each of these would otherwise produce a picture that looks like a
	// measurement of a prompt nobody wrote.
	cases := map[string]string{
		"neznámá rodina (překlep)": "p1:\n  pony: \"a, b\"\n",
		"prázdný text":             "p1:\n  flux:\n",
		"dvakrát týž prompt":       "p1:\n  flux: \"a\"\np1:\n  flux: \"b\"\n",
		"není mapa rodin":          "p1: \"a, b\"\n",
		"seznam místo mapy":        "- p1\n- p2\n",
		"prázdný soubor":           "",
	}
	for name, body := range cases {
		if _, err := ParsePromptBodies(writePromptYAML(t, body)); err == nil {
			t.Errorf("%s: čekal jsem chybu", name)
		}
	}
}

func TestParsePromptBodiesNamesTheLine(t *testing.T) {
	// A file is edited by hand, so the complaint has to say where to look.
	_, err := ParsePromptBodies(writePromptYAML(t,
		"p1:\n  flux: \"a\"\np2:\n  ponny: \"b\"\n"))
	if err == nil {
		t.Fatal("čekal jsem chybu")
	}
	if !strings.Contains(err.Error(), "řádek 4") || !strings.Contains(err.Error(), "ponny") {
		t.Fatalf("chyba neukazuje na řádek s překlepem: %v", err)
	}
}

func TestPromptFamilyOfMirrorsTheRegistry(t *testing.T) {
	// The manifest carries the family dump.dart computed; the fallback is for
	// a registry probe cached before the field existed, and has to agree.
	ckpt := "juggernaut.safetensors"
	cases := []struct {
		name string
		m    ManifestModel
		want string
	}{
		{"z manifestu", ManifestModel{PromptFamily: FamilyFlux, PromptDialect: "booru"}, FamilyFlux},
		{"booru bez pole", ManifestModel{PromptDialect: "booru", Backend: BackendComfy, CkptName: &ckpt}, FamilyDanbooru},
		{"sdxl bez pole", ManifestModel{PromptDialect: "natural", Backend: BackendComfy, CkptName: &ckpt}, FamilyJuggernaut},
		{"dedikovaný graf", ManifestModel{PromptDialect: "natural", Backend: BackendComfy}, FamilyFlux},
		{"gen-queue", ManifestModel{PromptDialect: "natural", Backend: BackendNim}, FamilyFlux},
	}
	for _, c := range cases {
		if got := promptFamilyOf(c.m); got != c.want {
			t.Errorf("%s: %s, want %s", c.name, got, c.want)
		}
	}
}

func TestEstimateMultipliesPromptsByTheFile(t *testing.T) {
	ckpt := "x.safetensors"
	models := []ManifestModel{
		{ID: "pony", Label: "Pony", PromptFamily: FamilyDanbooru, Preset: map[string]any{}},
		{ID: "jug", Label: "Juggernaut", PromptFamily: FamilyJuggernaut, CkptName: &ckpt, Preset: map[string]any{}},
	}
	man := &Manifest{Models: models}
	path := writePromptYAML(t, promptYAML)

	// Two prefixes × two bodies × two models × baseline-only × one flow.
	s := Spec{
		Models: []string{"pony", "jug"}, Prompts: []string{"masterpiece", "low angle"},
		PromptsYAML: path, Flows: []string{"txt2img"}, NoStyles: true,
	}
	e := s.Estimate(man, nil)
	if len(e.Blockers) != 0 {
		t.Fatalf("nečekaný blocker: %v", e.Blockers)
	}
	if e.Cells != 8 {
		t.Fatalf("cells = %d, want 8", e.Cells)
	}

	// The file carries the prompts, so an empty box is no longer empty — it is
	// one empty prefix, and blocking it would refuse a legitimate run.
	noBox := s
	noBox.Prompts = nil
	e = noBox.Estimate(man, nil)
	if len(e.Blockers) != 0 {
		t.Fatalf("prázdné pole s YAML nesmí blokovat: %v", e.Blockers)
	}
	if e.Cells != 4 {
		t.Fatalf("cells = %d, want 4", e.Cells)
	}
}

func TestEstimateBlocksAPromptTheRunCannotRead(t *testing.T) {
	// The dump would crash on this; saying it here means the file can be fixed
	// while it is still open, and the crash stays the backstop.
	models := []ManifestModel{
		{ID: "pony", Label: "Pony V6", PromptFamily: FamilyDanbooru, Preset: map[string]any{}},
	}
	path := writePromptYAML(t, "p1:\n  flux: \"jen pro flux\"\n")
	s := Spec{
		Models: []string{"pony"}, PromptsYAML: path,
		Flows: []string{"txt2img"}, NoStyles: true,
	}
	e := s.Estimate(&Manifest{Models: models}, nil)
	if len(e.Blockers) == 0 {
		t.Fatal("prompt bez textu pro vybraný model musí blokovat")
	}
	joined := strings.Join(e.Blockers, " · ")
	if !strings.Contains(joined, "p1") || !strings.Contains(joined, FamilyDanbooru) ||
		!strings.Contains(joined, "Pony V6") {
		t.Fatalf("blocker neřekne co a pro koho chybí: %q", joined)
	}

	// The same file is fine once nothing in the run reads danbooru.
	ok := s
	ok.Models = []string{"schnell"}
	e = ok.Estimate(&Manifest{Models: []ManifestModel{
		{ID: "schnell", Label: "FLUX Schnell", PromptFamily: FamilyFlux, Backend: BackendNim},
	}}, nil)
	if len(e.Blockers) != 0 {
		t.Fatalf("flux-only soubor s flux-only během nesmí blokovat: %v", e.Blockers)
	}
}

func TestEstimateBlocksAMalformedPromptFile(t *testing.T) {
	models := []ManifestModel{{ID: "a", PromptFamily: FamilyFlux, Preset: map[string]any{}}}
	s := Spec{
		Models: []string{"a"}, Prompts: []string{"x"}, Flows: []string{"txt2img"},
		NoStyles: true, PromptsYAML: writePromptYAML(t, "p1:\n  pony: \"x\"\n"),
	}
	if e := s.Estimate(&Manifest{Models: models}, nil); len(e.Blockers) == 0 {
		t.Fatal("rozbitý YAML musí blokovat start")
	}
}

func TestUploadPromptsAnswersWithWhatItRead(t *testing.T) {
	// Parsed on the way in, so a typo shows while the file is still on screen
	// rather than as a blocker on a spec the user has stopped thinking about.
	s := &Server{env: &Env{RepoRoot: t.TempDir()}, runs: map[string]*Run{}, token: "t"}

	rec := httptest.NewRecorder()
	s.handleUploadPrompts(rec, httptest.NewRequest("PUT", "/api/upload-prompts",
		strings.NewReader(promptYAML)))
	if rec.Code != 200 {
		t.Fatalf("upload skončil %d: %s", rec.Code, rec.Body.String())
	}
	var ok struct {
		LocalPath string `json:"localPath"`
		Prompts   []struct {
			ID       string   `json:"id"`
			Families []string `json:"families"`
		} `json:"prompts"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &ok); err != nil {
		t.Fatal(err)
	}
	if len(ok.Prompts) != 2 || ok.Prompts[0].ID != "portrait" {
		t.Fatalf("odpověď nenese prompty: %+v", ok.Prompts)
	}
	if !slices.Equal(ok.Prompts[0].Families, promptFamilies) {
		t.Fatalf("rodiny = %v, want %v", ok.Prompts[0].Families, promptFamilies)
	}
	if _, err := os.Stat(ok.LocalPath); err != nil {
		t.Fatalf("soubor se neuložil: %v", err)
	}

	rec = httptest.NewRecorder()
	s.handleUploadPrompts(rec, httptest.NewRequest("PUT", "/api/upload-prompts",
		strings.NewReader("p1:\n  ponny: \"x\"\n")))
	if rec.Code != 400 || !strings.Contains(rec.Body.String(), "ponny") {
		t.Fatalf("překlep měl skončit 400 s vysvětlením, mám %d: %s",
			rec.Code, rec.Body.String())
	}
}

func TestDumpEnvNormalisesThePromptFile(t *testing.T) {
	// dump.dart reads JSON, not YAML: one parser in the system, and the run
	// directory keeps the bodies it ran on so a resume replays them.
	dir := t.TempDir()
	s := Spec{
		Models: []string{"a"}, Prompts: []string{"masterpiece"},
		PromptsYAML: writePromptYAML(t, promptYAML), Flows: []string{"txt2img"},
	}
	env, err := s.DumpEnv(dir)
	if err != nil {
		t.Fatal(err)
	}
	var path string
	for _, kv := range env {
		if rest, ok := strings.CutPrefix(kv, "PROMPT_BODIES="); ok {
			path = rest
		}
	}
	if path == "" {
		t.Fatal("PROMPT_BODIES chybí v env")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var bodies []PromptBody
	if err := json.Unmarshal(data, &bodies); err != nil {
		t.Fatal(err)
	}
	if len(bodies) != 2 || bodies[0].ID != "portrait" {
		t.Fatalf("normalizované prompty nesedí: %+v", bodies)
	}
	if !slices.Contains([]string{filepath.Join(dir, "prompt-bodies.json")}, path) {
		t.Fatalf("soubor nevznikl v adresáři běhu: %s", path)
	}

	// Without a file the variable must not appear at all — dump.dart keys the
	// whole feature off its presence.
	plain := s
	plain.PromptsYAML = ""
	env, err = plain.DumpEnv(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	for _, kv := range env {
		if strings.HasPrefix(kv, "PROMPT_BODIES=") {
			t.Fatal("PROMPT_BODIES nesmí být nastavené bez souboru")
		}
	}
}
