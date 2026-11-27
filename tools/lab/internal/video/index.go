// Package video is the lab's video studio: an index of every picture of every
// run by axis (model, style, prompt, flow…), coverage and suggestions over it,
// recipes, storyboards and the renderer. It knows nothing about HTTP or the
// lab's Env — the main package wires it to the CLI and the server.
//
// Plan and vocabulary: docs/plan-video-studio.md.
package video

import (
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// Baseline is the style id of a cell without a style block.
const Baseline = "__baseline"

// cacheVersion invalidates every cached run when the cached shape changes.
const cacheVersion = 3

// Pic is one picture of one run: a manifest cell whose image is on disk and
// not empty. Everything the studio needs about it, nothing it does not — the
// prompt text, negative and graph stay in the manifest.
type Pic struct {
	Run         string `json:"run"`
	Cell        string `json:"cell"`
	Model       string `json:"model"`
	Style       string `json:"style"`
	Flow        string `json:"flow"`
	PromptIndex int    `json:"promptIndex"`
	// Scene is the prompt file's entry id (promptBody); empty when the prompt
	// was typed into the box. Column is the run's label of the whole prompt
	// column: prefix · scene · character.
	Scene     string `json:"scene,omitempty"`
	Column    string `json:"column"`
	Prefix    string `json:"prefix,omitempty"`
	Character string `json:"character,omitempty"`
	Variant   string `json:"variant,omitempty"`
	// VariantOrder keeps a sweep in its own order (0.5 before 0.75).
	VariantOrder int `json:"variantOrder,omitempty"`
	// Setup fingerprints the settings that change a picture besides the axes:
	// seed, LoRA, face identity, denoise, negative… Two runs with the same
	// setup drew the same thing; with different ones they did not.
	Setup string `json:"setup"`
}

// StyleMeta is what the app's registry says about a style.
type StyleMeta struct {
	ID    string `json:"id"`
	Label string `json:"label"`
	Kind  string `json:"kind,omitempty"`
	Year  *int   `json:"year,omitempty"`
}

// ModelMeta names a model.
type ModelMeta struct {
	ID    string `json:"id"`
	Label string `json:"label"`
}

// Run is one lab run as the studio sees it.
type Run struct {
	ID      string    `json:"id"`
	Title   string    `json:"title"`
	Status  string    `json:"status"`
	Created time.Time `json:"created"`
	Dir     string    `json:"-"`
	// Total is the number of cells the run planned; Pics the ones with a
	// picture. Empty counts 0-byte files — failed downloads of older labs.
	Total int   `json:"total"`
	Pics  []Pic `json:"-"`
	Empty int   `json:"empty"`
	// Styles and Models in the run's own order (the app's picker order).
	Styles []StyleMeta `json:"styles"`
	Models []ModelMeta `json:"models"`
	// Prompts is the run's prompt columns in order; Scenes whether every
	// column comes from a prompt file entry.
	Prompts []string `json:"prompts"`
	Scenes  bool     `json:"scenes"`
	// Family groups runs with the same set of prompts: the runs whose
	// pictures can honestly sit next to each other.
	Family string `json:"family"`
	// Placeholder: a dry run, its pictures are hatched stand-ins.
	Placeholder bool `json:"placeholder,omitempty"`

	styleCount map[string]bool
}

// PicCount is how many pictures the run has.
func (r *Run) PicCount() int { return len(r.Pics) }

// StyleCount is how many styles the run has pictures of (baseline included);
// Styles is the whole registry the run knew.
func (r *Run) StyleCount() int { return len(r.styleCount) }

// ── reading a run ───────────────────────────────────────────

// leanManifest reads only what the index needs: manifests are up to 10 MB,
// mostly prompt texts and graphs it never looks at.
type leanManifest struct {
	Cells []struct {
		ID           string         `json:"id"`
		Flow         string         `json:"flow"`
		Model        string         `json:"model"`
		ModelLabel   string         `json:"modelLabel"`
		Style        string         `json:"style"`
		StyleLabel   *string        `json:"styleLabel"`
		PromptIndex  int            `json:"promptIndex"`
		PromptBody   string         `json:"promptBody"`
		PromptPrefix string         `json:"promptPrefix"`
		Character    string         `json:"character"`
		Negative     *string        `json:"negative"`
		Params       map[string]any `json:"params"`
		Variant      *struct {
			Value string `json:"value"`
			Order int    `json:"order"`
		} `json:"variant"`
		DependsOn string `json:"dependsOn"`
	} `json:"cells"`
	Models []struct {
		ID    string `json:"id"`
		Label string `json:"label"`
	} `json:"models"`
	Styles []struct {
		ID            string `json:"id"`
		Label         string `json:"label"`
		LabelWithYear string `json:"labelWithYear"`
		Kind          string `json:"kind"`
		Year          *int   `json:"year"`
	} `json:"styles"`
	Prompts []string `json:"prompts"`
}

type leanSpec struct {
	Prompts    []string `json:"prompts"`
	Characters []string `json:"characters"`
	BaseModel  string   `json:"baseModel"`
	Negative   string   `json:"negative"`
	RefFile    string   `json:"refFile"`
	Dry        bool     `json:"dry"`
}

type leanState struct {
	Title     string    `json:"title"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"createdAt"`
	Dry       bool      `json:"dry"`
}

// cached is the manifest-derived part of a run; which pictures exist is read
// fresh every time (one directory listing), so a running run stays current.
type cached struct {
	Version   int         `json:"version"`
	Size      int64       `json:"size"`
	ModTime   int64       `json:"modTime"`
	Cells     []Pic       `json:"cells"`
	Styles    []StyleMeta `json:"styles"`
	Models    []ModelMeta `json:"models"`
	Prompts   []string    `json:"prompts"`
	Scenes    bool        `json:"scenes"`
	Title     string      `json:"title"`
	Positions int         `json:"positions"`
}

// LoadRun reads one run directory. cacheDir may be empty (no cache).
func LoadRun(dir, cacheDir string) (*Run, error) {
	id := filepath.Base(dir)
	manPath := filepath.Join(dir, "wf", "manifest.json")
	st, err := os.Stat(manPath)
	if err != nil {
		return nil, fmt.Errorf("%s: chybí manifest", id)
	}
	c, err := readCached(cacheDir, id, st)
	if err != nil {
		return nil, err
	}
	if c == nil {
		c, err = parseRun(dir, st)
		if err != nil {
			return nil, err
		}
		writeCached(cacheDir, id, c)
	}
	run := &Run{
		ID: id, Dir: dir, Title: c.Title, Styles: c.Styles, Models: c.Models,
		Prompts: c.Prompts, Scenes: c.Scenes, Total: len(c.Cells),
	}
	var state leanState
	if data, err := os.ReadFile(filepath.Join(dir, "state.json")); err == nil {
		_ = json.Unmarshal(data, &state)
	}
	run.Status = state.Status
	run.Created = state.CreatedAt
	run.Placeholder = state.Dry
	if state.Title != "" {
		run.Title = state.Title
	}
	if run.Created.IsZero() {
		if t, err := time.ParseInLocation("20060102-150405", id, time.Local); err == nil {
			run.Created = t
		}
	}
	sizes := imageSizes(filepath.Join(dir, "img"))
	for _, p := range c.Cells {
		size, ok := sizes[p.Cell+".png"]
		switch {
		case !ok:
		case size == 0:
			run.Empty++
		default:
			p.Run = id
			run.Pics = append(run.Pics, p)
		}
	}
	run.Family = familyKey(c.Cells, c.Scenes)
	for _, p := range run.Pics {
		if run.styleCount == nil {
			run.styleCount = map[string]bool{}
		}
		run.styleCount[p.Style] = true
	}
	return run, nil
}

func imageSizes(dir string) map[string]int64 {
	out := map[string]int64{}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return out
	}
	for _, e := range entries {
		if info, err := e.Info(); err == nil {
			out[e.Name()] = info.Size()
		}
	}
	return out
}

func readCached(cacheDir, id string, st os.FileInfo) (*cached, error) {
	if cacheDir == "" {
		return nil, nil
	}
	data, err := os.ReadFile(filepath.Join(cacheDir, id+".json"))
	if err != nil {
		return nil, nil
	}
	var c cached
	if json.Unmarshal(data, &c) != nil || c.Version != cacheVersion ||
		c.Size != st.Size() || c.ModTime != st.ModTime().UnixNano() {
		return nil, nil
	}
	return &c, nil
}

func writeCached(cacheDir, id string, c *cached) {
	if cacheDir == "" {
		return
	}
	if os.MkdirAll(cacheDir, 0o755) != nil {
		return
	}
	data, err := json.Marshal(c)
	if err != nil {
		return
	}
	tmp := filepath.Join(cacheDir, id+".json.tmp")
	if os.WriteFile(tmp, data, 0o644) == nil {
		_ = os.Rename(tmp, filepath.Join(cacheDir, id+".json"))
	}
}

func parseRun(dir string, st os.FileInfo) (*cached, error) {
	data, err := os.ReadFile(filepath.Join(dir, "wf", "manifest.json"))
	if err != nil {
		return nil, err
	}
	var m leanManifest
	if err := json.Unmarshal(data, &m); err != nil {
		return nil, fmt.Errorf("%s: manifest: %w", filepath.Base(dir), err)
	}
	var spec leanSpec
	if sd, err := os.ReadFile(filepath.Join(dir, "spec.json")); err == nil {
		_ = json.Unmarshal(sd, &spec)
	}
	c := &cached{
		Version: cacheVersion, Size: st.Size(), ModTime: st.ModTime().UnixNano(),
		Prompts: m.Prompts, Scenes: len(m.Cells) > 0,
	}
	for _, md := range m.Models {
		c.Models = append(c.Models, ModelMeta{ID: md.ID, Label: md.Label})
	}
	for _, s := range m.Styles {
		label := s.LabelWithYear
		if label == "" {
			label = s.Label
		}
		c.Styles = append(c.Styles, StyleMeta{ID: s.ID, Label: label, Kind: s.Kind, Year: s.Year})
	}
	knownModel := map[string]bool{}
	for _, md := range c.Models {
		knownModel[md.ID] = true
	}
	knownStyle := map[string]bool{}
	for _, s := range c.Styles {
		knownStyle[s.ID] = true
	}
	runSetup := map[string]any{
		"negative": spec.Negative, "baseModel": spec.BaseModel, "ref": refStamp(spec.RefFile),
	}
	for _, cell := range m.Cells {
		if cell.Flow == "position" {
			c.Positions++
			continue // the restyle's photo, a source for a reference tile, not a picture of the matrix
		}
		style := cell.Style
		if style == "" {
			style = Baseline
		}
		p := Pic{
			Cell: cell.ID, Model: cell.Model, Style: style, Flow: cell.Flow,
			PromptIndex: cell.PromptIndex, Scene: cell.PromptBody,
			Prefix: cell.PromptPrefix, Character: cell.Character,
		}
		if cell.PromptIndex >= 0 && cell.PromptIndex < len(m.Prompts) {
			p.Column = m.Prompts[cell.PromptIndex]
		} else {
			p.Column = fmt.Sprintf("#%d", cell.PromptIndex)
		}
		if p.Prefix == "" && p.Character == "" && p.Scene != "" {
			p.Prefix, p.Character = splitColumn(p.Column, p.Scene)
		}
		if cell.Variant != nil {
			p.Variant, p.VariantOrder = cell.Variant.Value, cell.Variant.Order
		}
		if cell.PromptBody == "" {
			c.Scenes = false
		}
		p.Setup = setupHash(cell.Params, runSetup, cell.Negative)
		c.Cells = append(c.Cells, p)
		// Older manifests list only what the run picked; keep a label for
		// every model and style a cell names.
		if !knownModel[cell.Model] {
			knownModel[cell.Model] = true
			c.Models = append(c.Models, ModelMeta{ID: cell.Model, Label: orDefault(cell.ModelLabel, cell.Model)})
		}
		if !knownStyle[style] && style != Baseline {
			knownStyle[style] = true
			label := style
			if cell.StyleLabel != nil {
				label = *cell.StyleLabel
			}
			c.Styles = append(c.Styles, StyleMeta{ID: style, Label: label})
		}
	}
	// A character (or prefix) is an axis only where it tells columns of one
	// run apart. A run with a single character wrote it for its model family —
	// like the prompt text itself — so it is part of the run's setup, and runs
	// with differently worded characters still line up by scene.
	for _, field := range []func(*Pic) *string{
		func(p *Pic) *string { return &p.Character },
		func(p *Pic) *string { return &p.Prefix },
	} {
		distinct := map[string]bool{}
		for i := range c.Cells {
			distinct[*field(&c.Cells[i])] = true
		}
		if len(distinct) > 1 {
			continue
		}
		for i := range c.Cells {
			v := field(&c.Cells[i])
			if *v != "" {
				c.Cells[i].Setup = shortHash(c.Cells[i].Setup + "\n" + *v)
				*v = ""
			}
		}
	}
	c.Title = filepath.Base(dir)
	return c, nil
}

func shortHash(s string) string {
	sum := sha1.Sum([]byte(s))
	return hex.EncodeToString(sum[:])[:10]
}

// splitColumn recovers prefix and character from a column label
// "prefix · scene · character" for manifests written before the cell carried
// them. Either side may be missing.
func splitColumn(column, scene string) (prefix, character string) {
	parts := strings.Split(column, " · ")
	for i, part := range parts {
		if part == scene {
			return strings.Join(parts[:i], " · "), strings.Join(parts[i+1:], " · ")
		}
	}
	return "", ""
}

// refStamp identifies a reference picture by size and name — the content
// hash would mean reading megabytes per run for a value that rarely matters.
func refStamp(path string) string {
	if path == "" {
		return ""
	}
	st, err := os.Stat(path)
	if err != nil {
		return filepath.Base(path)
	}
	return fmt.Sprintf("%s:%d", filepath.Base(path), st.Size())
}

// setupHash fingerprints everything that changes a picture but is not an
// axis. Params that only say where something was uploaded are left out.
func setupHash(params map[string]any, run map[string]any, negative *string) string {
	keys := make([]string, 0, len(params))
	for k := range params {
		if k == "refName" || k == "batch" {
			continue
		}
		keys = append(keys, k)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys)+4)
	for _, k := range keys {
		parts = append(parts, fmt.Sprintf("%s=%v", k, params[k]))
	}
	for _, k := range []string{"baseModel", "negative", "ref"} {
		parts = append(parts, fmt.Sprintf("%s=%v", k, run[k]))
	}
	if negative != nil {
		parts = append(parts, "cellNegative="+*negative)
	}
	sum := sha1.Sum([]byte(strings.Join(parts, "\n")))
	return hex.EncodeToString(sum[:])[:10]
}

func orDefault(s, def string) string {
	if s == "" {
		return def
	}
	return s
}

// familyKey: runs with the same set of prompt identities. With a prompt file
// the identity is the entry id (scene), without one the column text. Taken
// from the planned cells, not the pictures: an interrupted run still belongs
// to the family it set out to draw.
func familyKey(cells []Pic, scenes bool) string {
	set := map[string]bool{}
	for _, p := range cells {
		set[promptID(p, scenes)] = true
	}
	if len(set) == 0 {
		return ""
	}
	keys := make([]string, 0, len(set))
	for k := range set {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	kind := "column"
	if scenes {
		kind = "scene"
	}
	sum := sha1.Sum([]byte(kind + "\n" + strings.Join(keys, "\n")))
	return hex.EncodeToString(sum[:])[:8]
}

func promptID(p Pic, scenes bool) string {
	if scenes && p.Scene != "" {
		return p.Scene
	}
	return p.Column
}

// ── the whole collection ────────────────────────────────────

// Collection is every run under a lab directory.
type Collection struct {
	Runs   []*Run
	byID   map[string]*Run
	Errors []string
}

// Load indexes every run directory under labDir (build/lab). Directories
// starting with "_" are the lab's own (uploads, merged output, the cache).
func Load(labDir string) (*Collection, error) {
	entries, err := os.ReadDir(labDir)
	if err != nil {
		return nil, err
	}
	cacheDir := filepath.Join(labDir, "_video", ".index")
	col := &Collection{byID: map[string]*Run{}}
	var mu sync.Mutex
	var wg sync.WaitGroup
	sem := make(chan struct{}, 8)
	for _, e := range entries {
		name := e.Name()
		if strings.HasPrefix(name, "_") || strings.HasPrefix(name, ".") {
			continue
		}
		dir := filepath.Join(labDir, name)
		if st, err := os.Stat(dir); err != nil || !st.IsDir() {
			continue
		}
		if _, err := os.Stat(filepath.Join(dir, "wf", "manifest.json")); err != nil {
			continue
		}
		wg.Add(1)
		sem <- struct{}{}
		go func() {
			defer wg.Done()
			defer func() { <-sem }()
			run, err := LoadRun(dir, cacheDir)
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				col.Errors = append(col.Errors, err.Error())
				return
			}
			col.Runs = append(col.Runs, run)
		}()
	}
	wg.Wait()
	sort.Slice(col.Runs, func(i, j int) bool { return col.Runs[i].ID < col.Runs[j].ID })
	for _, r := range col.Runs {
		col.byID[r.ID] = r
	}
	sort.Strings(col.Errors)
	return col, nil
}

// Run returns a run by id.
func (c *Collection) Run(id string) *Run { return c.byID[id] }

// ClearCache drops the cached index (lab video index --refresh).
func ClearCache(labDir string) error {
	return os.RemoveAll(filepath.Join(labDir, "_video", ".index"))
}

// Family is a group of runs with the same prompts.
type Family struct {
	Key     string   `json:"key"`
	Runs    []*Run   `json:"-"`
	RunIDs  []string `json:"runs"`
	Prompts int      `json:"prompts"`
	Scenes  bool     `json:"scenes"`
	Models  []string `json:"models"`
	Flows   []string `json:"flows"`
	Pics    int      `json:"pics"`
}

// Families groups runs with at least minPics pictures, the families with
// more models first.
func (c *Collection) Families(minPics int) []*Family {
	byKey := map[string]*Family{}
	var order []string
	for _, r := range c.Runs {
		if r.Family == "" || len(r.Pics) < minPics {
			continue
		}
		f := byKey[r.Family]
		if f == nil {
			f = &Family{Key: r.Family, Scenes: r.Scenes}
			byKey[r.Family] = f
			order = append(order, r.Family)
		}
		f.Runs = append(f.Runs, r)
		f.RunIDs = append(f.RunIDs, r.ID)
		f.Pics += len(r.Pics)
	}
	out := make([]*Family, 0, len(order))
	for _, k := range order {
		f := byKey[k]
		models, flows, prompts := map[string]bool{}, map[string]bool{}, map[string]bool{}
		for _, r := range f.Runs {
			for _, p := range r.Pics {
				models[p.Model] = true
				flows[p.Flow] = true
				prompts[promptID(p, f.Scenes)] = true
			}
		}
		f.Models, f.Flows, f.Prompts = sortedKeys(models), sortedKeys(flows), len(prompts)
		out = append(out, f)
	}
	sort.SliceStable(out, func(i, j int) bool {
		if len(out[i].Models) != len(out[j].Models) {
			return len(out[i].Models) > len(out[j].Models)
		}
		return out[i].Pics > out[j].Pics
	})
	return out
}

// FamilyOf returns the family a run belongs to (all its runs, any size).
func (c *Collection) FamilyOf(runID string) []*Run {
	r := c.byID[runID]
	if r == nil || r.Family == "" {
		return nil
	}
	var out []*Run
	for _, x := range c.Runs {
		if x.Family == r.Family && len(x.Pics) > 0 {
			out = append(out, x)
		}
	}
	return out
}

func sortedKeys(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
