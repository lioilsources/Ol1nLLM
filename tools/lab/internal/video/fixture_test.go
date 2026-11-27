package video

import (
	"bytes"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"testing"
)

// fakeCell describes one cell of a fake run.
type fakeCell struct {
	model, style, flow string
	prompt             int    // promptIndex
	scene              string // promptBody; "" = typed prompt
	character          string
	seed               int
	missing, empty     bool   // no picture / a 0-byte file
	dependsOn          string // the cell this one was drawn over (restyle)
	id                 string // explicit cell id (default: built from the axes)
	reaction           *float64
}

// fakeRun is what writeRun puts on disk: a manifest, state, spec and small
// PNGs. Real runs carry real prompts and pictures and stay out of the repo.
type fakeRun struct {
	id      string
	status  string
	dry     bool
	columns []string // manifest.prompts; derived from cells when nil
	styles  []StyleMeta
	cells   []fakeCell
	ref     string // reference picture, relative to the lab directory
}

func writeRun(t *testing.T, labDir string, r fakeRun) string {
	t.Helper()
	dir := filepath.Join(labDir, r.id)
	for _, d := range []string{"wf", "img", "thumb"} {
		if err := os.MkdirAll(filepath.Join(dir, d), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	type mcell map[string]any
	var cells []mcell
	reactions := map[string]any{}
	columns := r.columns
	models := []map[string]string{}
	seenModel := map[string]bool{}
	maxPrompt := -1
	for _, c := range r.cells {
		if c.prompt > maxPrompt {
			maxPrompt = c.prompt
		}
	}
	if columns == nil {
		columns = make([]string, maxPrompt+1)
		for _, c := range r.cells {
			label := c.scene
			if label == "" {
				label = fmt.Sprintf("typed prompt %d", c.prompt)
			}
			if c.character != "" {
				label += " · " + c.character
			}
			columns[c.prompt] = label
		}
	}
	for _, c := range r.cells {
		flow := c.flow
		if flow == "" {
			flow = "txt2img"
		}
		style := c.style
		if style == "" {
			style = Baseline
		}
		id := fmt.Sprintf("%s__%s__%s__p%02d", flow, c.model, style, c.prompt)
		if c.character != "" {
			id += "__" + c.character
		}
		if c.id != "" {
			id = c.id
		}
		if c.reaction != nil {
			reactions[id] = map[string]any{"reaction": *c.reaction}
		}
		cell := mcell{
			"id": id, "flow": flow, "model": c.model, "modelLabel": "M " + c.model,
			"style": style, "promptIndex": c.prompt, "promptBody": c.scene,
			"params": map[string]any{"seed": c.seed, "refName": "x.png"},
		}
		if c.dependsOn != "" {
			cell["dependsOn"] = c.dependsOn
		}
		cells = append(cells, cell)
		if !seenModel[c.model] {
			seenModel[c.model] = true
			models = append(models, map[string]string{"id": c.model, "label": "M " + c.model})
		}
		switch {
		case c.missing:
		case c.empty:
			if err := os.WriteFile(filepath.Join(dir, "img", id+".png"), nil, 0o644); err != nil {
				t.Fatal(err)
			}
		default:
			if err := os.WriteFile(filepath.Join(dir, "img", id+".png"), tinyPNG(t), 0o644); err != nil {
				t.Fatal(err)
			}
		}
	}
	var styles []map[string]any
	for _, s := range r.styles {
		styles = append(styles, map[string]any{"id": s.ID, "label": s.Label, "labelWithYear": s.Label + " (y)",
			"kind": s.Kind, "year": s.Year})
	}
	man := map[string]any{"cells": cells, "models": models, "styles": styles, "prompts": columns}
	writeJSON(t, filepath.Join(dir, "wf", "manifest.json"), man)
	status := r.status
	if status == "" {
		status = "done"
	}
	writeJSON(t, filepath.Join(dir, "state.json"), map[string]any{"status": status, "dry": r.dry, "title": r.id})
	refFile := ""
	if r.ref != "" {
		refFile = filepath.Join(labDir, r.ref)
		if err := os.MkdirAll(filepath.Dir(refFile), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(refFile, tinyPNG(t), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	writeJSON(t, filepath.Join(dir, "spec.json"), map[string]any{"negative": "", "dry": r.dry, "refFile": refFile})
	if len(reactions) > 0 {
		writeJSON(t, filepath.Join(dir, "metrics.json"), map[string]any{"cells": reactions})
	}
	return dir
}

func writeJSON(t *testing.T, path string, v any) {
	t.Helper()
	data, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
}

func tinyPNG(t *testing.T) []byte {
	img := image.NewRGBA(image.Rect(0, 0, 4, 6))
	for i := range img.Pix {
		img.Pix[i] = 128
	}
	img.Set(0, 0, color.RGBA{255, 0, 0, 255})
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func intp(v int) *int { return &v }

// registry is a small picker-ordered style list: two cultures, an artist, a medium.
var registry = []StyleMeta{
	{ID: "cave", Label: "Cave", Kind: "culture", Year: intp(-17000)},
	{ID: "baroque", Label: "Baroque", Kind: "culture", Year: intp(1600)},
	{ID: "vermeer", Label: "Vermeer", Kind: "artist", Year: intp(1632)},
	{ID: "ink", Label: "Ink", Kind: "medium"},
}

func mustLoad(t *testing.T, labDir string) *Collection {
	t.Helper()
	col, err := Load(labDir)
	if err != nil {
		t.Fatal(err)
	}
	if len(col.Errors) > 0 {
		t.Fatalf("chyby indexu: %v", col.Errors)
	}
	return col
}

func mustPool(t *testing.T, col *Collection, identity string, ids ...string) *Pool {
	t.Helper()
	var runs []*Run
	for _, id := range ids {
		r := col.Run(id)
		if r == nil {
			t.Fatalf("běh %s v kolekci není", id)
		}
		runs = append(runs, r)
	}
	p, err := NewPool(runs, identity, "first")
	if err != nil {
		t.Fatal(err)
	}
	return p
}
