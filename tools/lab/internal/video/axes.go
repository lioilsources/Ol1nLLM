package video

import (
	"fmt"
	"sort"
	"strings"
)

// Axes a picture has. Content axes say what is in the picture; run and setup
// say where it came from and only become axes when a recipe makes them one.
const (
	AxModel     = "model"
	AxStyle     = "style"
	AxPrompt    = "prompt"
	AxCharacter = "character"
	AxPrefix    = "prefix"
	AxFlow      = "flow"
	AxVariant   = "variant"
	AxRun       = "run"
	AxSetup     = "setup"
)

// ContentAxes in the order a slide key lists them.
var ContentAxes = []string{AxPrompt, AxCharacter, AxPrefix, AxStyle, AxFlow, AxVariant, AxModel}

// AllAxes is every axis a recipe may name.
var AllAxes = append(append([]string{}, ContentAxes...), AxRun, AxSetup)

// AxisName is the Czech name of an axis for people.
func AxisName(axis string) string {
	switch axis {
	case AxModel:
		return "model"
	case AxStyle:
		return "styl"
	case AxPrompt:
		return "prompt"
	case AxCharacter:
		return "postava"
	case AxPrefix:
		return "prefix"
	case AxFlow:
		return "flow"
	case AxVariant:
		return "hodnota sweepu"
	case AxRun:
		return "běh"
	case AxSetup:
		return "nastavení"
	}
	return axis
}

// IsAxis reports whether name is a known axis.
func IsAxis(name string) bool {
	for _, a := range AllAxes {
		if a == name {
			return true
		}
	}
	return false
}

// Prompt identity: the prompt file's entry (same scene, text per model family)
// or the whole column label.
const (
	IdentityScene  = "scene"
	IdentityColumn = "column"
)

// Collision is two runs offering a picture for the same combination of axes.
type Collision struct {
	Key  string `json:"key"`
	Kept string `json:"kept"`
	Lost string `json:"lost"`
	// SameSetup: both runs drew it with the same settings, a repeat. Without
	// it the pictures differ in something that is not an axis (seed, denoise…).
	SameSetup bool `json:"sameSetup"`
}

// Pool is the pictures of the chosen runs merged into one collection, with
// the orders every axis is shown in.
type Pool struct {
	Pics     []Pic
	Identity string
	Runs     []*Run

	Collisions []Collision
	// DifferentSetups counts collisions whose pictures were drawn with
	// different settings — the ones a recipe must decide about.
	DifferentSetups int
	Empty           int

	styleMeta   map[string]StyleMeta
	modelLabel  map[string]string
	rank        map[string]map[string]int
	promptLabel map[string]string
}

// NewPool merges runs. identity "" picks scene when every run has prompt file
// entries, column otherwise. prefer decides between two pictures of the same
// combination: "first" (run order given), "newest", or "error".
func NewPool(runs []*Run, identity, prefer string) (*Pool, error) {
	if len(runs) == 0 {
		return nil, fmt.Errorf("žádný běh")
	}
	allScenes := true
	for _, r := range runs {
		allScenes = allScenes && r.Scenes
	}
	switch identity {
	case "":
		identity = IdentityColumn
		if allScenes {
			identity = IdentityScene
		}
	case IdentityScene:
		if !allScenes {
			var no []string
			for _, r := range runs {
				if !r.Scenes {
					no = append(no, r.ID)
				}
			}
			return nil, fmt.Errorf("prompt_identity: scene — běhy %s nemají promptový soubor (id scén); použij column",
				strings.Join(no, ", "))
		}
	case IdentityColumn:
	default:
		return nil, fmt.Errorf("prompt_identity: %q, čekám scene nebo column", identity)
	}
	switch prefer {
	case "", "first", "newest", "error":
	default:
		return nil, fmt.Errorf("prefer: %q, čekám first, newest nebo error", prefer)
	}
	ordered := append([]*Run{}, runs...)
	if prefer == "newest" {
		sort.SliceStable(ordered, func(i, j int) bool { return ordered[i].ID > ordered[j].ID })
	}

	p := &Pool{
		Identity: identity, Runs: runs,
		styleMeta: map[string]StyleMeta{}, modelLabel: map[string]string{},
		rank: map[string]map[string]int{}, promptLabel: map[string]string{},
	}
	for _, a := range AllAxes {
		p.rank[a] = map[string]int{}
	}
	p.rank[AxStyle][Baseline] = -1
	p.styleMeta[Baseline] = StyleMeta{ID: Baseline, Label: "bez stylu"}
	promptMin := map[string]int{}
	seen := map[string]Pic{}
	for _, r := range ordered {
		p.Empty += r.Empty
		for _, s := range r.Styles {
			if _, ok := p.rank[AxStyle][s.ID]; !ok {
				p.rank[AxStyle][s.ID] = len(p.rank[AxStyle])
			}
			if _, ok := p.styleMeta[s.ID]; !ok {
				p.styleMeta[s.ID] = s
			}
		}
		for _, m := range r.Models {
			if _, ok := p.rank[AxModel][m.ID]; !ok {
				p.rank[AxModel][m.ID] = len(p.rank[AxModel])
			}
			if p.modelLabel[m.ID] == "" {
				p.modelLabel[m.ID] = m.Label
			}
		}
		if _, ok := p.rank[AxRun][r.ID]; !ok {
			p.rank[AxRun][r.ID] = len(p.rank[AxRun])
		}
		for _, pic := range r.Pics {
			key := p.contentKey(pic)
			if prev, dup := seen[key]; dup {
				c := Collision{Key: key, Kept: prev.Run, Lost: pic.Run, SameSetup: prev.Setup == pic.Setup}
				if prefer == "error" {
					return nil, fmt.Errorf("obrázek %s je v běhu %s i %s (prefer: error)", key, prev.Run, pic.Run)
				}
				p.Collisions = append(p.Collisions, c)
				if !c.SameSetup {
					p.DifferentSetups++
				}
				continue
			}
			seen[key] = pic
			p.Pics = append(p.Pics, pic)
			pk := p.Value(pic, AxPrompt)
			if v, ok := promptMin[pk]; !ok || pic.PromptIndex < v {
				promptMin[pk] = pic.PromptIndex
			}
			if p.promptLabel[pk] == "" {
				p.promptLabel[pk] = pk
			}
		}
	}
	// Prompts in run order; merged runs by the lowest index a prompt has in any.
	pkeys := make([]string, 0, len(promptMin))
	for k := range promptMin {
		pkeys = append(pkeys, k)
	}
	sort.Slice(pkeys, func(i, j int) bool {
		if promptMin[pkeys[i]] != promptMin[pkeys[j]] {
			return promptMin[pkeys[i]] < promptMin[pkeys[j]]
		}
		return pkeys[i] < pkeys[j]
	})
	for i, k := range pkeys {
		p.rank[AxPrompt][k] = i
	}
	// Everything else in order of first appearance; a sweep in its own order.
	for _, pic := range p.Pics {
		for _, a := range []string{AxStyle, AxModel, AxFlow, AxCharacter, AxPrefix, AxSetup} {
			v := p.Value(pic, a)
			if _, ok := p.rank[a][v]; !ok {
				p.rank[a][v] = len(p.rank[a]) + 1000
			}
		}
		if _, ok := p.rank[AxVariant][pic.Variant]; !ok {
			p.rank[AxVariant][pic.Variant] = pic.VariantOrder
		}
		if _, ok := p.styleMeta[pic.Style]; !ok {
			p.styleMeta[pic.Style] = StyleMeta{ID: pic.Style, Label: pic.Style}
		}
		if p.modelLabel[pic.Model] == "" {
			p.modelLabel[pic.Model] = pic.Model
		}
	}
	return p, nil
}

// contentKey identifies what a picture shows: two pictures with the same key
// are the same cell of the matrix, whichever run drew them.
func (p *Pool) contentKey(pic Pic) string {
	parts := make([]string, len(ContentAxes))
	for i, a := range ContentAxes {
		parts[i] = p.Value(pic, a)
	}
	return strings.Join(parts, "|")
}

// Value is a picture's value on an axis.
func (p *Pool) Value(pic Pic, axis string) string {
	switch axis {
	case AxModel:
		return pic.Model
	case AxStyle:
		return pic.Style
	case AxFlow:
		return pic.Flow
	case AxVariant:
		return pic.Variant
	case AxRun:
		return pic.Run
	case AxSetup:
		return pic.Setup
	case AxPrompt:
		if p.Identity == IdentityScene {
			return pic.Scene
		}
		return pic.Column
	case AxCharacter:
		if p.Identity == IdentityScene {
			return pic.Character
		}
		return ""
	case AxPrefix:
		if p.Identity == IdentityScene {
			return pic.Prefix
		}
		return ""
	}
	return ""
}

// Rank orders values of an axis: styles in the app's picker order (baseline
// first), models in run order, prompts in run order, the rest as they come.
func (p *Pool) Rank(axis, value string) int {
	if r, ok := p.rank[axis][value]; ok {
		return r
	}
	return 1 << 30
}

// Values lists the distinct values of an axis in order.
func (p *Pool) Values(axis string) []string {
	set := map[string]bool{}
	for _, pic := range p.Pics {
		set[p.Value(pic, axis)] = true
	}
	return p.sortValues(axis, set)
}

func (p *Pool) sortValues(axis string, set map[string]bool) []string {
	out := make([]string, 0, len(set))
	for v := range set {
		out = append(out, v)
	}
	sort.Slice(out, func(i, j int) bool {
		ri, rj := p.Rank(axis, out[i]), p.Rank(axis, out[j])
		if ri != rj {
			return ri < rj
		}
		return out[i] < out[j]
	})
	return out
}

// Label is how a value reads: the model's name, the style with its year.
func (p *Pool) Label(axis, value string) string {
	switch axis {
	case AxModel:
		if l := p.modelLabel[value]; l != "" {
			return l
		}
	case AxStyle:
		if m, ok := p.styleMeta[value]; ok && m.Label != "" {
			return m.Label
		}
	case AxPrompt:
		if value == "" {
			return "bez promptu"
		}
	}
	return value
}

// Style returns the registry's metadata of a style.
func (p *Pool) Style(id string) StyleMeta { return p.styleMeta[id] }

// Selection filters a pool: per axis, the allowed values in the order the
// recipe lists them (that order also orders the axis), or values to drop.
type Selection struct {
	Only  map[string][]string
	Not   map[string][]string
	Kinds []string // style kinds (culture, artist, medium)
}

// Select keeps the pictures a selection allows and reorders the axes it lists.
func (p *Pool) Select(sel Selection) *Pool {
	out := *p
	out.rank = map[string]map[string]int{}
	for a, m := range p.rank {
		cp := make(map[string]int, len(m))
		for k, v := range m {
			cp[k] = v
		}
		out.rank[a] = cp
	}
	only := map[string]map[string]bool{}
	for a, vals := range sel.Only {
		if len(vals) == 0 {
			continue
		}
		only[a] = map[string]bool{}
		for i, v := range vals {
			only[a][v] = true
			out.rank[a][v] = -1000 + i // the recipe's order wins
		}
	}
	not := map[string]map[string]bool{}
	for a, vals := range sel.Not {
		not[a] = map[string]bool{}
		for _, v := range vals {
			not[a][v] = true
		}
	}
	kinds := map[string]bool{}
	for _, k := range sel.Kinds {
		kinds[k] = true
	}
	out.Pics = nil
	for _, pic := range p.Pics {
		ok := true
		for a, set := range only {
			if !set[p.Value(pic, a)] {
				ok = false
				break
			}
		}
		for a, set := range not {
			if ok && set[p.Value(pic, a)] {
				ok = false
			}
		}
		if ok && len(kinds) > 0 && pic.Style != Baseline && !kinds[p.styleMeta[pic.Style].Kind] {
			ok = false
		}
		if ok {
			out.Pics = append(out.Pics, pic)
		}
	}
	return &out
}

// ParseWhere turns "axis=value" items into a selection (values of one axis
// are alternatives, in the order given).
func ParseWhere(items []string) (Selection, error) {
	sel := Selection{Only: map[string][]string{}}
	for _, it := range items {
		k, v, ok := strings.Cut(it, "=")
		k, v = strings.TrimSpace(k), strings.TrimSpace(v)
		if !ok || k == "" {
			return sel, fmt.Errorf("--where čeká osa=hodnota, ne %q", it)
		}
		if !IsAxis(k) {
			return sel, fmt.Errorf("--where: neznámá osa %q (osy: %s)", k, strings.Join(AllAxes, ", "))
		}
		sel.Only[k] = append(sel.Only[k], v)
	}
	return sel, nil
}
