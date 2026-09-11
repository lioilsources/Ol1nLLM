package main

import (
	"encoding/json"
	"os"
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
	ID          string              `json:"id"`
	Flow        string              `json:"flow"`
	Model       string              `json:"model"`
	ModelLabel  string              `json:"modelLabel"`
	Style       string              `json:"style"`
	StyleLabel  *string             `json:"styleLabel"`
	// StyleText is the style block as sent. Per cell, not per row: which text
	// a style sends can depend on the model reading it.
	StyleText   *string             `json:"styleText"`
	PromptIndex int                 `json:"promptIndex"`
	Prompt      *string             `json:"prompt"`
	Negative    *string             `json:"negative"`
	Variant     *Variant            `json:"variant"`
	Params      map[string]any      `json:"params"`
	Applied     map[string][]string `json:"applied"`
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
	ID           string `json:"id"`
	Label        string `json:"label"`
	SupportsPose bool   `json:"supportsPose"`
	// PromptDialect is how the model reads a style: "natural" or "booru".
	PromptDialect string         `json:"promptDialect"`
	StyleNote     *string        `json:"styleNote"`
	CkptName      *string        `json:"ckptName"`
	Preset        map[string]any `json:"preset"`
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
	// dump.dart emits variants in sweep order; record it so neighbour deltas
	// compare 0.5→0.75 rather than whatever the map iteration gave us.
	seen := map[string]int{}
	for i := range m.Cells {
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
