package main

import (
	"bytes"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
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
// The same table is accepted as CSV, which is how a spreadsheet of positions
// leaves the editor — one row per prompt, one column per family:
//
//	id,juggernaut,pony,flux
//	arabesque,"a ballerina in arabesque","1girl, ballerina, arabesque","A ballerina holds an arabesque."
//
// `pony` is the column name people use for the tag family; it means danbooru.
// An empty cell is "no text for this family", the same as a missing YAML key.
//
// A `negative` column (a `negative:` key in YAML) is what this one prompt must
// not show — "sitting" next to a standing pose. One text for every family: it
// is a tag list either way, and FLUX takes no negative at all.
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

// PromptBody is one entry of the file: an id, its text per family and the
// negative that goes with it. The JSON tags are the contract with
// dump_spec.dart's parsePromptBodies.
type PromptBody struct {
	ID       string            `json:"id"`
	Texts    map[string]string `json:"texts"`
	Negative string            `json:"negative,omitempty"`
}

// negativeKey is the one column that is not a family.
const negativeKey = "negative"

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

// readsNegative says whether a negative reaches the model. Old manifests
// lack the field; there the FLUX family was exactly the set that ignores it.
func readsNegative(m ManifestModel) bool {
	if m.ReadsNegative != nil {
		return *m.ReadsNegative
	}
	return promptFamilyOf(m) != FamilyFlux
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
	data = bytes.TrimPrefix(data, []byte("\xef\xbb\xbf")) // Excel's BOM
	if looksLikePromptCSV(data, name) {
		return parsePromptCSV(data, name)
	}
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
		negative := ""
		for j := 0; j+1 < len(val.Content); j += 2 {
			fk, fv := val.Content[j], val.Content[j+1]
			if fk.Value == negativeKey {
				if fv.Kind != yaml.ScalarNode {
					return nil, fmt.Errorf("%s řádek %d: negativ promptu %q musí být text",
						name, fv.Line, id)
				}
				negative = strings.TrimSpace(fv.Value)
				continue
			}
			// A typo here would otherwise drop a text silently, and the run
			// would look like a measurement of a prompt nobody wrote.
			if !knownPromptFamily(fk.Value) {
				return nil, fmt.Errorf("%s řádek %d: prompt %q má neznámou rodinu %q — čekám %s, %s",
					name, fk.Line, id, fk.Value, strings.Join(promptFamilies, ", "), negativeKey)
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
		out = append(out, PromptBody{ID: id, Texts: texts, Negative: negative})
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("%s: žádné prompty", name)
	}
	return out, nil
}

// csvFamilyColumns maps a CSV header to the family it fills. `pony` is an
// alias: the spreadsheet names the column after the checkpoint people think
// of, the lab after the tag vocabulary.
var csvFamilyColumns = map[string]string{
	"danbooru":   FamilyDanbooru,
	"pony":       FamilyDanbooru,
	"juggernaut": FamilyJuggernaut,
	"flux":       FamilyFlux,
}

// looksLikePromptCSV decides by content as well as by name: the upload handler
// stores whatever arrives under one extension, and a header row starting with
// `id` and a separator is not a YAML mapping anyone would write.
func looksLikePromptCSV(data []byte, name string) bool {
	if strings.EqualFold(filepath.Ext(name), ".csv") {
		return true
	}
	head := strings.ToLower(strings.TrimSpace(firstLine(data)))
	for _, sep := range []string{",", ";", "\t"} {
		if strings.HasPrefix(head, "id"+sep) || strings.HasPrefix(head, `"id"`+sep) {
			return true
		}
	}
	return false
}

func firstLine(data []byte) string {
	for _, line := range strings.Split(string(data), "\n") {
		if strings.TrimSpace(line) != "" {
			return line
		}
	}
	return ""
}

// csvDelimiter picks the separator the header was written with. A Czech Excel
// exports semicolons, and a tag prompt is full of commas — so the header, which
// has no prose in it, is the only line worth counting on.
func csvDelimiter(header string) rune {
	best, count := ',', strings.Count(header, ",")
	for _, r := range []rune{';', '\t'} {
		if n := strings.Count(header, string(r)); n > count {
			best, count = r, n
		}
	}
	return best
}

func parsePromptCSV(data []byte, name string) ([]PromptBody, error) {
	r := csv.NewReader(bytes.NewReader(data))
	r.Comma = csvDelimiter(firstLine(data))
	r.TrimLeadingSpace = true
	header, err := r.Read()
	if errors.Is(err, io.EOF) {
		return nil, fmt.Errorf("%s: prázdný soubor", name)
	}
	if err != nil {
		return nil, fmt.Errorf("%s: %w", name, err)
	}
	columns := make([]string, len(header)) // family per column; "" for id and negative
	idCol, negCol := -1, -1
	for i, h := range header {
		h = strings.ToLower(strings.TrimSpace(h))
		if h == "id" {
			if idCol >= 0 {
				return nil, fmt.Errorf("%s: sloupec id je v hlavičce dvakrát", name)
			}
			idCol = i
			continue
		}
		if h == negativeKey {
			if negCol >= 0 {
				return nil, fmt.Errorf("%s: sloupec %s je v hlavičce dvakrát", name, negativeKey)
			}
			negCol = i
			continue
		}
		fam, ok := csvFamilyColumns[h]
		if !ok {
			return nil, fmt.Errorf("%s: neznámý sloupec %q — čekám id, juggernaut, pony, flux, %s",
				name, header[i], negativeKey)
		}
		for _, other := range columns[:i] {
			if other == fam {
				return nil, fmt.Errorf("%s: rodina %s je v hlavičce dvakrát (pony = danbooru)",
					name, fam)
			}
		}
		columns[i] = fam
	}
	if idCol < 0 {
		return nil, fmt.Errorf("%s: v hlavičce chybí sloupec id", name)
	}
	// A fixed column count on purpose: an unquoted tag prompt spills its commas
	// into the neighbouring families, and a run on those texts would look like
	// a measurement of prompts nobody wrote.
	r.FieldsPerRecord = len(header)
	var out []PromptBody
	seen := map[string]bool{}
	for {
		row, err := r.Read()
		if errors.Is(err, io.EOF) {
			break
		}
		line, _ := r.FieldPos(0)
		if err != nil {
			if errors.Is(err, csv.ErrFieldCount) {
				return nil, fmt.Errorf("%s řádek %d: čekám %d sloupců — text s oddělovačem patří do uvozovek",
					name, line, len(header))
			}
			return nil, fmt.Errorf("%s: %w", name, err)
		}
		id := strings.TrimSpace(row[idCol])
		if id == "" {
			return nil, fmt.Errorf("%s řádek %d: prompt bez jména", name, line)
		}
		if seen[id] {
			return nil, fmt.Errorf("%s řádek %d: prompt %q je v souboru dvakrát", name, line, id)
		}
		seen[id] = true
		texts := map[string]string{}
		for i, fam := range columns {
			if fam == "" {
				continue
			}
			if text := strings.TrimSpace(row[i]); text != "" {
				texts[fam] = text
			}
		}
		if len(texts) == 0 {
			return nil, fmt.Errorf("%s řádek %d: prompt %q nemá žádný text", name, line, id)
		}
		body := PromptBody{ID: id, Texts: texts}
		if negCol >= 0 {
			body.Negative = strings.TrimSpace(row[negCol])
		}
		out = append(out, body)
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

// hasNegative says whether any entry of the file brings its own negative.
func hasNegative(bodies []PromptBody) bool {
	for _, b := range bodies {
		if b.Negative != "" {
			return true
		}
	}
	return false
}
