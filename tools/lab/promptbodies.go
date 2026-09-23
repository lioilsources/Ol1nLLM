package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

// Prompt bodies: a YAML file that writes the same subject out once per model
// family, so one run can ask every model the same thing in the language it
// reads. The prompt box keeps its old meaning next to it — its lines become
// prefixes, and the axis is the product.
//
//	portrait:
//	  danbooru: "1girl, solo, looking at viewer"
//	  juggernaut: "a portrait of a young woman, looking at the camera"
//	  flux: "A portrait photograph of a young woman looking at the camera."
//
// Go owns the parse — the estimate needs the count on every keystroke, long
// before the dump could be asked — and writes the normalised JSON into the run
// directory for dump.dart. One parser, and the run keeps the file it ran on.
const (
	FamilyDanbooru   = "danbooru"
	FamilyJuggernaut = "juggernaut"
	FamilyFlux       = "flux"
)

// promptFamilies is also the order every message lists them in.
var promptFamilies = []string{FamilyDanbooru, FamilyJuggernaut, FamilyFlux}

// PromptBody is one entry of the file: an id and its text per family. The JSON
// tags are the contract with dump_spec.dart's parsePromptBodies.
type PromptBody struct {
	ID    string            `json:"id"`
	Texts map[string]string `json:"texts"`
}

// promptFamilyOf is the model's family as dump.dart computed it. Derived there,
// from the app registry, and carried on the manifest so the plan does not keep
// a second opinion about which checkpoint reads tags.
//
// The fallback covers manifests written before the field existed (a cached
// registry probe, at most an hour old) and mirrors the Dart rule exactly:
// dialect first, then FLUX — which is "no checkpoint to patch", the same test
// the rest of the plan already uses for a dedicated template.
func promptFamilyOf(m ManifestModel) string {
	if m.PromptFamily != "" {
		return m.PromptFamily
	}
	if m.PromptDialect == "booru" {
		return FamilyDanbooru
	}
	if m.Backend != BackendComfy || m.CkptName == nil {
		return FamilyFlux
	}
	return FamilyJuggernaut
}

// ParsePromptBodies reads the prompt YAML in document order — the index of an
// entry becomes a column of the run, so the order on disk has to survive.
func ParsePromptBodies(path string) ([]PromptBody, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return parsePromptBodies(data, filepath.Base(path))
}

func parsePromptBodies(data []byte, name string) ([]PromptBody, error) {
	var doc yaml.Node
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("%s: %w", name, err)
	}
	if len(doc.Content) == 0 {
		return nil, fmt.Errorf("%s: prázdný soubor", name)
	}
	root := doc.Content[0]
	if root.Kind != yaml.MappingNode {
		return nil, fmt.Errorf("%s: čekám mapu promptů (jméno promptu, pod ním %s)",
			name, strings.Join(promptFamilies, " / "))
	}
	out := make([]PromptBody, 0, len(root.Content)/2)
	seen := map[string]bool{}
	for i := 0; i+1 < len(root.Content); i += 2 {
		key, val := root.Content[i], root.Content[i+1]
		id := strings.TrimSpace(key.Value)
		if id == "" {
			return nil, fmt.Errorf("%s řádek %d: prompt bez jména", name, key.Line)
		}
		if seen[id] {
			return nil, fmt.Errorf("%s řádek %d: prompt %q je v souboru dvakrát",
				name, key.Line, id)
		}
		seen[id] = true
		if val.Kind != yaml.MappingNode {
			return nil, fmt.Errorf("%s řádek %d: prompt %q musí mít texty po rodinách (%s)",
				name, val.Line, id, strings.Join(promptFamilies, ", "))
		}
		texts := map[string]string{}
		for j := 0; j+1 < len(val.Content); j += 2 {
			fk, fv := val.Content[j], val.Content[j+1]
			// A typo here would otherwise drop a text silently, and the run
			// would look like a measurement of a prompt nobody wrote.
			if !knownPromptFamily(fk.Value) {
				return nil, fmt.Errorf("%s řádek %d: prompt %q má neznámou rodinu %q — čekám %s",
					name, fk.Line, id, fk.Value, strings.Join(promptFamilies, ", "))
			}
			if fv.Kind != yaml.ScalarNode || strings.TrimSpace(fv.Value) == "" {
				return nil, fmt.Errorf("%s řádek %d: prompt %q má prázdný text pro %s",
					name, fv.Line, id, fk.Value)
			}
			texts[fk.Value] = fv.Value
		}
		if len(texts) == 0 {
			return nil, fmt.Errorf("%s řádek %d: prompt %q nemá žádný text", name, key.Line, id)
		}
		out = append(out, PromptBody{ID: id, Texts: texts})
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("%s: žádné prompty", name)
	}
	return out, nil
}

func knownPromptFamily(name string) bool {
	for _, f := range promptFamilies {
		if f == name {
			return true
		}
	}
	return false
}

// promptFamiliesInRun maps each family the picked models read to the labels of
// the models reading it, so a complaint can name them.
func promptFamiliesInRun(models []ManifestModel, picked map[string]bool) map[string][]string {
	out := map[string][]string{}
	for _, m := range models {
		if len(picked) > 0 && !picked[m.ID] {
			continue
		}
		f := promptFamilyOf(m)
		out[f] = append(out[f], m.Label)
	}
	return out
}

// missingPromptTexts reports the families a run needs and the file does not
// cover. Said here, on every keystroke, rather than left to the dump: the file
// is the slow thing to fix, and finding out from a crashed dump is the long way
// round.
func missingPromptTexts(bodies []PromptBody, families map[string][]string) []string {
	var out []string
	for _, f := range promptFamilies {
		readers, ok := families[f]
		if !ok {
			continue
		}
		var lacking []string
		for _, b := range bodies {
			if strings.TrimSpace(b.Texts[f]) == "" {
				lacking = append(lacking, b.ID)
			}
		}
		if len(lacking) == 0 {
			continue
		}
		sort.Strings(readers)
		out = append(out, fmt.Sprintf("%s nemá text pro %s (%s)",
			strings.Join(lacking, ", "), f, strings.Join(readers, ", ")))
	}
	return out
}
