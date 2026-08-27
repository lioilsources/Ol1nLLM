package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// MaxCells is the hard ceiling on one run. A sweep multiplies four axes, and
// the arithmetic that turns "all models × all styles" into four hours is easy
// to do by accident — see docs/style-matrix.md, where 600 cells took 3h40m.
const MaxCells = 400

// ConfirmCells is where the UI stops and asks rather than just starting.
const ConfirmCells = 120

// Spec is one experiment, exactly as the UI submits it and as it is replayed
// from spec.json.
type Spec struct {
	Title      string   `json:"title"`
	Models     []string `json:"models"`
	Prompts    []string `json:"prompts"`
	Styles     []string `json:"styles"`
	StylesFile string   `json:"stylesFile"`
	Flows      []string `json:"flows"`
	NoBaseline bool     `json:"noBaseline"`

	RefName string `json:"refName"` // server-side filename (after upload)
	RefFile string `json:"refFile"` // local path, for the latent bucket

	PoseMode    string `json:"poseMode"` // none | depth | template
	PoseID      string `json:"poseId"`
	PoseName    string `json:"poseName"` // uploaded skeleton filename
	SourceDepth string `json:"sourceDepth"`

	// FaceIdentity carries the reference's face into the render on top of the
	// pose: none | instantid | faceid | both (FLUX has one mechanism, so
	// anything but none means PuLID there). FaceDetail adds a cropped second
	// pass over the detected face; it needs an identity to be worth anything.
	FaceIdentity string `json:"faceIdentity"`
	FaceDetail   bool   `json:"faceDetail"`

	Lora string `json:"lora"`
	// Pointer, not a plain float: 0 is a legal strength (the LoRA loaded but
	// silent), so "not chosen" has to be distinguishable from "chosen zero".
	LoraStrength *float64 `json:"loraStrength"`

	Seed        int     `json:"seed"`
	Batch       int     `json:"batch"`
	Negative    string  `json:"negative"`
	Latent      string  `json:"latent"`
	EditDenoise float64 `json:"editDenoise"`

	Overrides  []string `json:"overrides"`
	Sweep      string   `json:"sweep"`
	SweepLabel string   `json:"sweepLabel"`

	Dry bool `json:"dry"`
}

type Estimate struct {
	Cells      int      `json:"cells"`
	Variants   int      `json:"variants"`
	EstMinutes float64  `json:"estMinutes"`
	Warnings   []string `json:"warnings"`
	Blockers   []string `json:"blockers"`
}

// Estimate is deliberately arithmetic, not a dump: it has to answer on every
// keystroke. The exact count arrives later, from the manifest, before any GPU
// time is spent — that two-stage guard is why a sweep cannot surprise you.
func (s *Spec) Estimate(man *Manifest, secondsPerCell map[string]float64) Estimate {
	models := man.Models
	// Non-nil slices on purpose: encoding/json turns a nil slice into null,
	// and every consumer would then need to guard before reading .length.
	e := Estimate{Variants: 1, Warnings: []string{}, Blockers: []string{}}
	if s.Sweep != "" {
		if _, values, err := splitSweep(s.Sweep); err == nil {
			e.Variants = len(values)
		}
	}
	styleCount := len(s.Styles)
	if styleCount == 0 {
		styleCount = 1 // baseline only
	} else if !s.NoBaseline {
		styleCount++ // baseline alongside the styles
	}
	prompts := len(s.Prompts)
	if prompts == 0 {
		prompts = 1
	}
	flows := len(s.Flows)
	if flows == 0 {
		flows = 1
	}

	picked := map[string]bool{}
	for _, id := range s.Models {
		picked[id] = true
	}
	var est float64
	for _, m := range models {
		if len(picked) > 0 && !picked[m.ID] {
			continue
		}
		per := secondsPerCell[m.ID]
		if per == 0 {
			per = 30 // conservative default; refined from real timings
			if steps, ok := m.Preset["steps"].(float64); ok && steps <= 8 {
				per = 12
			}
		}
		cells := prompts * styleCount * flows * e.Variants
		e.Cells += cells
		est += float64(cells) * per
	}
	e.EstMinutes = est / 60

	if len(s.Models) == 0 {
		e.Blockers = append(e.Blockers, "vyber aspoň jeden model")
	}
	// The dump loops over prompts, so none means zero cells — while the count
	// above pretends one. A run that says "0 ok, 0 chyb" after a GPU-less
	// minute is the wrong way to find out the textarea was empty.
	if len(s.Prompts) == 0 {
		e.Blockers = append(e.Blockers, "napiš aspoň jeden prompt")
	}
	if len(s.Flows) == 0 {
		e.Blockers = append(e.Blockers, "vyber aspoň jednu flow")
	}
	if s.needsRef() && s.RefName == "" {
		e.Blockers = append(e.Blockers,
			"tahle kombinace potřebuje referenční obrázek (img2img / zachovej pózu / depth)")
	}
	if s.PoseMode == "template" && s.PoseID == "" {
		e.Blockers = append(e.Blockers, "vyber šablonu pózy")
	}
	if e.Cells > MaxCells {
		e.Blockers = append(e.Blockers,
			fmt.Sprintf("%d buněk je nad stropem %d — zúž výběr nebo rozděl na víc běhů",
				e.Cells, MaxCells))
	} else if e.Cells > ConfirmCells {
		e.Warnings = append(e.Warnings,
			fmt.Sprintf("%d buněk, odhadem %.0f min", e.Cells, e.EstMinutes))
	}
	// Width/height overrides fight the repose bucket: _prepare computes the
	// latent from the reference, and a post-hoc width silently re-crops the
	// depth hint.
	if s.PoseMode == "depth" && (s.Latent != "" || overridesTouchLatent(s.Overrides, s.Sweep)) {
		e.Warnings = append(e.Warnings,
			"při depth póze nech latent na automatu — ruční rozměr ořízne hloubkovou mapu")
	}
	for _, m := range models {
		if !picked[m.ID] {
			continue
		}
		if m.CkptName == nil && (s.Sweep != "" || len(s.Overrides) > 0) {
			e.Warnings = append(e.Warnings, fmt.Sprintf(
				"%s jede na vlastní šabloně (bez KSampleru) — sweep na něj nesedne a buňky se přeskočí",
				m.Label))
		}
	}
	e.faceIdentity(s, man, picked)
	e.loraFit(s, man, picked)
	return e
}

// faceIdentity says up front where the face toggle will quietly do nothing.
// It reads the reference through the depth chain, so without a flow that
// injects one there is no face to read and the run looks identical to a plain
// repose — an expensive way to discover a checkbox was ignored.
func (e *Estimate) faceIdentity(s *Spec, man *Manifest, picked map[string]bool) {
	on := s.FaceIdentity != "" && s.FaceIdentity != "none"
	if !on && !s.FaceDetail {
		return
	}
	if !s.hasDepthSource(man, picked) {
		e.Warnings = append(e.Warnings,
			"tvář se čte z předlohy přes hloubkovou mapu — tahle kombinace žádnou "+
				"nevyrábí, takže se přepínač neprojeví")
	}
	if s.FaceDetail && !on {
		e.Warnings = append(e.Warnings,
			"dotažení tváře běží jen se zapnutou identitou — samo o sobě by "+
				"tvář jen přelosovalo")
	}
	if s.FaceDetail && s.Batch > 1 {
		e.Warnings = append(e.Warnings, fmt.Sprintf(
			"dotažení tváře nad batch %d není ověřené — první ostrý běh zkontroluj, "+
				"jestli projde celá dávka", s.Batch))
	}
	if !on {
		return
	}
	var flux []string
	for _, m := range man.Models {
		if picked[m.ID] && m.CkptName == nil {
			flux = append(flux, m.Label)
		}
	}
	if len(flux) > 0 {
		e.Warnings = append(e.Warnings, fmt.Sprintf(
			"%s jede PuLID — InstantID ani FaceID na FLUX nejsou; manifest zapíše "+
				"metodu, která opravdu běžela", strings.Join(flux, ", ")))
	}
}

// loraFit says up front what the dump would otherwise say cell by cell: a LoRA
// of a different architecture is not applied, it is skipped. Finding that out
// from an empty table after the GPU time is the expensive way to learn it.
func (e *Estimate) loraFit(s *Spec, man *Manifest, picked map[string]bool) {
	if s.Lora == "" {
		return
	}
	var lora *ManifestLora
	for i := range man.Loras {
		if man.Loras[i].Name == s.Lora {
			lora = &man.Loras[i]
		}
	}
	if lora == nil {
		return // a file the registry dump has not seen; the dump will judge it
	}
	var bad, weak []string
	for _, m := range man.Models {
		if !picked[m.ID] {
			continue
		}
		switch lora.Fit[m.ID] {
		case "incompatible":
			bad = append(bad, m.Label)
		case "weak":
			weak = append(weak, m.Label)
		}
	}
	if len(bad) > 0 {
		msg := fmt.Sprintf("%s (%s) nesedne na %s — ty buňky se přeskočí",
			s.Lora, lora.FamilyLabel, strings.Join(bad, ", "))
		if len(bad) == len(picked) {
			e.Blockers = append(e.Blockers, msg)
		} else {
			e.Warnings = append(e.Warnings, msg)
		}
	}
	if len(weak) > 0 {
		e.Warnings = append(e.Warnings, fmt.Sprintf(
			"%s je %s — na %s se načte, ale táhne slaběji",
			s.Lora, lora.FamilyLabel, strings.Join(weak, ", ")))
	}
}

// hasDepthSource says whether any picked flow/model would put a `__depth_src__`
// in the graph — the node the face is read from, so it is exactly the gate on
// identity. Three ways in, and the third is easy to forget: img2img on an SDXL
// model carries the source's own structure over by itself (auto-depth), so the
// face toggle works there without anyone asking for a pose.
func (s *Spec) hasDepthSource(man *Manifest, picked map[string]bool) bool {
	if s.PoseMode == "template" {
		return false // a skeleton is a pose, not a photo — no face in it
	}
	var img2img bool
	for _, f := range s.Flows {
		switch f {
		case "repose":
			return true // the reference *is* the depth hint
		case "img2img":
			img2img = true
		}
	}
	if s.PoseMode == "depth" {
		return true // explicit, and legal on img2img and txt2img alike
	}
	if !img2img {
		return false
	}
	for _, m := range man.Models {
		if picked[m.ID] && m.SupportsPose && m.CkptName != nil {
			return true
		}
	}
	return false
}

func (s *Spec) needsRef() bool {
	for _, f := range s.Flows {
		if f == "img2img" || f == "repose" {
			return true
		}
	}
	return s.PoseMode == "depth"
}

func overridesTouchLatent(overrides []string, sweep string) bool {
	all := append([]string{}, overrides...)
	if sweep != "" {
		all = append(all, sweep)
	}
	for _, o := range all {
		if strings.Contains(o, "width") || strings.Contains(o, "height") ||
			strings.Contains(o, "EmptyLatent") {
			return true
		}
	}
	return false
}

func splitSweep(s string) (string, []string, error) {
	eq := strings.Index(s, "=")
	if eq < 1 {
		return "", nil, fmt.Errorf("sweep musí být cíl=v1|v2")
	}
	var vals []string
	for _, v := range strings.Split(s[eq+1:], "|") {
		if v = strings.TrimSpace(v); v != "" {
			vals = append(vals, v)
		}
	}
	if len(vals) == 0 {
		return "", nil, fmt.Errorf("sweep bez hodnot")
	}
	return s[:eq], vals, nil
}

// DumpEnv translates a spec into the env contract of tools/lab/dump.dart.
//
// Every path goes out absolute: the dump subprocess runs with its working
// directory at the package root (dump.dart reads assets relatively), so a
// relative path here would resolve somewhere else entirely.
func (s *Spec) DumpEnv(dir string) ([]string, error) {
	dir, err := filepath.Abs(dir)
	if err != nil {
		return nil, err
	}
	env := os.Environ()
	set := func(k, v string) {
		if v != "" {
			env = append(env, k+"="+v)
		}
	}
	abs := func(p string) string {
		if p == "" {
			return ""
		}
		a, err := filepath.Abs(p)
		if err != nil {
			return p
		}
		return a
	}
	promptsPath := filepath.Join(dir, "prompts.txt")
	if err := os.WriteFile(promptsPath,
		[]byte(strings.Join(s.Prompts, "\n")+"\n"), 0o644); err != nil {
		return nil, err
	}
	set("OUT_DIR", filepath.Join(dir, "wf"))
	set("MANIFEST", "1")
	set("PROMPTS_FILE", promptsPath)
	set("SUBJECT", firstOr(s.Prompts, "a photo"))
	set("SEED", strconv.Itoa(s.Seed))
	set("BATCH", strconv.Itoa(maxIntv(s.Batch, 1)))
	set("FLOWS", strings.Join(s.Flows, ","))
	set("MODELS", strings.Join(s.Models, ","))
	set("STYLES", strings.Join(s.Styles, ","))
	set("STYLES_FILE", abs(s.StylesFile))
	set("REF_NAME", s.RefName)
	set("REF_FILE", abs(s.RefFile))
	set("POSE_MODE", s.PoseMode)
	set("POSE_NAME", s.PoseName)
	set("SOURCE_DEPTH", s.SourceDepth)
	// set() drops empty strings, so an unset identity simply never reaches the
	// dump — which defaults it to "none" anyway.
	set("FACE_IDENTITY", s.FaceIdentity)
	if s.FaceDetail {
		set("FACE_DETAIL", "1")
	}
	set("LORA", s.Lora)
	if s.Lora != "" && s.LoraStrength != nil {
		// FormatFloat, not set(): "0" must reach the dump, and set() drops
		// empty strings only — but a literal zero is exactly what we mean.
		env = append(env, "LORA_STRENGTH="+
			strconv.FormatFloat(*s.LoraStrength, 'f', -1, 64))
	}
	set("NEGATIVE", s.Negative)
	set("LATENT", s.Latent)
	set("OVERRIDE_AT", strings.Join(s.Overrides, ","))
	set("SWEEP", s.Sweep)
	set("SWEEP_LABEL", s.SweepLabel)
	if s.NoBaseline {
		set("NO_BASELINE", "1")
	}
	if s.EditDenoise > 0 {
		set("EDIT_DENOISE", strconv.FormatFloat(s.EditDenoise, 'f', -1, 64))
	}
	return env, nil
}

func firstOr(list []string, def string) string {
	if len(list) > 0 && list[0] != "" {
		return list[0]
	}
	return def
}

func maxIntv(v, min int) int {
	if v < min {
		return min
	}
	return v
}
