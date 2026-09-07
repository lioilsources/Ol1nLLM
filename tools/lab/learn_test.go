package main

import (
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// The rules in decide.go stated as a table, plus one end-to-end pass from
// fixture JSON to the exact Dart that gets committed.
//
// A guard is worth testing at its edge, not in its middle: every case here
// sits one rating or one percent from flipping, because that is where a rule
// that "usually works" stops working.

func cellOf(up, down int) *EvalCell {
	c := &EvalCell{Up: up, Down: down}
	c.Rated = up + down
	if c.Rated == 0 {
		return c
	}
	rate, lo, hi := wilsonTest(up, down)
	c.Rate, c.Lower, c.Upper = &rate, &lo, &hi
	c.Eligible = c.Rated
	return c
}

// wilsonTest mirrors the gallery's own arithmetic — the lab never computes it
// in production, but a fixture built with a different formula would test the
// fixture rather than the rule.
func wilsonTest(up, down int) (rate, lower, upper float64) {
	n := float64(up + down)
	const z = 1.959963984540054
	p := float64(up) / n
	denom := 1 + z*z/n
	center := p + z*z/(2*n)
	margin := z * math.Sqrt(p*(1-p)/n+z*z/(4*n*n))
	lo := (center - margin) / denom
	hi := (center + margin) / denom
	if lo < 0 {
		lo = 0
	}
	if hi > 1 {
		hi = 1
	}
	return p, lo, hi
}

func TestDecideWinner(t *testing.T) {
	tests := []struct {
		name    string
		cands   []Candidate
		min     int
		want    string // winning key, "" = fallback
		wantWhy string // substring the reason must carry
	}{
		{
			name: "guard not met — nothing reached min",
			cands: []Candidate{
				{"a", "A", cellOf(5, 1)},
				{"b", "B", cellOf(4, 2)},
			},
			min: 10, want: "", wantWhy: "min=10",
		},
		{
			name: "guard met and intervals separate — decided",
			cands: []Candidate{
				{"a", "A", cellOf(20, 2)},
				{"b", "B", cellOf(6, 13)},
			},
			min: 10, want: "a", wantWhy: "dolní mez",
		},
		{
			name: "guard met but intervals overlap — refusal",
			cands: []Candidate{
				{"a", "A", cellOf(8, 4)},
				{"b", "B", cellOf(7, 4)},
			},
			min: 10, want: "", wantWhy: "překrývají",
		},
		{
			name: "a tie is an overlap, not a coin flip",
			cands: []Candidate{
				{"a", "A", cellOf(10, 5)},
				{"b", "B", cellOf(10, 5)},
			},
			min: 10, want: "", wantWhy: "překrývají",
		},
		{
			name:  "one arm over the threshold wins nothing but says so",
			cands: []Candidate{{"a", "A", cellOf(20, 2)}, {"b", "B", cellOf(2, 1)}},
			min:   10, want: "a", wantWhy: "jediné rameno",
		},
		{
			name: "an arm below min cannot beat one above it",
			// B has the better observed rate, and three ratings behind it.
			cands: []Candidate{
				{"a", "A", cellOf(20, 2)},
				{"b", "B", cellOf(3, 0)},
			},
			min: 10, want: "a", wantWhy: "jediné rameno",
		},
		{name: "empty input", cands: nil, min: 10, want: "", wantWhy: "žádná ramena"},
		{
			name:  "unrated arms are not arms",
			cands: []Candidate{{"a", "A", cellOf(0, 0)}, {"b", "B", nil}},
			min:   10, want: "", wantWhy: "min=10",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := decideWinner(tt.cands, tt.min)
			if tt.want == "" {
				if got.Decided() {
					t.Fatalf("čekal fallback, dostal %q (%s)", got.Value.Key, got.Reason)
				}
			} else {
				if !got.Decided() {
					t.Fatalf("čekal %q, dostal fallback (%s)", tt.want, got.Reason)
				}
				if got.Value.Key != tt.want {
					t.Fatalf("vítěz = %q, čekal %q", got.Value.Key, tt.want)
				}
			}
			if !strings.Contains(got.Reason, tt.wantWhy) {
				t.Fatalf("důvod %q neobsahuje %q", got.Reason, tt.wantWhy)
			}
			if got.Reason == "" {
				t.Fatal("rozhodnutí bez důvodu — porušuje I3")
			}
		})
	}
}

func TestDecideWinnerIsDeterministic(t *testing.T) {
	// Same lower bound on both arms: the order the map or the server gave them
	// in must not decide anything, or the golden file churns on every run.
	a := []Candidate{{"b", "B", cellOf(12, 4)}, {"a", "A", cellOf(12, 4)}}
	b := []Candidate{{"a", "A", cellOf(12, 4)}, {"b", "B", cellOf(12, 4)}}
	if decideWinner(a, 10).Reason != decideWinner(b, 10).Reason {
		t.Fatal("pořadí vstupu změnilo výsledek")
	}
}

func TestDecideStyleFlag(t *testing.T) {
	tests := []struct {
		name string
		cell *EvalCell
		min  int
		want StyleVerdict
	}{
		// upper 0.298 — clears the 0.35 bar for "this model does not do it"
		{"weak: upper under the bar", cellOf(1, 14), 10, StyleWeak},
		// upper 0.379 — above the bar, so no verdict even though 2/15 looks bad
		{"no flag: upper just over the bar", cellOf(2, 13), 10, ""},
		// lower 0.773 — over the 0.75 bar
		{"strong: lower over the bar", cellOf(20, 1), 10, StyleStrong},
		// lower 0.686 — under it
		{"no flag: lower just under the bar", cellOf(17, 2), 10, ""},
		{"no flag: sample too thin", cellOf(0, 6), 10, ""},
		{"no flag: nothing rated", cellOf(0, 0), 10, ""},
		{"no flag: no cell at all", nil, 10, ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := decideStyleFlag(tt.cell, tt.min)
			if tt.want == "" {
				if ok {
					t.Fatalf("čekal žádný příznak, dostal %s (%s)", got.Verdict, got.Reason)
				}
				return
			}
			if !ok {
				t.Fatalf("čekal %s, dostal nic", tt.want)
			}
			if got.Verdict != tt.want {
				t.Fatalf("verdikt = %s, čekal %s", got.Verdict, tt.want)
			}
			if got.Reason == "" {
				t.Fatal("příznak bez důvodu — porušuje I3")
			}
		})
	}
}

func TestLoraStrengthNeedsTwoArms(t *testing.T) {
	l := &Learned{LoraStrength: map[string]Decision[float64]{}}
	learnLoraStrength(l, &EvalResponse{Rows: []*EvalRow{
		{Key: "solo.safetensors @ 0.90", Label: "solo", Like: *cellOf(15, 3)},
	}}, 10)
	d := l.LoraStrength["solo.safetensors"]
	if d.Decided() {
		t.Fatal("jedno rameno není porovnání")
	}
	if !strings.Contains(d.Reason, "jen jedna síla") {
		t.Fatalf("důvod = %q", d.Reason)
	}
}

func TestLoraStrengthIgnoresStrengthlessRuns(t *testing.T) {
	// A run recorded before the strength column existed has a name and no
	// strength. Letting it in would let an unknown value win a comparison.
	l := &Learned{LoraStrength: map[string]Decision[float64]{}}
	learnLoraStrength(l, &EvalResponse{Rows: []*EvalRow{
		{Key: "legacy.safetensors", Label: "legacy", Like: *cellOf(30, 1)},
		{Key: "", Label: "(no LoRA)", Like: *cellOf(40, 10)},
	}}, 10)
	if len(l.LoraStrength) != 0 {
		t.Fatalf("čekal prázdno, dostal %v", l.LoraStrength)
	}
}

// ── end to end ─────────────────────────────────────────────

// fakeGallery serves the fixtures the way the real endpoint would, so the
// golden test exercises the URL building and the JSON shape too, not only the
// rules.
func fakeEvalGallery(t *testing.T) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/eval" {
			http.NotFound(w, r)
			return
		}
		if r.Header.Get("CF-Access-Client-Id") == "" {
			http.Error(w, `{"error":"no creds"}`, http.StatusForbidden)
			return
		}
		name := "eval_" + r.URL.Query().Get("group") + ".json"
		if m := r.URL.Query().Get("model"); m != "" {
			name = "eval_style_" + m + ".json"
		}
		data, err := os.ReadFile(filepath.Join("testdata", name))
		if err != nil {
			// An unseeded slice is an empty one, not a 500: the real gallery
			// answers every group, just with no rows.
			w.Header().Set("Content-Type", "application/json")
			w.Write([]byte(`{"group":"` + r.URL.Query().Get("group") + `","rows":[]}`))
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write(data)
	}))
}

func TestLearnGolden(t *testing.T) {
	srv := fakeEvalGallery(t)
	defer srv.Close()

	old := nowUTC
	nowUTC = func() time.Time { return time.Date(2026, 9, 7, 14, 2, 0, 0, time.UTC) }
	defer func() { nowUTC = old }()

	ft := NewFinetune(srv.URL, "id", "secret")
	l, err := Learn(ft, 10)
	if err != nil {
		t.Fatal(err)
	}
	// The test server's port is not knowledge, and it changes every run.
	l.GalleryHost = "finetune.ol1n.com"
	got := EmitDart(l)

	golden := filepath.Join("testdata", "learned_expected.dart")
	if os.Getenv("UPDATE_GOLDEN") == "1" {
		if err := os.WriteFile(golden, []byte(got), 0o644); err != nil {
			t.Fatal(err)
		}
		t.Log("golden přepsán")
	}
	want, err := os.ReadFile(golden)
	if err != nil {
		t.Fatal(err)
	}
	if got != string(want) {
		t.Fatalf("emitovaný Dart se liší od golden souboru. "+
			"Když je změna zamýšlená: UPDATE_GOLDEN=1 go test ./...\n\n--- got ---\n%s", got)
	}
}

// TestGoldenIsAnalyzedAsDart keeps the golden and its copy under test/fixtures
// in lockstep. Nothing here can tell whether the emitted text is valid Dart —
// but `flutter analyze` reads that copy, so the two files being identical is
// what turns the analyzer into a check on this generator.
func TestGoldenIsAnalyzedAsDart(t *testing.T) {
	golden, err := os.ReadFile(filepath.Join("testdata", "learned_expected.dart"))
	if err != nil {
		t.Fatal(err)
	}
	fixture, err := os.ReadFile(filepath.Join("..", "..", "test", "fixtures", "learned_golden.dart"))
	if err != nil {
		t.Fatal(err)
	}
	if string(golden) != string(fixture) {
		t.Fatal("test/fixtures/learned_golden.dart se rozešel s golden souborem — " +
			"zkopíruj: cp tools/lab/testdata/learned_expected.dart test/fixtures/learned_golden.dart")
	}
}

func TestEmitIsDeterministic(t *testing.T) {
	srv := fakeEvalGallery(t)
	defer srv.Close()
	ft := NewFinetune(srv.URL, "id", "secret")

	a, err := Learn(ft, 10)
	if err != nil {
		t.Fatal(err)
	}
	b, err := Learn(ft, 10)
	if err != nil {
		t.Fatal(err)
	}
	// Snapshot aside, two runs over unchanged data must be byte-identical —
	// otherwise every `lab learn` produces a diff and the review means nothing.
	b.SnapshotAt = a.SnapshotAt
	if EmitDart(a) != EmitDart(b) {
		t.Fatal("dva běhy nad týmiž daty daly různý soubor")
	}
}

func TestLearnFailsLoudWithoutCreds(t *testing.T) {
	// I1 from the other side: no credentials must be an error, never an empty
	// overlay. An empty file would satisfy "never worse than today" while
	// quietly deleting everything already learned.
	ft := NewFinetune("https://finetune.example", "", "")
	if _, err := Learn(ft, 10); err == nil {
		t.Fatal("bez creds musí selhat, ne emitovat prázdno")
	}
}

func TestLearnRejectsGalleryWithoutEval(t *testing.T) {
	// A gallery older than the eval harness serves its SPA index for unknown
	// paths. Parsing that as "no rows" would emit an empty overlay.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		w.Write([]byte("<!doctype html><html><body><div id=app></div></body></html>"))
	}))
	defer srv.Close()
	_, err := Learn(NewFinetune(srv.URL, "id", "secret"), 10)
	if err == nil {
		t.Fatal("stará galerie musí být chyba")
	}
	if !strings.Contains(err.Error(), "nečekaná odpověď") &&
		!strings.Contains(err.Error(), "eval harness") {
		t.Fatalf("chyba nepomůže: %v", err)
	}
}

func TestEveryEmittedValueCarriesAReason(t *testing.T) {
	// I3, checked on the emitted text rather than the struct: a value whose
	// reason got lost in the template is still a value nobody can review.
	srv := fakeEvalGallery(t)
	defer srv.Close()
	l, err := Learn(NewFinetune(srv.URL, "id", "secret"), 10)
	if err != nil {
		t.Fatal(err)
	}
	for _, line := range strings.Split(EmitDart(l), "\n") {
		if strings.Contains(line, "LearnedValue(") ||
			strings.Contains(line, "LearnedChoice(") ||
			strings.Contains(line, "StyleFlag.") {
			if !strings.Contains(line, "reason: '") {
				t.Fatalf("hodnota bez proveniences: %s", line)
			}
			if strings.Contains(line, "reason: ''") {
				t.Fatalf("prázdný důvod: %s", line)
			}
		}
	}
}

func TestMinBelowOneIsRefused(t *testing.T) {
	// "Lower --min until something comes out" is the one way to make this
	// whole pipeline produce confident nonsense.
	env := &Env{RepoRoot: t.TempDir(), Finetune: NewFinetune("https://x", "id", "s")}
	if err := learnCLI(env, []string{"--min", "0"}); err == nil {
		t.Fatal("min=0 musí být odmítnuto")
	}
}

func TestDartString(t *testing.T) {
	if got := dartString("it's"); got != `'it\'s'` {
		t.Fatalf("got %s", got)
	}
	if got := dartString("a$b"); got != `'a\$b'` {
		t.Fatalf("got %s", got)
	}
}

func TestDartDoubleAlwaysHasAPoint(t *testing.T) {
	for in, want := range map[float64]string{1: "1.0", 1.2: "1.2", 0.75: "0.75", 0: "0.0"} {
		if got := dartDouble(in); got != want {
			t.Fatalf("dartDouble(%v) = %s, čekal %s", in, got, want)
		}
	}
}
