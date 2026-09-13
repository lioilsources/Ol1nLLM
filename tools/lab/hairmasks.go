package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// hairAnalysePrefixes are the SaveImage prefixes of hair_analyse.api.json and
// the file names the masks are stored under.
var hairAnalysePrefixes = map[string]string{
	"tsumiki_hair_mask":     "hair",
	"tsumiki_face_mask":     "face",
	"tsumiki_hat_mask":      "hat",
	"tsumiki_features_mask": "features",
}

// hairmasksCLI prepares a reference for the `hair` flow: face parsing on the
// server, then the app's own mask geometry (tools/lab/hairmask.dart) for every
// shape the candidates use, then the masks go up to ComfyUI under stable
// names. The dump reads masks.json and never touches the network.
//
//	lab hairmasks --ref foto.png [--hair-file candidates/hairstyles.json] [--out DIR]
func hairmasksCLI(env *Env, args []string) error {
	fs := flag.NewFlagSet("hairmasks", flag.ExitOnError)
	ref := fs.String("ref", "", "portrét")
	hairFile := fs.String("hair-file", filepath.Join("tools", "lab", "candidates", "hairstyles.json"), "kandidáti účesů")
	out := fs.String("out", "", "výstup (výchozí build/lab/hairmasks/<jméno reference>)")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *ref == "" {
		return fmt.Errorf("chybí --ref")
	}
	if !env.Comfy.HasCreds() {
		return fmt.Errorf("hairmasks potřebuje ComfyUI (CF Access creds)")
	}
	refAbs, err := filepath.Abs(*ref)
	if err != nil {
		return err
	}
	stem := strings.TrimSuffix(filepath.Base(refAbs), filepath.Ext(refAbs))
	dir := *out
	if dir == "" {
		dir = filepath.Join(env.RepoRoot, "build", "lab", "hairmasks", stem)
	}
	if dir, err = filepath.Abs(dir); err != nil {
		return err
	}
	analysis := filepath.Join(dir, "analysis")
	if err := os.MkdirAll(analysis, 0o755); err != nil {
		return err
	}

	fmt.Println("▸ analýza (face parsing) na serveru…")
	refName, err := env.Comfy.Upload(refAbs, "lab_hair_"+filepath.Base(refAbs))
	if err != nil {
		return err
	}
	if err := runHairAnalysis(env.Comfy, filepath.Join(env.RepoRoot, "assets", "comfyui", "hair_analyse.api.json"), refName, analysis); err != nil {
		return err
	}

	fmt.Println("▸ masky (lib/models/hair_mask.dart)…")
	hairAbs, err := filepath.Abs(*hairFile)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, "flutter", "test", "tools/lab/hairmask.dart")
	cmd.Dir = env.RepoRoot
	cmd.Env = append(os.Environ(),
		"ANALYSIS_DIR="+analysis, "PHOTO="+refAbs, "HAIR_FILE="+hairAbs, "OUT_DIR="+dir)
	if log, err := cmd.CombinedOutput(); err != nil {
		_ = os.WriteFile(filepath.Join(dir, "hairmask.log"), log, 0o644)
		return fmt.Errorf("hairmask.dart: %v (viz %s)", err, filepath.Join(dir, "hairmask.log"))
	}

	manPath := filepath.Join(dir, "masks.json")
	man, err := readHairMasks(manPath)
	if err != nil {
		return err
	}
	for key, shape := range man.Shapes {
		if shape.File == "" {
			fmt.Printf("  ✗ %-28s %s\n", key, shape.Error)
			continue
		}
		name, err := env.Comfy.Upload(filepath.Join(dir, shape.File), fmt.Sprintf("lab_hairmask_%s_%s.png", stem, key))
		if err != nil {
			return err
		}
		shape.Uploaded = name
		man.Shapes[key] = shape
		fmt.Printf("  ✓ %-28s plocha %.0f %%\n", key, shape.Area*100)
	}
	man.RefName = refName
	data, _ := json.MarshalIndent(man, "", " ")
	if err := os.WriteFile(manPath, data, 0o644); err != nil {
		return err
	}
	fmt.Printf("▸ hotovo: %s (barva vlasů: %s)\n  lab run --flows hair --ref %s --hair-masks %s …\n",
		dir, defaultStr(man.Colour, "—"), *ref, dir)
	return nil
}

type hairShapeMask struct {
	File     string  `json:"file,omitempty"`
	Area     float64 `json:"area,omitempty"`
	Error    string  `json:"error,omitempty"`
	Uploaded string  `json:"uploaded,omitempty"`
}

type hairMasks struct {
	Colour  string                   `json:"colour,omitempty"`
	RefName string                   `json:"refName,omitempty"`
	Shapes  map[string]hairShapeMask `json:"shapes"`
}

func readHairMasks(path string) (*hairMasks, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var m hairMasks
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return &m, nil
}

// runHairAnalysis submits the analysis graph for an uploaded image and saves
// its four masks into dir, matched by filename prefix (history keys outputs by
// node id, with no order).
func runHairAnalysis(c *Comfy, graphPath, imageName, dir string) error {
	raw, err := os.ReadFile(graphPath)
	if err != nil {
		return err
	}
	var wf map[string]any
	if err := json.Unmarshal(raw, &wf); err != nil {
		return err
	}
	substituteImage(wf, imageName)
	id, err := c.Submit(wf, "lab-hairmasks")
	if err != nil {
		return err
	}
	deadline := time.Now().Add(5 * time.Minute)
	var hist *HistoryEntry
	for time.Now().Before(deadline) {
		time.Sleep(2 * time.Second)
		h, err := c.History(id)
		if err != nil || h == nil {
			continue
		}
		if h.Status.StatusStr == "error" {
			return fmt.Errorf("analýza selhala na serveru (prompt %s)", id)
		}
		if len(h.Outputs) > 0 {
			hist = h
			break
		}
	}
	if hist == nil {
		return fmt.Errorf("analýza nedoběhla do 5 min (prompt %s)", id)
	}
	found := pickHairOutputs(hist.SavedImages())
	for prefix, name := range hairAnalysePrefixes {
		im, ok := found[prefix]
		if !ok {
			return fmt.Errorf("výsledek analýzy nemá %s", prefix)
		}
		data, err := c.Download(im)
		if err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(dir, name+".png"), data, 0o644); err != nil {
			return err
		}
	}
	return nil
}

func substituteImage(wf map[string]any, imageName string) {
	for _, n := range wf {
		node, ok := n.(map[string]any)
		if !ok {
			continue
		}
		inputs, ok := node["inputs"].(map[string]any)
		if !ok {
			continue
		}
		for k, v := range inputs {
			if v == "__IMAGE__" {
				inputs[k] = imageName
			}
		}
	}
}

// pickHairOutputs returns the first saved image per analysis prefix; the
// longest matching prefix wins.
func pickHairOutputs(images []Image) map[string]Image {
	out := map[string]Image{}
	for _, im := range images {
		best := ""
		for prefix := range hairAnalysePrefixes {
			if strings.HasPrefix(im.Filename, prefix+"_") && len(prefix) > len(best) {
				best = prefix
			}
		}
		if best != "" {
			if _, seen := out[best]; !seen {
				out[best] = im
			}
		}
	}
	return out
}
