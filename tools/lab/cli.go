package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// runCLI is the terminal path — same engine as the web UI, so a batch started
// here and one started in the browser produce identical directories.
func runCLI(env *Env, args []string) error {
	fs := flag.NewFlagSet("run", flag.ExitOnError)
	models := fs.String("models", "", "id modelů oddělené čárkou (výchozí: všechny nainstalované)")
	promptsFile := fs.String("prompts", "", "soubor s prompty, jeden na řádek")
	subject := fs.String("subject", "", "jeden prompt (alternativa k --prompts)")
	styles := fs.String("styles", "", "id stylů oddělená čárkou")
	stylesFile := fs.String("styles-file", "", "JSON s kandidáty stylů [{id,label,block}]")
	flows := fs.String("flows", "repose,img2img", "txt2img,img2img,repose")
	ref := fs.String("ref", "", "referenční obrázek")
	refPrompt := fs.String("ref-prompt", "", "vygenerovat referenci z promptu")
	pose := fs.String("pose", "none", "none|depth|template")
	poseID := fs.String("pose-id", "", "id šablony pózy (ol1..ol8)")
	seed := fs.Int("seed", 777, "seed pro celou matici")
	batch := fs.Int("batch", 1, "obrázků na buňku")
	negative := fs.String("negative", "", "negativní prompt")
	lora := fs.String("lora", "", "jméno LoRA souboru, jak ho hlásí ComfyUI")
	loraStrength := fs.Float64("lora-strength", 0, "síla LoRA (výchozí: appková 0.9)")
	editDenoise := fs.Float64("edit-denoise", 0, "přebít img2img denoise")
	sweep := fs.String("sweep", "", "cíl=v1|v2|v3")
	overrides := fs.String("override", "", "cíl=hodnota, oddělené čárkou")
	out := fs.String("out", "", "výstupní adresář (výchozí build/lab/<čas>)")
	dry := fs.Bool("dry", false, "nanečisto, bez ComfyUI")
	noBaseline := fs.Bool("no-baseline", false, "vynechat buňku bez stylu")
	if err := fs.Parse(args); err != nil {
		return err
	}
	var strength *float64
	fs.Visit(func(f *flag.Flag) {
		if f.Name == "lora-strength" {
			strength = loraStrength
		}
	})

	spec := &Spec{
		Models: splitCSV(*models), Styles: splitCSV(*styles), StylesFile: *stylesFile,
		Flows: splitCSV(*flows), NoBaseline: *noBaseline,
		PoseMode: *pose, PoseID: *poseID,
		Seed: *seed, Batch: *batch, Negative: *negative, EditDenoise: *editDenoise,
		Lora:  *lora,
		Sweep: *sweep, Overrides: splitCSV(*overrides), Dry: *dry,
		LoraStrength: strength,
	}
	switch {
	case *promptsFile != "":
		data, err := os.ReadFile(*promptsFile)
		if err != nil {
			return err
		}
		for _, l := range strings.Split(string(data), "\n") {
			if l = strings.TrimSpace(l); l != "" {
				spec.Prompts = append(spec.Prompts, l)
			}
		}
	case *subject != "":
		spec.Prompts = []string{*subject}
	default:
		return fmt.Errorf("chybí --prompts nebo --subject")
	}
	spec.Title = spec.Prompts[0]

	dir := *out
	if dir == "" {
		dir = filepath.Join(env.RepoRoot, "build", "lab", time.Now().Format("20060102-150405"))
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}

	if *ref == "" && *refPrompt != "" {
		if spec.Dry {
			return fmt.Errorf("--ref-prompt potřebuje ComfyUI; nanečisto použij --ref")
		}
		fmt.Println("▸ generuji referenci…")
		path, err := generateReference(env, dir, *refPrompt, *seed)
		if err != nil {
			return err
		}
		*ref = path
		fmt.Println("  →", path)
	}
	if *ref != "" {
		abs, err := filepath.Abs(*ref)
		if err != nil {
			return err
		}
		spec.RefFile = abs
		if !spec.Dry {
			name, err := env.Comfy.Upload(abs, "lab_ref_"+filepath.Base(abs))
			if err != nil {
				return err
			}
			spec.RefName = name
		} else {
			spec.RefName = filepath.Base(abs)
		}
	}
	if spec.PoseMode == "template" {
		if spec.PoseID == "" {
			return fmt.Errorf("--pose template vyžaduje --pose-id (ol1..ol8)")
		}
		if !spec.Dry {
			asset := filepath.Join(env.RepoRoot, "assets", "poses", spec.PoseID+".png")
			name, err := env.Comfy.Upload(asset, "ol1n_pose_"+spec.PoseID+".png")
			if err != nil {
				return err
			}
			spec.PoseName = name
		} else {
			spec.PoseName = spec.PoseID + ".png"
		}
	}

	run := NewRun(env, dir, spec)
	// Progress to stdout: the CLI has no SSE, so mirror the same state changes.
	ch, stop := run.Subscribe()
	defer stop()
	done := make(chan struct{})
	go func() {
		last := ""
		for st := range ch {
			line := fmt.Sprintf("%s %d/%d ok=%d chyb=%d %s",
				st.Status, st.Done+st.Failed, st.Total, st.Done, st.Failed, st.Message)
			if line != last {
				fmt.Println(line)
				last = line
			}
		}
		close(done)
	}()
	if err := run.Dump(); err != nil {
		return err
	}
	run.Generate()
	fmt.Println("▸ hotovo:", dir)
	return nil
}

// generateReference reuses the dump for a single txt2img cell, so the reference
// is produced by the same code path as everything else.
func generateReference(env *Env, dir, prompt string, seed int) (string, error) {
	refDir := filepath.Join(dir, "_ref")
	spec := &Spec{
		Prompts: []string{prompt}, Flows: []string{"txt2img"},
		Models: []string{"juggernaut-xl"}, Seed: seed, Batch: 1,
		Latent: "832x1216", Title: "reference",
	}
	run := NewRun(env, refDir, spec)
	if err := os.MkdirAll(refDir, 0o755); err != nil {
		return "", err
	}
	if err := run.Dump(); err != nil {
		return "", err
	}
	run.Generate()
	man := run.Manifest()
	if man == nil || len(man.Cells) == 0 {
		return "", fmt.Errorf("reference se nevygenerovala")
	}
	path := run.imgPath(man.Cells[0].ID)
	if _, err := os.Stat(path); err != nil {
		return "", fmt.Errorf("reference se nevygenerovala: %w", err)
	}
	final := filepath.Join(dir, "reference.png")
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return final, os.WriteFile(final, data, 0o644)
}

func scoreCLI(env *Env, args []string) error {
	if len(args) < 1 {
		return fmt.Errorf("lab score <adresář běhu>")
	}
	dir := args[0]
	man, err := ReadManifest(filepath.Join(dir, "wf", "manifest.json"))
	if err != nil {
		return err
	}
	run := &Run{Dir: dir, env: env, man: man}
	run.computeMetrics()
	data, err := os.ReadFile(filepath.Join(dir, "metrics.json"))
	if err != nil {
		return err
	}
	var m Metrics
	if err := json.Unmarshal(data, &m); err != nil {
		return err
	}
	fmt.Printf("%-42s %8s %5s\n", "skupina (flow|model|prompt)", "rozptyl", "n")
	for k, g := range m.Groups {
		fmt.Printf("%-42s %8.3f %5d\n", k, g.Spread, g.N)
	}
	fmt.Println("\n" + m.Note)
	return nil
}

func splitCSV(s string) []string {
	var out []string
	for _, p := range strings.Split(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}
