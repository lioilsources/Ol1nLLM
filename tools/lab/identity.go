package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// Identity: ArcFace similarity of each cell's largest face to the run's
// reference. The model lives in Python (insightface), so this shells out to
// tools/lab/arcface.py — same antelopev2 models, 640×640 detection and
// largest-face rule as tools/facebench and the Kadeřník bench, so the numbers
// sit on the same scale as theirs (checked on six bench cells: within 0.006).
//
// Scores are cached in identity.json, keyed by the image's size and mtime and
// by the reference itself: re-scoring a finished run costs nothing, a resumed
// run only scores its new cells.

// FaceScore is one cell's result. Identity is nil when no face was found.
type FaceScore struct {
	Identity *float64 `json:"identity"`
	Faces    int      `json:"faces"`
	Face     int      `json:"face,omitempty"`
	Stamp    string   `json:"stamp,omitempty"`
}

type identityCache struct {
	Ref   string               `json:"ref"`
	Cells map[string]FaceScore `json:"cells"`
}

const identityScale = "Tvář = ArcFace (antelopev2) největší tváře k referenci: 1.0 táž tvář, " +
	"~0.6 pořád táž osoba, pod 0.4 jiný člověk. ArcFace je naučený na fotkách: u anime modelů " +
	"vychází blízko nuly (NoobAI 0.06 i s InstantID) a nízké číslo tam neodliší jiného člověka " +
	"od nakreslené tváře — porovnávej hodnoty sweepu v rámci modelu, ne modely mezi sebou. " +
	"Pod ~40 px výšky tváře číslu nevěř."

// arcfaceTimeout bounds one scoring pass; CPU insightface does ~0.5 s a cell.
const arcfaceTimeout = 30 * time.Minute

func arcfacePython(env *Env) string {
	if p := os.Getenv("LAB_ARCFACE_PYTHON"); p != "" {
		return p
	}
	return filepath.Join(env.RepoRoot, "tools", "lab", ".venv", "bin", "python")
}

func fileStamp(path string) (string, bool) {
	st, err := os.Stat(path)
	if err != nil {
		return "", false
	}
	return fmt.Sprintf("%d-%d", st.Size(), st.ModTime().UnixNano()), true
}

// scoreIdentity scores images (cell id → image path) against the run's
// reference. It never fails the run: without a reference there is nothing to
// say, and a missing ArcFace setup or a crash comes back as the note.
func (r *Run) scoreIdentity(images map[string]string) (map[string]FaceScore, string) {
	if r.Spec == nil || r.Spec.RefFile == "" || len(images) == 0 {
		return nil, ""
	}
	if r.Spec.Dry {
		return nil, "Tvář se nanečisto nepočítá — obrázky jsou placeholdery."
	}
	refStamp, ok := fileStamp(r.Spec.RefFile)
	if !ok {
		return nil, "Tvář nespočítána: reference " + r.Spec.RefFile + " už na disku není."
	}
	python := arcfacePython(r.env)
	if _, err := os.Stat(python); err != nil {
		return nil, "Tvář (ArcFace) nespočítána: chybí " + python + " — nastavení: make lab-arcface."
	}

	cachePath := filepath.Join(r.Dir, "identity.json")
	refKey := r.Spec.RefFile + "@" + refStamp
	cache := identityCache{}
	if data, err := os.ReadFile(cachePath); err == nil {
		_ = json.Unmarshal(data, &cache)
	}
	if cache.Ref != refKey || cache.Cells == nil {
		cache = identityCache{Ref: refKey, Cells: map[string]FaceScore{}}
	}

	stamps := map[string]string{}
	todo := map[string]string{}
	for id, path := range images {
		st, ok := fileStamp(path)
		if !ok {
			continue
		}
		stamps[id] = st
		if cached, ok := cache.Cells[id]; !ok || cached.Stamp != st {
			todo[id] = path
		}
	}

	note := identityScale
	if len(todo) > 0 {
		scores, err := runArcface(r.env, r.Spec.RefFile, todo)
		if err != nil {
			note = "Tvář nespočítána: " + err.Error()
		} else {
			for id, s := range scores {
				s.Stamp = stamps[id]
				cache.Cells[id] = s
			}
			data, _ := json.MarshalIndent(cache, "", " ")
			_ = os.WriteFile(cachePath, data, 0o644)
		}
	}

	out := map[string]FaceScore{}
	for id, st := range stamps {
		if s, ok := cache.Cells[id]; ok && s.Stamp == st {
			out[id] = s
		}
	}
	return out, note
}

func runArcface(env *Env, ref string, images map[string]string) (map[string]FaceScore, error) {
	req, err := json.Marshal(map[string]any{"ref": ref, "images": images})
	if err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), arcfaceTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, arcfacePython(env),
		filepath.Join(env.RepoRoot, "tools", "lab", "arcface.py"))
	cmd.Stdin = bytes.NewReader(req)
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("arcface.py: %s", lastLine(stderr.String(), err.Error()))
	}
	var resp struct {
		Cells map[string]FaceScore `json:"cells"`
	}
	if err := json.Unmarshal(stdout.Bytes(), &resp); err != nil {
		return nil, fmt.Errorf("arcface.py vrátil nečitelný výstup: %w", err)
	}
	return resp.Cells, nil
}

// lastLine keeps the actual error of a Python traceback (its last line)
// instead of pasting the whole stack into the UI.
func lastLine(s, fallback string) string {
	lines := strings.Split(strings.TrimSpace(s), "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		if l := strings.TrimSpace(lines[i]); l != "" {
			return l
		}
	}
	return fallback
}
