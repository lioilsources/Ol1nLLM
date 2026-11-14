package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestPromptCSVReadsTheNegativeColumn(t *testing.T) {
	body := `id,juggernaut,pony,negative
standing,"a woman standing","1girl, standing","sitting, chair"
sitting,"a woman sitting","1girl, sitting",
`
	bodies, err := ParsePromptBodies(writePromptFile(t, "positions.csv", body))
	if err != nil {
		t.Fatal(err)
	}
	if got := bodies[0].Negative; got != "sitting, chair" {
		t.Fatalf("negativ první pozice: %q", got)
	}
	// An empty cell is "this position has no negative of its own".
	if got := bodies[1].Negative; got != "" {
		t.Fatalf("prázdná buňka nesmí dát negativ: %q", got)
	}
	// The negative is not a family: it must not show up as a text to send.
	if len(bodies[0].Texts) != 2 {
		t.Fatalf("negativ se dostal mezi texty rodin: %+v", bodies[0].Texts)
	}
}

func TestPromptYAMLReadsTheNegativeKey(t *testing.T) {
	body := `standing:
  juggernaut: "a woman standing"
  negative: "sitting, chair"
sitting:
  juggernaut: "a woman sitting"
`
	bodies, err := ParsePromptBodies(writePromptYAML(t, body))
	if err != nil {
		t.Fatal(err)
	}
	if bodies[0].Negative != "sitting, chair" || bodies[1].Negative != "" {
		t.Fatalf("negativy: %q, %q", bodies[0].Negative, bodies[1].Negative)
	}
}

func TestPromptNegativeAloneIsNotAPrompt(t *testing.T) {
	cases := map[string]struct{ body, want string }{
		"jen negativ":     {"id,flux,negative\na,,blurry\n", "žádný text"},
		"negativ dvakrát": {"id,flux,negative,negative\na,x,y,z\n", "dvakrát"},
	}
	for name, c := range cases {
		_, err := ParsePromptBodies(writePromptFile(t, "p.csv", c.body))
		if err == nil || !strings.Contains(err.Error(), c.want) {
			t.Errorf("%s: čekal jsem chybu s %q, mám %v", name, c.want, err)
		}
	}
}

func TestPromptNegativeReachesTheDumpContract(t *testing.T) {
	bodies, err := ParsePromptBodies(writePromptFile(t, "p.csv",
		"id,flux,negative\na,A photo.,blurry\nb,Another.,\n"))
	if err != nil {
		t.Fatal(err)
	}
	data, err := json.Marshal(bodies)
	if err != nil {
		t.Fatal(err)
	}
	// dump_spec.dart reads `negative`; a body without one leaves the key out,
	// so a file written before the column existed and one written after look
	// the same where nothing was asked for.
	if got := string(data); !strings.Contains(got, `"negative":"blurry"`) ||
		strings.Count(got, `"negative"`) != 1 {
		t.Fatalf("JSON pro dump: %s", got)
	}
}

func TestEstimateWarnsWhenANegativeMeetsFlux(t *testing.T) {
	man := &Manifest{Models: restyleModels()}
	warned := func(s Spec) string {
		t.Helper()
		for _, w := range s.Estimate(man, nil).Warnings {
			if strings.HasPrefix(w, "negativ:") {
				return w
			}
		}
		return ""
	}
	base := Spec{
		Models: []string{"illu"}, BaseModel: "manga", Flows: []string{"restyle"},
		Prompts: []string{"a dancer"}, NoStyles: true,
	}
	if w := warned(base); w != "" {
		t.Fatalf("bez negativu není co hlásit: %q", w)
	}

	typed := base
	typed.Negative = "blurry"
	if w := warned(typed); !strings.Contains(w, "Flux Manga") || strings.Contains(w, "Illustrious") {
		t.Fatalf("negativ z pole u FLUX modelu pozice: %q", w)
	}

	fromFile := base
	fromFile.Prompts = nil
	fromFile.PromptsYAML = writePromptFile(t, "p.csv",
		"id,pony,flux,negative\nstanding,\"1girl, standing\",A woman standing.,sitting\n")
	if w := warned(fromFile); !strings.Contains(w, "Flux Manga") {
		t.Fatalf("negativ ze souboru u FLUX modelu pozice: %q", w)
	}

	// Every model in the run reads a negative: nothing to say.
	sdxl := typed
	sdxl.BaseModel = "jug"
	if w := warned(sdxl); w != "" {
		t.Fatalf("SDXL modely negativ čtou: %q", w)
	}

	// Qwen-Image reads the FLUX column and still takes a negative: the dump
	// says so per model, and the warning follows that, not the family.
	yes := true
	man.Models = append(man.Models, ManifestModel{
		ID: "qwen", Label: "Qwen-Image", Backend: BackendComfy, PromptFamily: FamilyFlux,
		ReadsNegative: &yes,
	})
	qwen := typed
	qwen.BaseModel = "qwen"
	if w := warned(qwen); w != "" {
		t.Fatalf("Qwen-Image negativ čte: %q", w)
	}
}
