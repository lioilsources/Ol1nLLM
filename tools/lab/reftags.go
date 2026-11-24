package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// Ref tags: WD14 booru tags read off the run's reference and used as the
// prompt (or appended to it), so img2img on a booru model needs no typing.
// The tagger is tools/lab/wd14.py — a mirror of the FINETUNE gallery's
// sidecar (same model, preprocessing and thresholds), run locally on CPU so
// the lab works off the home network too.

// RefTags is what the tagger saw and what of it goes into the prompt.
type RefTags struct {
	Model string `json:"model"`
	// Tags is the prompt text in order: character tags first (identity, as
	// the gallery's auto caption has it), then general tags by confidence.
	Tags []string `json:"tags"`
	// Dropped are tags the tagger saw but the prompt leaves out (see
	// refTagDrop) — listed so a run never hides what it decided.
	Dropped   []string           `json:"dropped,omitempty"`
	General   map[string]float64 `json:"general"`
	Character map[string]float64 `json:"character"`
	Rating    map[string]float64 `json:"rating"`
}

// Text is the prompt fragment.
func (t *RefTags) Text() string { return strings.Join(t.Tags, ", ") }

// refTagDrop: tags that describe the reference *as a photo*, not what is in
// it. Sent to a booru model they pull it back to photography (that is what
// those tags mean on danbooru), which is the opposite of why one repaints a
// photo on Illustrious or Pony; artefact tags would get drawn in. The subject,
// clothes, pose and background stay.
var refTagDrop = map[string]bool{
	"realistic": true, "photorealistic": true, "photo (medium)": true,
	"photo background": true, "cosplay": true, "cosplay photo": true, "3d": true,
	"blurry": true, "blurry background": true, "blurry foreground": true,
	"depth of field": true, "bokeh": true, "motion blur": true,
	"film grain": true, "jpeg artifacts": true, "chromatic aberration": true,
	"watermark": true, "signature": true, "artist name": true, "web address": true,
	"dated": true, "twitter username": true, "patreon username": true,
	"username": true,
}

// composeRefTags orders and filters the tagger's output: character tags
// first, then general, each by confidence (ties by name, so the prompt is
// deterministic), minus refTagDrop.
func composeRefTags(general, character map[string]float64) (tags, dropped []string) {
	for _, m := range []map[string]float64{character, general} {
		for _, t := range byConfidence(m) {
			if refTagDrop[t] {
				dropped = append(dropped, t)
				continue
			}
			tags = append(tags, t)
		}
	}
	return tags, dropped
}

func byConfidence(m map[string]float64) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Slice(out, func(i, j int) bool {
		if m[out[i]] != m[out[j]] {
			return m[out[i]] > m[out[j]]
		}
		return out[i] < out[j]
	})
	return out
}

// withRefTags puts the tags behind each prompt line — own text first, as the
// app puts the style behind the prompt — or makes them the only line.
func withRefTags(prompts []string, tags string) []string {
	if tags == "" {
		return prompts
	}
	if len(prompts) == 0 {
		return []string{tags}
	}
	out := make([]string, len(prompts))
	for i, p := range prompts {
		out[i] = p + ", " + tags
	}
	return out
}

func wd14Python(env *Env) string {
	if p := os.Getenv("LAB_WD14_PYTHON"); p != "" {
		return p
	}
	return arcfacePython(env) // one venv for the lab's Python helpers
}

const wd14Timeout = 3 * time.Minute

var refTagCache = struct {
	sync.Mutex
	m map[string]*RefTags // path + stamp → tags
}{m: map[string]*RefTags{}}

// tagReference runs the tagger on one image. Cached per file stamp: the UI
// previews the tags on upload and the run asks again at dump time.
func tagReference(env *Env, path string) (*RefTags, error) {
	stamp, ok := fileStamp(path)
	if !ok {
		return nil, fmt.Errorf("tagy z předlohy: reference %s na disku není", path)
	}
	key := path + "@" + stamp
	refTagCache.Lock()
	if t := refTagCache.m[key]; t != nil {
		refTagCache.Unlock()
		return t, nil
	}
	refTagCache.Unlock()

	python := wd14Python(env)
	if _, err := os.Stat(python); err != nil {
		return nil, fmt.Errorf("tagy z předlohy: chybí %s — nastavení: make lab-wd14", python)
	}
	req, _ := json.Marshal(map[string]string{"image": path})
	ctx, cancel := context.WithTimeout(context.Background(), wd14Timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, python, filepath.Join(env.RepoRoot, "tools", "lab", "wd14.py"))
	cmd.Stdin = bytes.NewReader(req)
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("tagy z předlohy: %s", lastLine(stderr.String(), err.Error()))
	}
	var t RefTags
	if err := json.Unmarshal(stdout.Bytes(), &t); err != nil {
		return nil, fmt.Errorf("tagy z předlohy: odpověď taggeru: %w", err)
	}
	t.Tags, t.Dropped = composeRefTags(t.General, t.Character)
	if len(t.Tags) == 0 {
		return nil, fmt.Errorf("tagy z předlohy: tagger na předloze nic nenašel")
	}
	refTagCache.Lock()
	refTagCache.m[key] = &t
	refTagCache.Unlock()
	return &t, nil
}
