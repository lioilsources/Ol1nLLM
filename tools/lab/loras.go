package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
)

// LoRA trigger words, read out of each file's own training metadata.
//
// There is no manifest on the server and no convention in the filenames, so
// the words a LoRA actually responds to are only recoverable from the
// safetensors header. Three sources, in descending order of trust:
//
//	metadata — an explicit trigger field (`avatar_trigger`, `trigger_phrase`).
//	tagy     — captions present on *every* training image (ss_tag_frequency).
//	dataset  — the training folder names, when there are no captions at all.
//
// The source travels with the words on purpose: "tagy" is evidence, "dataset"
// is an educated guess, and the UI says which one it is instead of presenting
// both as fact.

// LoraTrigger is one word or phrase plus how much of the dataset carried it.
type LoraTrigger struct {
	Word string `json:"word"`
	// Cover is "160/160" for tag-derived words, empty for the other sources.
	Cover string `json:"cover"`
}

// LoraInfo is what the control panel needs to offer one LoRA: what it is
// called, what to type to wake it up, and whether it fits the chosen models.
type LoraInfo struct {
	Name          string        `json:"name"`
	Triggers      []LoraTrigger `json:"triggers"`
	TriggerSource string        `json:"triggerSource"`
	// Base is the checkpoint it was trained on, as the metadata records it —
	// the evidence behind the family, shown so a wrong family is spottable.
	Base string `json:"base"`
	// Family / Fit come from the app's registry via the manifest, not from
	// here: lineage is curated in lib/models/lora_family.dart.
	Family      string            `json:"family"`
	FamilyLabel string            `json:"familyLabel"`
	Fit         map[string]string `json:"fit"`
}

// triggerCoverage: a caption on 99 % of the images is part of the LoRA's
// identity; one on 90 % is just a common subject in the dataset. Measured
// against the 36 LoRAs on the server, 0.99 is where "usnr", "cardoggy",
// "sp4c3sh1p" and "anime screencap" stay in while the merely-frequent
// "sweat" (221/225) and "spread legs" (88/100) drop out.
const triggerCoverage = 0.99

// Booru/caption boilerplate. These reach full coverage in a dataset that is
// simply all-female or all-photographic, and typing them back does nothing.
// Deliberately short: it only ever removes words that already cleared the
// coverage bar, so anything specific must survive.
var genericTags = map[string]bool{
	"1girl": true, "2girls": true, "1boy": true, "solo": true,
	"solo focus": true, "looking at viewer": true, "male focus": true,
	"long hair": true, "short hair": true, "medium hair": true,
	"black hair": true, "blonde hair": true, "brown hair": true,
	"blue eyes": true, "brown eyes": true, "green eyes": true,
	"breasts": true, "large breasts": true, "medium breasts": true,
	"blush": true, "smile": true, "closed mouth": true, "open mouth": true,
	"simple background": true, "white background": true, "no humans": true,
	"upper body": true, "full body": true, "standing": true, "sitting": true,
	"photo": true, "realistic": true, "woman": true, "man": true,
	"girl": true, "day": true, "outdoors": true, "indoors": true,
	"lips": true, "jewelry": true, "earrings": true, "bangs": true,
}

// minTriggerImages: below this a folder is too small for "on every image" to
// mean anything.
const minTriggerImages = 8

var repeatPrefix = regexp.MustCompile(`^\d+_`)

// genericDirs are training-folder names that say nothing about the concept.
var genericDirs = map[string]bool{
	"img": true, "dataset": true, "image_dir": true, "images": true,
	"train": true, "data": true,
}

// extractTriggers returns the words to type and where they came from.
func extractTriggers(meta map[string]string) ([]LoraTrigger, string) {
	if t := explicitTriggers(meta); len(t) > 0 {
		return t, "metadata"
	}
	if t := tagTriggers(meta); len(t) > 0 {
		return t, "tagy"
	}
	if t := dirTriggers(meta); len(t) > 0 {
		return t, "dataset"
	}
	return nil, ""
}

// explicitTriggers takes any field whose name says "trigger" — ai-toolkit
// writes `avatar_trigger`, the model-spec draft `modelspec.trigger_phrase`.
func explicitTriggers(meta map[string]string) []LoraTrigger {
	keys := make([]string, 0, 2)
	for k := range meta {
		if strings.Contains(strings.ToLower(k), "trigger") {
			keys = append(keys, k)
		}
	}
	sort.Strings(keys)
	var out []LoraTrigger
	for _, k := range keys {
		for _, w := range strings.Split(meta[k], ",") {
			if w = cleanWord(w); w != "" {
				out = append(out, LoraTrigger{Word: w})
			}
		}
	}
	return capTriggers(out, 6)
}

// tagTriggers keeps the captions that were on (almost) every image of a
// training folder. Each folder is judged on its own: a two-concept LoRA
// (`10_denim` + `10_micro_shorts`) has one trigger per folder, not one overall.
func tagTriggers(meta map[string]string) []LoraTrigger {
	raw := meta["ss_tag_frequency"]
	if raw == "" {
		return nil
	}
	var byDir map[string]map[string]float64
	if json.Unmarshal([]byte(raw), &byDir) != nil {
		return nil
	}
	counts := dirImageCounts(meta)

	dirs := make([]string, 0, len(byDir))
	for d := range byDir {
		dirs = append(dirs, d)
	}
	sort.Strings(dirs)

	type hit struct {
		word  string
		c     float64
		total float64
	}
	var all []hit
	for _, dir := range dirs {
		tags := byDir[dir]
		total := counts[dir]
		if total <= 0 {
			// No ss_dataset_dirs entry: the most frequent tag is then the only
			// available denominator.
			for _, c := range tags {
				if c > total {
					total = c
				}
			}
		}
		if total < minTriggerImages {
			// A four-image folder cannot establish anything; whatever is on
			// all four is on all four by accident.
			continue
		}
		hits := make([]hit, 0, 4)
		for tag, c := range tags {
			if c < total*triggerCoverage {
				continue
			}
			w := cleanWord(tag)
			if w == "" || genericTags[strings.ToLower(w)] {
				continue
			}
			// Counts above the image count are real: kohya counts some
			// datasets once per repeat. The ratio is still the signal.
			hits = append(hits, hit{w, c, total})
		}
		sort.Slice(hits, func(i, j int) bool {
			if hits[i].c != hits[j].c {
				return hits[i].c > hits[j].c
			}
			return hits[i].word < hits[j].word
		})
		for i, h := range hits {
			if i == 4 {
				break // one folder cannot flood the list
			}
			all = append(all, h)
		}
	}
	// Across folders the strongest evidence wins the six slots.
	sort.SliceStable(all, func(i, j int) bool {
		if all[i].c != all[j].c {
			return all[i].c > all[j].c
		}
		return all[i].word < all[j].word
	})
	out := make([]LoraTrigger, 0, len(all))
	for _, h := range all {
		out = append(out, LoraTrigger{
			Word: h.word, Cover: num(h.c) + "/" + num(h.total),
		})
	}
	return capTriggers(out, 6)
}

// dirTriggers is the last resort: `7_hoodie` → `hoodie`. Only used when the
// file carries no captions at all, and only for folder names that name a
// concept — `img` and `dataset` are just where the pictures sat.
func dirTriggers(meta map[string]string) []LoraTrigger {
	counts := dirImageCounts(meta)
	dirs := make([]string, 0, len(counts))
	for d := range counts {
		dirs = append(dirs, d)
	}
	sort.Strings(dirs)
	var out []LoraTrigger
	for _, d := range dirs {
		if counts[d] <= 0 {
			continue // .ipynb_checkpoints and friends
		}
		w := cleanWord(repeatPrefix.ReplaceAllString(d, ""))
		if w == "" || genericDirs[strings.ToLower(w)] || genericTags[strings.ToLower(w)] {
			continue
		}
		out = append(out, LoraTrigger{Word: w})
	}
	return capTriggers(out, 6)
}

func dirImageCounts(meta map[string]string) map[string]float64 {
	out := map[string]float64{}
	var dirs map[string]struct {
		ImgCount float64 `json:"img_count"`
	}
	if json.Unmarshal([]byte(meta["ss_dataset_dirs"]), &dirs) == nil {
		for d, v := range dirs {
			out[d] = v.ImgCount
		}
	}
	return out
}

// loraBase is the checkpoint the file says it was trained on — the same field
// lib/models/lora_family.dart was curated from, so a family that looks wrong
// can be checked against its own evidence.
func loraBase(meta map[string]string) string {
	for _, k := range []string{"ss_sd_model_name", "ss_base_model_version",
		"modelspec.architecture"} {
		if v := cleanWord(meta[k]); v != "" && v != "None" {
			return v
		}
	}
	return ""
}

func cleanWord(s string) string {
	s = strings.TrimSpace(s)
	s = strings.Trim(s, `"'`)
	s = strings.TrimSpace(s)
	if s == "" || s == "None" || s == "null" || len(s) > 80 {
		return ""
	}
	return s
}

func capTriggers(in []LoraTrigger, max int) []LoraTrigger {
	seen := map[string]bool{}
	out := make([]LoraTrigger, 0, max)
	for _, t := range in {
		key := strings.ToLower(t.Word)
		if seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, t)
		if len(out) == max {
			break
		}
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

func num(f float64) string { return strconv.FormatFloat(f, 'f', -1, 64) }

// TriggerCache remembers what a filename's metadata said. The mapping is
// immutable — a given .safetensors never changes its own header — so entries
// never expire; only files the server has newly grown are fetched.
type TriggerCache struct {
	path   string
	mu     sync.Mutex
	byName map[string]cachedLora
}

type cachedLora struct {
	Triggers []LoraTrigger `json:"triggers"`
	Source   string        `json:"source"`
	Base     string        `json:"base"`
}

func NewTriggerCache(path string) *TriggerCache {
	c := &TriggerCache{path: path, byName: map[string]cachedLora{}}
	if data, err := os.ReadFile(path); err == nil {
		_ = json.Unmarshal(data, &c.byName)
	}
	return c
}

// Fill fetches metadata for every name it does not already know and returns
// the enriched list in the order given. A fetch that errors is left out of the
// cache so it is retried, but never blocks the list: a LoRA with unknown
// trigger words is still a LoRA you can run.
func (c *TriggerCache) Fill(comfy *Comfy, names []string) []LoraInfo {
	missing := make([]string, 0, len(names))
	c.mu.Lock()
	for _, n := range names {
		if _, ok := c.byName[n]; !ok {
			missing = append(missing, n)
		}
	}
	c.mu.Unlock()

	if len(missing) > 0 && comfy != nil && comfy.HasCreds() {
		const workers = 6
		var wg sync.WaitGroup
		jobs := make(chan string)
		for i := 0; i < workers; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				for n := range jobs {
					meta, err := comfy.LoraMetadata(n)
					if err != nil {
						continue
					}
					t, src := extractTriggers(meta)
					c.mu.Lock()
					c.byName[n] = cachedLora{Triggers: t, Source: src, Base: loraBase(meta)}
					c.mu.Unlock()
				}
			}()
		}
		for _, n := range missing {
			jobs <- n
		}
		close(jobs)
		wg.Wait()
		c.save()
	}

	out := make([]LoraInfo, 0, len(names))
	c.mu.Lock()
	defer c.mu.Unlock()
	for _, n := range names {
		e := c.byName[n]
		out = append(out, LoraInfo{
			Name: n, Triggers: e.Triggers, TriggerSource: e.Source, Base: e.Base,
			Fit: map[string]string{},
		})
	}
	return out
}

func (c *TriggerCache) save() {
	c.mu.Lock()
	data, err := json.MarshalIndent(c.byName, "", " ")
	c.mu.Unlock()
	if err != nil {
		return
	}
	_ = os.MkdirAll(filepath.Dir(c.path), 0o755)
	tmp := c.path + ".tmp"
	if os.WriteFile(tmp, data, 0o644) == nil {
		_ = os.Rename(tmp, c.path)
	}
}
