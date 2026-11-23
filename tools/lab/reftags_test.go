package main

import (
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestComposeRefTagsOrdersAndDropsPhotoTags(t *testing.T) {
	general := map[string]float64{
		"1girl": 0.98, "solo": 0.95, "realistic": 0.9, "long hair": 0.8,
		"blurry background": 0.6, "smile": 0.5, "black hair": 0.5,
	}
	character := map[string]float64{"hatsune miku": 0.8}
	tags, dropped := composeRefTags(general, character)
	// Character first; general by confidence, ties by name.
	want := []string{"hatsune miku", "1girl", "solo", "long hair", "black hair", "smile"}
	if !reflect.DeepEqual(tags, want) {
		t.Fatalf("tags = %v, want %v", tags, want)
	}
	if !reflect.DeepEqual(dropped, []string{"realistic", "blurry background"}) {
		t.Fatalf("dropped = %v", dropped)
	}
}

func TestWithRefTags(t *testing.T) {
	if got := withRefTags(nil, "1girl, solo"); !reflect.DeepEqual(got, []string{"1girl, solo"}) {
		t.Fatalf("empty box: %v", got)
	}
	got := withRefTags([]string{"masterpiece", "low angle"}, "1girl")
	if !reflect.DeepEqual(got, []string{"masterpiece, 1girl", "low angle, 1girl"}) {
		t.Fatalf("prefixes: %v", got)
	}
	if got := withRefTags([]string{"a"}, ""); !reflect.DeepEqual(got, []string{"a"}) {
		t.Fatalf("no tags: %v", got)
	}
}

func TestEstimateRefTagsStandInForPrompts(t *testing.T) {
	ckpt := "x.safetensors"
	man := &Manifest{Models: []ManifestModel{
		{ID: "pony", Label: "Pony", PromptFamily: FamilyDanbooru, CkptName: &ckpt,
			SupportsPose: true, Preset: map[string]any{}},
	}}
	s := Spec{Models: []string{"pony"}, Flows: []string{"img2img"}, NoStyles: true,
		RefTags: true, RefFile: "/tmp/ref.png", RefName: "ref.png"}
	if e := s.Estimate(man, nil); len(e.Blockers) != 0 || e.Cells != 1 {
		t.Fatalf("tagy místo promptu: cells %d, blockers %v", e.Cells, e.Blockers)
	}
	noRef := s
	noRef.RefFile, noRef.RefName = "", ""
	e := noRef.Estimate(man, nil)
	if !strings.Contains(strings.Join(e.Blockers, " "), "tagy z předlohy") {
		t.Fatalf("bez reference chce blocker, má %v", e.Blockers)
	}
	off := s
	off.RefTags = false
	if e := off.Estimate(man, nil); len(e.Blockers) == 0 {
		t.Fatal("bez tagů a bez promptu má blokovat")
	}
}

// The tags reach prompts.txt and SUBJECT, but never spec.Prompts — spec.json
// would otherwise carry them and a replay would append them twice.
func TestDumpEnvSendsRefTags(t *testing.T) {
	dir := t.TempDir()
	s := Spec{Prompts: []string{"masterpiece"}, Flows: []string{"img2img"}, RefTags: true}
	s.refTagText = "1girl, solo"
	env, err := s.DumpEnv(dir)
	if err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(filepath.Join(dir, "prompts.txt"))
	if string(data) != "masterpiece, 1girl, solo\n" {
		t.Fatalf("prompts.txt = %q", data)
	}
	if !contains(env, "SUBJECT=masterpiece, 1girl, solo") {
		t.Fatal("SUBJECT bez tagů")
	}
	if !reflect.DeepEqual(s.Prompts, []string{"masterpiece"}) {
		t.Fatalf("spec.Prompts změněné: %v", s.Prompts)
	}
}

func contains(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

// The preview endpoint reads only uploaded references; a path from the
// browser outside build/lab/_refs is refused before the tagger runs.
func TestRefTagsEndpointReadsOnlyUploads(t *testing.T) {
	root := t.TempDir()
	s := &Server{env: &Env{RepoRoot: root}}
	for _, path := range []string{
		"/etc/hosts",
		filepath.Join(root, "build", "lab", "_refs", "..", "secret.png"),
	} {
		rec := httptest.NewRecorder()
		body := strings.NewReader(`{"refFile":"` + path + `"}`)
		s.handleRefTags(rec, httptest.NewRequest("POST", "/api/ref-tags", body))
		if rec.Code != 400 {
			t.Fatalf("%s: HTTP %d, want 400", path, rec.Code)
		}
	}
	// An upload path passes the guard and fails on the missing file instead.
	rec := httptest.NewRecorder()
	body := strings.NewReader(`{"refFile":"` + filepath.Join(root, "build", "lab", "_refs", "ref-1.png") + `"}`)
	s.handleRefTags(rec, httptest.NewRequest("POST", "/api/ref-tags", body))
	if rec.Code != 502 || !strings.Contains(rec.Body.String(), "na disku není") {
		t.Fatalf("upload path: HTTP %d %s", rec.Code, rec.Body.String())
	}
}
