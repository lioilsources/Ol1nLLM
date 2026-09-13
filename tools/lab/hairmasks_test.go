package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestEstimateCountsHairCellsAsModelsTimesHairstyles(t *testing.T) {
	models := []ManifestModel{{ID: "flux-fill", Preset: map[string]any{}}, {ID: "juggernaut-xl", Preset: map[string]any{}}}
	s := Spec{
		Models: []string{"flux-fill", "juggernaut-xl"}, Prompts: []string{"x"},
		Flows: []string{"hair"}, HairFile: filepath.Join("candidates", "hairstyles.json"),
		HairMasks: "masks", RefName: "ref.png", Styles: []string{"ukiyoe"},
	}
	all, err := countHairCandidates(s.HairFile, nil)
	if err != nil || all < 50 {
		t.Fatalf("kandidáti: %d, %v", all, err)
	}
	e := s.Estimate(&Manifest{Models: models}, nil)
	if e.Cells != 2*all {
		t.Fatalf("cells = %d, want %d (styles must not multiply hair cells)", e.Cells, 2*all)
	}
	s.Hairstyles = []string{"pixie", "wolf-cut", "nope"}
	if e := s.Estimate(&Manifest{Models: models}, nil); e.Cells != 4 {
		t.Fatalf("picked cells = %d, want 4", e.Cells)
	}
	noMasks := s
	noMasks.HairMasks = ""
	if e := noMasks.Estimate(&Manifest{Models: models}, nil); len(e.Blockers) == 0 {
		t.Fatal("hair bez --hair-masks musí blokovat")
	}
	noRef := s
	noRef.RefName = ""
	if e := noRef.Estimate(&Manifest{Models: models}, nil); len(e.Blockers) == 0 {
		t.Fatal("hair bez reference musí blokovat")
	}
}

func TestDumpEnvCarriesHairInputsAbsolute(t *testing.T) {
	s := &Spec{Prompts: []string{"x"}, Flows: []string{"hair"},
		HairFile: "candidates/hairstyles.json", HairMasks: "build/lab/hairmasks/r", Hairstyles: []string{"pixie", "bob"}}
	env, err := s.DumpEnv(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]string{}
	for _, kv := range env {
		k, v, _ := strings.Cut(kv, "=")
		got[k] = v
	}
	for _, k := range []string{"HAIR_FILE", "HAIR_MASKS_DIR"} {
		if !filepath.IsAbs(got[k]) {
			t.Errorf("%s není absolutní: %q", k, got[k])
		}
	}
	if got["HAIRSTYLES"] != "pixie,bob" || got["FLOWS"] != "hair" {
		t.Errorf("HAIRSTYLES=%q FLOWS=%q", got["HAIRSTYLES"], got["FLOWS"])
	}
}

func TestHairAnalysisOutputsMatchByPrefix(t *testing.T) {
	found := pickHairOutputs([]Image{
		{Filename: "tsumiki_features_mask_00002_.png"},
		{Filename: "tsumiki_hair_mask_00002_.png"},
		{Filename: "tsumiki_face_mask_00002_.png"},
		{Filename: "something_else.png"},
	})
	if len(found) != 3 || found["tsumiki_hair_mask"].Filename != "tsumiki_hair_mask_00002_.png" {
		t.Fatalf("found = %+v", found)
	}
	if _, ok := found["tsumiki_hat_mask"]; ok {
		t.Fatal("hat mask nebyla ve výstupu")
	}
}

func TestAnalysisGraphGetsTheUploadedImage(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("..", "..", "assets", "comfyui", "hair_analyse.api.json"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), "__IMAGE__") {
		t.Fatal("šablona nemá __IMAGE__")
	}
	wf := map[string]any{"1": map[string]any{"class_type": "LoadImage", "inputs": map[string]any{"image": "__IMAGE__"}}}
	substituteImage(wf, "lab_hair_ref.png")
	if wf["1"].(map[string]any)["inputs"].(map[string]any)["image"] != "lab_hair_ref.png" {
		t.Fatal("__IMAGE__ nenahrazen")
	}
}
