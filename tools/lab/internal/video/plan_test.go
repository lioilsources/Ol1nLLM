package video

import (
	"errors"
	"os"
	"reflect"
	"strings"
	"testing"
)

func mustRecipe(t *testing.T, y string) Recipe {
	t.Helper()
	rs, err := ParseRecipes([]byte(y))
	if err != nil {
		t.Fatal(err)
	}
	return rs[0]
}

func mustPlan(t *testing.T, col *Collection, y string) *Storyboard {
	t.Helper()
	sb, err := Plan(col, mustRecipe(t, y))
	if err != nil {
		t.Fatal(err)
	}
	return sb
}

func TestParseRecipeRejectsUnknownKeysWithLine(t *testing.T) {
	_, err := ParseRecipes([]byte("name: x\nsource: {runs: [a]}\ntime:\n  rate: 2\n  tempo: 3\n"))
	if err == nil || !strings.Contains(err.Error(), "tempo") || !strings.Contains(err.Error(), "řádek 5") {
		t.Fatalf("neznámý klíč má říct jméno a řádek: %v", err)
	}
	_, err = ParseRecipes([]byte("source: {runs: [a]}\nselect: {style: {nic: [x]}}\n"))
	if err == nil || !strings.Contains(err.Error(), "nic") {
		t.Fatalf("neznámý klíč filtru: %v", err)
	}
}

func TestParseRecipeDefaultsAndDocuments(t *testing.T) {
	rs, err := ParseRecipes([]byte("source: {runs: [a]}\n---\nname: b\nsource: {family: a}\nframe: {cols: 3, captions: auto}\n"))
	if err != nil {
		t.Fatal(err)
	}
	if len(rs) != 2 {
		t.Fatalf("dva dokumenty, ne %d", len(rs))
	}
	r := rs[0]
	if r.Name != "video" || r.Time.Rate != 4 || *r.Time.Fade != 0.4 || !*r.Time.Complete ||
		r.Output.Size != "1080x1920" || r.Output.FPS != 30 || r.Frame.Captions.Mode != "none" {
		t.Fatalf("výchozí hodnoty: %+v", r)
	}
	if rs[1].Frame.Cols != 3 || rs[1].Frame.Captions.Mode != "auto" {
		t.Fatalf("cols a captions: %+v", rs[1].Frame)
	}
}

func TestValidateExplainsCombinations(t *testing.T) {
	cases := map[string]string{
		"time: {axes: [prompt, style], loose: [style]}":                            "jen s frame.tiles",
		"frame: {tiles: model}\ntime: {axes: [style, prompt], loose: [style]}":     "vnitřní konec",
		"frame: {tiles: model}\ntime: {axes: [model]}":                             "jednu roli",
		"frame: {tiles: model, fit: cover}":                                        "cover jde jen bez dlaždic",
		"time: {rate: 60}":                                                         "nejvýš snímků",
		"time: {axes: [prompt, style]}\noutput: {split: {seconds: 60, at: model}}": "striktní osa",
		"select: {model: {kind: [artist]}}":                                        "jen styly",
	}
	for body, want := range cases {
		_, err := ParseRecipes([]byte("source: {runs: [a]}\n" + body + "\n"))
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("%q: čekám %q, chyba %v", body, want, err)
		}
	}
}

func TestRoleRuleNamesTheAxisAndTheFixes(t *testing.T) {
	col := mustLoad(t, fixture(t))
	_, err := Plan(col, mustRecipe(t, "source: {runs: ["+runA+", "+runB+"]}\ntime: {axes: [prompt, style]}\n"))
	var pe *PlanError
	if !errors.As(err, &pe) {
		t.Fatalf("čekám PlanError, ne %v", err)
	}
	msg := pe.Error()
	for _, want := range []string{"osa model má 3 hodnot", "M a", "time.axes", "output.per", "select.model"} {
		if !strings.Contains(msg, want) {
			t.Errorf("chybí %q v %q", want, msg)
		}
	}
}

func TestTimeAxesDefaultToEveryAxisWithoutRole(t *testing.T) {
	col := mustLoad(t, fixture(t))
	sb := mustPlan(t, col, "source: {runs: ["+runA+"]}\n")
	if got := sb.Recipe.Time.Axes; !reflect.DeepEqual(got, []string{AxPrompt, AxStyle}) {
		t.Fatalf("osy času %v", got)
	}
	// One picture per slide, prompt then style; A has four pictures.
	if len(sb.Slides) != 4 || sb.Slides[0].Key[AxPrompt] != "s1" || sb.Slides[3].Key[AxPrompt] != "s2" {
		t.Fatalf("snímky: %+v", sb.Slides)
	}
}

func TestStrictTilesDropIncompleteSlides(t *testing.T) {
	col := mustLoad(t, fixture(t))
	y := "source: {runs: [" + runA + ", " + runB + "]}\nframe: {tiles: model}\ntime: {axes: [prompt, style]}\n"
	sb := mustPlan(t, col, y)
	// Keys: s1 × 5 styles, s2 × 3; only the baseline has all three models.
	if len(sb.Slides) != 2 || sb.Stats.Dropped["incomplete"] != 6 {
		t.Fatalf("snímků %d, neúplných %d; čekám 2 a 6", len(sb.Slides), sb.Stats.Dropped["incomplete"])
	}
	if got := []string{sb.Tiles[0].ID, sb.Tiles[1].ID, sb.Tiles[2].ID}; !reflect.DeepEqual(got, []string{"a", "b", "c"}) {
		t.Fatalf("dlaždice %v", got)
	}
	all := mustPlan(t, col, strings.Replace(y, "axes: [prompt, style]", "axes: [prompt, style], complete: false", 1))
	if len(all.Slides) != 8 || all.Slides[1].Tiles[1] != nil {
		t.Fatalf("complete: false nechá prázdné dlaždice: %d snímků", len(all.Slides))
	}
	// Selection order is the tile order.
	sel := mustPlan(t, col, y+"select: {model: [c, a]}\n")
	if sel.Tiles[0].ID != "c" || sel.Tiles[1].ID != "a" {
		t.Fatalf("pořadí dlaždic z výběru: %+v", sel.Tiles)
	}
}

func TestLooseStylesOrderAndKind(t *testing.T) {
	col := mustLoad(t, fixture(t))
	base := "source: {runs: [" + runA + ", " + runB + "]}\nframe: {tiles: model, captions: [model, style], title: prompt}\n"
	order := mustPlan(t, col, base+"time: {axes: [prompt, style], loose: [style], complete: false}\n")
	type row struct{ match, a, b, c string }
	got := []row{}
	style := func(t *TileRef) string {
		if t == nil {
			return "—"
		}
		return t.Style
	}
	for _, s := range order.Slides {
		got = append(got, row{s.Match, style(s.Tiles[0]), style(s.Tiles[1]), style(s.Tiles[2])})
	}
	want := []row{
		{"exact", Baseline, Baseline, Baseline},
		{"order", "cave", "baroque", "baroque"},
		{"order", "vermeer", "ink", "ink"},
		{"exact", Baseline, Baseline, Baseline},
		{"order", "—", "baroque", "baroque"},
		{"order", "—", "—", "ink"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("pořadí:\n%v\nčekám\n%v", got, want)
	}
	if order.Slides[1].Title != "s1" || order.Slides[1].Captions[0][1] != "Cave (y)" {
		t.Fatalf("titulek je prompt, popisek model + styl: %q %v", order.Slides[1].Title, order.Slides[1].Captions)
	}
	// kind: cave (culture) meets baroque (culture), vermeer (artist) has no
	// artist partner and goes to order.
	kind := mustPlan(t, col, base+"time: {axes: [prompt, style], loose: [style], pair: kind}\n")
	if kind.Stats.Match["exact"] != 2 || kind.Stats.Match["kind"] != 1 || kind.Stats.Match["order"] != 1 {
		t.Fatalf("žebřík: %v", kind.Stats.Match)
	}
	exact := mustPlan(t, col, base+"time: {axes: [prompt, style], loose: [style], pair: exact}\n")
	if len(exact.Slides) != 2 {
		t.Fatalf("pair: exact nechá jen společné styly, snímků %d", len(exact.Slides))
	}
}

func TestSplitRangesMatchesThePythonTool(t *testing.T) {
	var keys []string
	for i, n := range []int{31, 31, 31, 10} {
		for j := 0; j < n; j++ {
			keys = append(keys, string(rune('a'+i)))
		}
	}
	// The case make_video.py was tested with: 62 × 0.25 = 15.5 s fits in 20 s,
	// a third group (23.25 s) does not; the last two make 10.25 s.
	if got := SplitRanges(keys, 0.25, 20); !reflect.DeepEqual(got, [][2]int{{0, 62}, {62, 103}}) {
		t.Fatalf("dělení %v", got)
	}
	// A group longer than the limit gets a part of its own.
	long := append(make([]string, 100), "x", "x", "x", "x", "x")
	if got := SplitRanges(long, 1, 30); !reflect.DeepEqual(got, [][2]int{{0, 100}, {100, 105}}) {
		t.Fatalf("dlouhá skupina sama: %v", got)
	}
}

func TestPerAndSplitName(t *testing.T) {
	col := mustLoad(t, fixture(t))
	sb := mustPlan(t, col, "name: m\nsource: {runs: ["+runA+", "+runB+"]}\ntime: {axes: [prompt, style], rate: 1}\noutput: {per: [model], split: {seconds: 3}}\n")
	var names []string
	for _, v := range sb.Videos {
		names = append(names, v.Name)
	}
	// a has 3 pictures in s1 and 1 in s2 → 3 s + 1 s; b: 3 + 2; c: 3 + 3.
	want := []string{"m-a-01", "m-a-02", "m-b-01", "m-b-02", "m-c-01", "m-c-02"}
	if !reflect.DeepEqual(names, want) {
		t.Fatalf("jména %v", names)
	}
	if sb.Videos[0].Per[AxModel] != "a" || sb.Videos[0].Groups[0] != "s1" {
		t.Fatalf("díl nese hodnotu per a skupiny: %+v", sb.Videos[0])
	}
}

func TestMaxSecondsKeepsWholeModelSets(t *testing.T) {
	col := mustLoad(t, fixture(t))
	sb := mustPlan(t, col, "source: {runs: ["+runB+"]}\nselect: {prompt: s1}\ntime: {axes: [style, model], rate: 1}\noutput: {max_seconds: 4}\n")
	// Three styles × two models; 4 s at 1/s keeps two whole styles.
	if len(sb.Slides) != 4 || sb.Slides[0].Key[AxStyle] != sb.Slides[1].Key[AxStyle] {
		t.Fatalf("zkrácení po celých stylech: %d snímků", len(sb.Slides))
	}
}

func TestTemplatesPlanAsTheyAre(t *testing.T) {
	col := mustLoad(t, fixture(t))
	pool := mustPool(t, col, "", runA, runB)
	for _, tm := range Templates {
		r, _ := FromTemplate(tm.ID, tm.ID, Source{Runs: []string{runA, runB}}, pool)
		text, err := TemplateYAML(r, pool, nil)
		if err != nil {
			t.Fatal(err)
		}
		rs, err := ParseRecipes([]byte(text))
		if err != nil {
			t.Fatalf("%s: šablona se nenačte: %v\n%s", tm.ID, err, text)
		}
		if _, err := Plan(col, rs[0]); err != nil && !strings.Contains(err.Error(), "nezbyl") {
			t.Fatalf("%s: šablona se nenaplánuje: %v", tm.ID, err)
		}
	}
	if _, err := TemplateID("Plátno"); err != nil {
		t.Fatal("šablona i s diakritikou")
	}
}

func TestLayout(t *testing.T) {
	// Six squares on 9:16 → 2 × 3; six 2:3 pictures → 3 × 2.
	if l := ComputeLayout(1080, 1920, 6, 0, 1, false, 0, true); l.Cols != 2 || l.Rows != 3 {
		t.Fatalf("čtverce: %d×%d", l.Cols, l.Rows)
	}
	l := ComputeLayout(1080, 1920, 6, 0, 2.0/3, true, 2, true)
	if l.Cols != 3 || l.Rows != 2 {
		t.Fatalf("2:3: %d×%d", l.Cols, l.Rows)
	}
	safeTop, safeBottom := 163, 1690
	for i, a := range l.Tiles {
		if a.Pic.Y < safeTop || a.Caption.Y+a.Caption.H > safeBottom+1 {
			t.Fatalf("dlaždice %d mimo bezpečnou zónu: %+v", i, a)
		}
		if l.Title != nil && a.Pic.Y < l.Title.Y+l.Title.H {
			t.Fatalf("dlaždice %d pod titulkem", i)
		}
		for j, b := range l.Tiles {
			if i != j && overlaps(a.Pic, b.Pic) {
				t.Fatalf("dlaždice %d a %d se překrývají", i, j)
			}
		}
	}
	if l := ComputeLayout(1080, 1920, 2, 1, 1, false, 0, true); l.Cols != 1 || l.Rows != 2 {
		t.Fatalf("cols: 1 = pod sebou: %d×%d", l.Cols, l.Rows)
	}
	if l := ComputeLayout(1080, 1920, 0, 0, 1, false, 0, false); !l.Single {
		t.Fatal("bez dlaždic je jeden obrázek")
	}
	if l := ComputeLayout(1080, 1920, 0, 0, 1, true, 0, false); l.CaptionTop < l.Title.Y+l.Title.H {
		t.Fatal("popisek jednoho obrázku má být pod titulkem")
	}
}

func overlaps(a, b Rect) bool {
	return a.X < b.X+b.W && b.X < a.X+a.W && a.Y < b.Y+b.H && b.Y < a.Y+a.H
}

func TestExampleRecipesParse(t *testing.T) {
	data, err := os.ReadFile("../../candidates/video-examples.yaml")
	if err != nil {
		t.Fatal(err)
	}
	rs, err := ParseRecipes(data)
	if err != nil {
		t.Fatalf("ukázky v candidates/ se mají načíst: %v", err)
	}
	if len(rs) != 6 {
		t.Fatalf("ukázek %d", len(rs))
	}
}

func fp(v float64) *float64 { return &v }

func TestReferenceTile(t *testing.T) {
	lab := t.TempDir()
	// A repose run with a reference picture, and a restyle drawn over a
	// position photo.
	writeRun(t, lab, fakeRun{id: "20260201-000001", ref: "_refs/foto.png", styles: registry, cells: []fakeCell{
		{model: "a", flow: "repose", scene: "s1"}, {model: "b", flow: "repose", scene: "s1"},
	}})
	writeRun(t, lab, fakeRun{id: "20260201-000002", styles: registry, cells: []fakeCell{
		{id: "pos-s1", model: "p", flow: "position", scene: "s1"},
		{model: "a", flow: "restyle", scene: "s1", dependsOn: "pos-s1"},
		{model: "b", flow: "restyle", scene: "s1", dependsOn: "pos-s1"},
	}})
	col := mustLoad(t, lab)
	y := "frame: {tiles: model, reference: true, captions: auto}\n"
	sb := mustPlan(t, col, "source: {runs: [20260201-000001]}\n"+y)
	if sb.Tiles[0].ID != refSlot || len(sb.Layout.Tiles) != 3 {
		t.Fatalf("předloha je první dlaždice: %+v, rozložení %d", sb.Tiles, len(sb.Layout.Tiles))
	}
	s := sb.Slides[0]
	if s.Tiles[0] == nil || s.Tiles[0].Img != "_refs/foto.png" || s.Captions[0][0] != "předloha" {
		t.Fatalf("předloha běhu: %+v %v", s.Tiles[0], s.Captions)
	}
	sb = mustPlan(t, col, "source: {runs: [20260201-000002]}\n"+y)
	if got := sb.Slides[0].Tiles[0]; got == nil || got.Img != "20260201-000002/img/pos-s1.png" {
		t.Fatalf("u restylu je předloha fotka pozice: %+v", got)
	}
	if _, err := ParseRecipes([]byte("source: {runs: [a]}\nframe: {reference: true}\n")); err == nil {
		t.Fatal("předloha bez dlaždic má být chyba")
	}
}

func TestMinReaction(t *testing.T) {
	lab := t.TempDir()
	writeRun(t, lab, fakeRun{id: "20260301-000001", styles: registry, cells: []fakeCell{
		{model: "a", scene: "s1"},
		{model: "a", scene: "s1", style: "cave", reaction: fp(0.05)},
		{model: "a", scene: "s1", style: "vermeer", reaction: fp(0.5)},
	}})
	writeRun(t, lab, fakeRun{id: "20260301-000002", styles: registry, cells: []fakeCell{
		{model: "b", scene: "s1", style: "ink"},
	}})
	col := mustLoad(t, lab)
	sb := mustPlan(t, col, "source: {runs: [20260301-000001]}\nselect: {min_reaction: 0.15}\n")
	var styles []string
	for _, s := range sb.Slides {
		styles = append(styles, s.Key[AxStyle])
	}
	if strings.Join(styles, ",") != Baseline+",vermeer" || sb.Stats.Dropped["reaction"] != 1 {
		t.Fatalf("bez stylu zůstává, cave (0.05) vypadne: %v, vyřazeno %v", styles, sb.Stats.Dropped)
	}
	sb = mustPlan(t, col, "source: {runs: [20260301-000002]}\nselect: {min_reaction: 0.15}\n")
	if len(sb.Slides) != 1 || len(sb.Warnings) == 0 || !strings.Contains(sb.Warnings[0], "nemá metriky") {
		t.Fatalf("běh bez metrik se nefiltruje, ale řekne to: %v %v", len(sb.Slides), sb.Warnings)
	}
	if _, err := ParseRecipes([]byte("source: {runs: [a]}\nselect: {min_reaction: hodně}\n")); err == nil {
		t.Fatal("min_reaction musí být číslo")
	}
}
