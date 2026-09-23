package main

import (
	"encoding/json"
	"os"
)

// Which service runs a cell. The values are the app's own backend ids
// (lib/services/image_backend.dart), so the manifest and the app agree on the
// name of the thing that produced a picture.
const (
	BackendComfy = "comfyui"
	BackendNim   = "flux_nim"
)

// Manifest is what dump.dart writes: the authoritative description of a run's
// cells. The lab never parses filenames — a cell is whatever the manifest says
// it is, so a naming change in the dumper cannot silently reshape a run.
type Manifest struct {
	Cells   []ManifestCell  `json:"cells"`
	Skipped []ManifestSkip  `json:"skipped"`
	Models  []ManifestModel `json:"models"`
	Styles  []ManifestStyle `json:"styles"`
	Poses   []ManifestPose  `json:"poses"`
	Buckets []string        `json:"buckets"`
	Prompts []string        `json:"prompts"`
	// Loras is the server's LoRA list classified by the app's registry; the
	// trigger words are joined onto it later, from each file's metadata.
	Loras               []ManifestLora `json:"loras"`
	DefaultLoraStrength float64        `json:"defaultLoraStrength"`
}

type ManifestLora struct {
	Name        string            `json:"name"`
	Family      string            `json:"family"`
	FamilyLabel string            `json:"familyLabel"`
	Fit         map[string]string `json:"fit"`
}

type ManifestCell struct {
	ID string `json:"id"`
	// Backend decides how wf/<id>.json is read: a ComfyUI graph to submit, or
	// a gen-queue request body to POST. Empty in manifests written before the
	// NIM path existed — ReadManifest fills those in.
	Backend    string  `json:"backend"`
	Flow       string  `json:"flow"`
	Model      string  `json:"model"`
	ModelLabel string  `json:"modelLabel"`
	Style      string  `json:"style"`
	StyleLabel *string `json:"styleLabel"`
	// StyleText is the style block as sent. Per cell, not per row: which text
	// a style sends can depend on the model reading it.
	StyleText   *string `json:"styleText"`
	PromptIndex int     `json:"promptIndex"`
	// PromptBody names the entry of the prompt file this column came from;
	// empty when the prompt box was the whole axis.
	PromptBody string              `json:"promptBody"`
	Prompt     *string             `json:"prompt"`
	Negative   *string             `json:"negative"`
	Variant    *Variant            `json:"variant"`
	Params     map[string]any      `json:"params"`
	Applied    map[string][]string `json:"applied"`
	// PresetOverridden marks a cell whose sampler settings no longer are the
	// model's own — such a result must not be quoted back as a model verdict.
	PresetOverridden bool `json:"presetOverridden"`
}

type Variant struct {
	Label string `json:"label"`
	Value string `json:"value"`
	Order int    `json:"order"`
}

type ManifestSkip struct {
	Cell   string `json:"cell"`
	Reason string `json:"reason"`
}

type ManifestModel struct {
	ID    string `json:"id"`
	Label string `json:"label"`
	// Backend as in ManifestCell. A NIM model has no Preset — its steps and
	// size are fixed inside the NIM service, not in a checkpoint.
	Backend      string `json:"backend"`
	SupportsPose bool   `json:"supportsPose"`
	// PromptDialect is how the model reads a style: "natural" or "booru".
	PromptDialect string `json:"promptDialect"`
	// PromptFamily is which text of a prompt file the model reads: "danbooru",
	// "juggernaut" or "flux". Empty in manifests written before prompt files
	// existed — promptFamilyOf derives it then.
	PromptFamily string         `json:"promptFamily"`
	StyleNote    *string        `json:"styleNote"`
	CkptName     *string        `json:"ckptName"`
	Preset       map[string]any `json:"preset"`
}

type ManifestStyle struct {
	ID    string `json:"id"`
	Label string `json:"label"`
	Block string `json:"block"`
	// Booru is the tag variant anime models get instead of Block.
	Booru string `json:"booru,omitempty"`
	// Artist is empty for cultures and epochs; the UI splits the chips on it.
	Artist string `json:"artist,omitempty"`
	Period string `json:"period,omitempty"`
}

type ManifestPose struct {
	ID    string `json:"id"`
	Label string `json:"label"`
	Asset string `json:"asset"`
}

func ReadManifest(path string) (*Manifest, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var m Manifest
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, err
	}
	// A manifest from before the NIM path has no backend field, and every cell
	// in it is a ComfyUI graph. Defaulting here rather than at each use keeps
	// the rest of the lab free of "" as a third, silent backend.
	for i := range m.Models {
		if m.Models[i].Backend == "" {
			m.Models[i].Backend = BackendComfy
		}
	}
	// dump.dart emits variants in sweep order; record it so neighbour deltas
	// compare 0.5→0.75 rather than whatever the map iteration gave us.
	seen := map[string]int{}
	for i := range m.Cells {
		if m.Cells[i].Backend == "" {
			m.Cells[i].Backend = BackendComfy
		}
		v := m.Cells[i].Variant
		if v == nil {
			continue
		}
		key := m.Cells[i].Flow + "|" + m.Cells[i].Model + "|" +
			m.Cells[i].Style + "|" + itoa(m.Cells[i].PromptIndex)
		v.Order = seen[key]
		seen[key]++
	}
	return &m, nil
}
