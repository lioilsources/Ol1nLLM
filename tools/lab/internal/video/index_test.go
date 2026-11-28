package video

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

const (
	runA = "20260101-000001" // model a; scenes s1, s2; baseline, cave, vermeer
	runB = "20260101-000002" // models b, c; same scenes; baseline, baroque, ink; one character
	runC = "20260101-000003" // model a again, other seed, scenes in reverse order
	runD = "20260101-000004" // typed prompts, no prompt file
	runE = "20260101-000005" // two characters per scene
)

func fixture(t *testing.T) string {
	t.Helper()
	lab := t.TempDir()
	var a []fakeCell
	for p, scene := range []string{"s1", "s2"} {
		for _, st := range []string{"", "cave", "vermeer"} {
			c := fakeCell{model: "a", style: st, prompt: p, scene: scene, seed: 777}
			if p == 1 && st == "vermeer" {
				c.empty = true
			}
			if p == 1 && st == "cave" {
				c.missing = true
			}
			a = append(a, c)
		}
	}
	a = append(a, fakeCell{model: "a", flow: "position", prompt: 0, scene: "s1", seed: 777})
	writeRun(t, lab, fakeRun{id: runA, styles: registry, cells: a})

	var b []fakeCell
	for _, m := range []string{"b", "c"} {
		for p, scene := range []string{"s1", "s2"} {
			for _, st := range []string{"", "baroque", "ink"} {
				b = append(b, fakeCell{model: m, style: st, prompt: p, scene: scene, seed: 777,
					character: "red hair", missing: m == "b" && p == 1 && st == "ink"})
			}
		}
	}
	writeRun(t, lab, fakeRun{id: runB, status: "cancelled", styles: registry, cells: b})

	var c []fakeCell
	for p, scene := range []string{"s2", "s1"} {
		for _, st := range []string{"", "cave"} {
			c = append(c, fakeCell{model: "a", style: st, prompt: p, scene: scene, seed: 101})
		}
	}
	writeRun(t, lab, fakeRun{id: runC, styles: registry, cells: c})

	writeRun(t, lab, fakeRun{id: runD, styles: registry, cells: []fakeCell{
		{model: "d", prompt: 0}, {model: "d", prompt: 1, style: "ink"},
	}})

	// Two characters: four prompt columns, two per scene, as the dump writes them.
	var e []fakeCell
	for i, ch := range []string{"red hair", "blue eyes"} {
		for p, scene := range []string{"s1", "s2"} {
			e = append(e, fakeCell{model: "e", prompt: i*2 + p, scene: scene, character: ch, seed: 777})
		}
	}
	writeRun(t, lab, fakeRun{id: runE, styles: registry, cells: e})
	return lab
}

func TestLoadRunCountsPicturesAndEmptyFiles(t *testing.T) {
	col := mustLoad(t, fixture(t))
	a := col.Run(runA)
	if a == nil {
		t.Fatal("běh A chybí")
	}
	// 6 planned cells (the position photo is not a picture of the matrix),
	// one missing, one 0-byte.
	if a.Total != 6 || len(a.Pics) != 4 || a.Empty != 1 {
		t.Fatalf("total %d pics %d empty %d, čekám 6/4/1", a.Total, len(a.Pics), a.Empty)
	}
	if a.StyleCount() != 3 {
		t.Fatalf("stylů s obrázkem %d, čekám 3", a.StyleCount())
	}
	if col.Run(runB).Status != "cancelled" {
		t.Fatal("stav běhu se má číst ze state.json")
	}
}

func TestFamilyComesFromPlannedPrompts(t *testing.T) {
	col := mustLoad(t, fixture(t))
	a, b, d := col.Run(runA), col.Run(runB), col.Run(runD)
	if a.Family == "" || a.Family != b.Family {
		t.Fatalf("A a B mají stejné scény, rodina %q × %q", a.Family, b.Family)
	}
	if a.Family == d.Family {
		t.Fatal("běh bez promptového souboru nepatří do rodiny scén")
	}
	got := col.FamilyOf(runA)
	ids := []string{}
	for _, r := range got {
		ids = append(ids, r.ID)
	}
	// C has the same scenes in another order, E the same scenes twice.
	want := []string{runA, runB, runC, runE}
	if !reflect.DeepEqual(ids, want) {
		t.Fatalf("rodina %v, čekám %v", ids, want)
	}
	fams := col.Families(1)
	if len(fams) == 0 || len(fams[0].Runs) != 4 || len(fams[0].Models) != 4 {
		t.Fatalf("první rodina má mít 4 běhy a 4 modely: %+v", fams[0])
	}
}

func TestSingleCharacterIsSetupNotAxis(t *testing.T) {
	col := mustLoad(t, fixture(t))
	for _, p := range col.Run(runB).Pics {
		if p.Character != "" {
			t.Fatalf("jediná postava běhu má jít do nastavení, ne do osy: %q", p.Character)
		}
	}
	chars := map[string]bool{}
	for _, p := range col.Run(runE).Pics {
		chars[p.Character] = true
	}
	if !chars["red hair"] || !chars["blue eyes"] {
		t.Fatalf("dvě postavy v jednom běhu jsou osa: %v", chars)
	}
	// B's character went into its setup: same scene, model-independent key,
	// different setup from a run without a character.
	if col.Run(runB).Pics[0].Setup == col.Run(runA).Pics[0].Setup {
		t.Fatal("postava se má promítnout do otisku nastavení")
	}
}

func TestPoolIdentity(t *testing.T) {
	col := mustLoad(t, fixture(t))
	if p := mustPool(t, col, "", runA, runB); p.Identity != IdentityScene {
		t.Fatalf("běhy se scénami → scene, ne %s", p.Identity)
	}
	if p := mustPool(t, col, "", runA, runD); p.Identity != IdentityColumn {
		t.Fatalf("běh bez scén → column, ne %s", p.Identity)
	}
	_, err := NewPool([]*Run{col.Run(runA), col.Run(runD)}, IdentityScene, "first")
	if err == nil || !strings.Contains(err.Error(), runD) {
		t.Fatalf("scene s během bez scén má říct, který běh to je: %v", err)
	}
}

func TestPoolOrders(t *testing.T) {
	col := mustLoad(t, fixture(t))
	p := mustPool(t, col, "", runA, runB)
	if got, want := p.Values(AxStyle), []string{Baseline, "cave", "baroque", "vermeer", "ink"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("styly %v, čekám baseline a pak pořadí pickeru %v", got, want)
	}
	if got := p.Values(AxModel); !reflect.DeepEqual(got, []string{"a", "b", "c"}) {
		t.Fatalf("modely %v", got)
	}
	if got := p.Label(AxStyle, "vermeer"); got != "Vermeer (y)" {
		t.Fatalf("popisek stylu je labelWithYear, ne %q", got)
	}
	// C alone lists s2 first.
	if got := mustPool(t, col, "", runC).Values(AxPrompt); !reflect.DeepEqual(got, []string{"s2", "s1"}) {
		t.Fatalf("prompty v pořadí běhu, ne %v", got)
	}
}

func TestPoolCollisions(t *testing.T) {
	col := mustLoad(t, fixture(t))
	p := mustPool(t, col, "", runA, runC)
	// a×{baseline, cave}×{s1, s2} in C; A has a baseline s1, s2 and cave s1.
	if len(p.Collisions) != 3 || p.DifferentSetups != 3 {
		t.Fatalf("kolizí %d (jiné nastavení %d), čekám 3/3", len(p.Collisions), p.DifferentSetups)
	}
	for _, pic := range p.Pics {
		if pic.Style == Baseline && pic.Run != runA {
			t.Fatal("prefer first: kolize bere první uvedený běh")
		}
	}
	newest, err := NewPool([]*Run{col.Run(runA), col.Run(runC)}, "", "newest")
	if err != nil {
		t.Fatal(err)
	}
	for _, pic := range newest.Pics {
		if pic.Style == Baseline && pic.Run != runC {
			t.Fatal("prefer newest: kolize bere novější běh")
		}
	}
	if _, err := NewPool([]*Run{col.Run(runA), col.Run(runC)}, "", "error"); err == nil {
		t.Fatal("prefer error má kolizi odmítnout")
	}
}

func TestSelect(t *testing.T) {
	col := mustLoad(t, fixture(t))
	p := mustPool(t, col, "", runA, runB)
	s := p.Select(Selection{Only: map[string][]string{AxModel: {"c", "b"}}})
	if got := s.Values(AxModel); !reflect.DeepEqual(got, []string{"c", "b"}) {
		t.Fatalf("pořadí z výběru má vyhrát: %v", got)
	}
	s = p.Select(Selection{Not: map[string][]string{AxStyle: {Baseline}}, Kinds: []string{"culture"}})
	if got := s.Values(AxStyle); !reflect.DeepEqual(got, []string{"cave", "baroque"}) {
		t.Fatalf("jen kultury bez baseline: %v", got)
	}
	if _, err := ParseWhere([]string{"barva=red"}); err == nil {
		t.Fatal("neznámá osa má být chyba")
	}
}

func TestCoverage(t *testing.T) {
	col := mustLoad(t, fixture(t))
	cov, err := mustPool(t, col, "", runA, runB).Coverage(AxModel, AxStyle, AxPrompt)
	if err != nil {
		t.Fatal(err)
	}
	// cols: baseline, cave, baroque, vermeer, ink
	want := [][]int{
		{2, 1, 0, 1, 0}, // a: cave and vermeer only in s1 (s2 missing / 0 B)
		{2, 0, 2, 0, 1}, // b: ink missing in s2
		{2, 0, 2, 0, 2},
	}
	if !reflect.DeepEqual(cov.Cells, want) || cov.Of != 2 {
		t.Fatalf("pokrytí %v z %d, čekám %v z 2", cov.Cells, cov.Of, want)
	}
}

func TestSuggest(t *testing.T) {
	col := mustLoad(t, fixture(t))
	sg, err := mustPool(t, col, "", runA, runB).Suggest(AxModel, []string{AxStyle}, 3, 5)
	if err != nil {
		t.Fatal(err)
	}
	got := map[string][2]int{}
	for _, k := range sg.Ks() {
		for _, s := range sg.ByK[k] {
			got[strings.Join(s.Values, ",")] = [2]int{s.Strict, s.Loose}
		}
	}
	// Strict: same prompt and style. Loose: per prompt, the fewest styles any
	// of the models has (s1: 3/3/3, s2: a 1, b 2, c 3).
	want := map[string][2]int{"a,b": {2, 4}, "a,c": {2, 4}, "b,c": {5, 5}, "a,b,c": {2, 4}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("návrhy %v, čekám %v", got, want)
	}
	if sg.ByK[2][0].Strict != 5 {
		t.Fatal("nejlepší dvojice je b+c")
	}
}

func TestCacheFollowsManifest(t *testing.T) {
	lab := fixture(t)
	col := mustLoad(t, lab)
	if _, err := os.Stat(filepath.Join(lab, "_video", ".index", runA+".json")); err != nil {
		t.Fatal("index se má uložit do cache")
	}
	if len(col.Run(runA).Pics) != 4 {
		t.Fatal("výchozí stav")
	}
	// The run draws more: a picture appears (no manifest change) …
	man := filepath.Join(lab, runA, "img", "txt2img__a__cave__p01.png")
	if err := os.WriteFile(man, tinyPNG(t), 0o644); err != nil {
		t.Fatal(err)
	}
	if n := len(mustLoad(t, lab).Run(runA).Pics); n != 5 {
		t.Fatalf("nový obrázek má být vidět hned, pics %d", n)
	}
	// … and a new dump replaces the manifest: the cache is stale.
	writeRun(t, lab, fakeRun{id: runA, styles: registry, cells: []fakeCell{{model: "z", scene: "s9"}}})
	r := mustLoad(t, lab).Run(runA)
	if len(r.Pics) != 1 || r.Pics[0].Model != "z" {
		t.Fatalf("změněný manifest má zneplatnit cache: %+v", r.Pics)
	}
}

func TestLabDirectoriesWithUnderscoreAreNotRuns(t *testing.T) {
	lab := fixture(t)
	writeRun(t, lab, fakeRun{id: "_merged", cells: []fakeCell{{model: "x", scene: "s1"}}})
	if mustLoad(t, lab).Run("_merged") != nil {
		t.Fatal("adresáře s podtržítkem jsou labu, ne běhy")
	}
}
