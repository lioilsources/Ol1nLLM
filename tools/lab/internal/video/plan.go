package video

import (
	"errors"
	"fmt"
	"path"
	"path/filepath"
	"sort"
	"strings"
)

// Storyboard is the result of planning: every slide, every output file, and
// why pictures fell out. The preview and the renderer only draw it.
type Storyboard struct {
	Recipe   Recipe                `json:"recipe"`
	Axes     map[string][]Labelled `json:"axes"`
	Tiles    []Labelled            `json:"tiles,omitempty"` // tile slots, fixed for the whole video
	Aspect   float64               `json:"aspect"`          // width/height of the pictures (most common)
	Layout   *Layout               `json:"layout,omitempty"`
	Slides   []Slide               `json:"slides"`
	Videos   []VideoPart           `json:"videos"`
	Stats    Stats                 `json:"stats"`
	Warnings []string              `json:"warnings,omitempty"`
	Sync     *SyncInfo             `json:"sync,omitempty"`
}

// Slide is one stretch of the video: one picture, or one tile per tile value.
type Slide struct {
	Key   map[string]string `json:"key"`
	Match string            `json:"match,omitempty"` // exact | kind | order (loose axes)
	Title string            `json:"title,omitempty"`
	// Tiles has one entry per tile slot (nil = no picture); one entry without tiles.
	Tiles    []*TileRef `json:"tiles"`
	Captions [][]string `json:"captions,omitempty"` // per tile, lines
	group    string     // value of the split axis
	unit     string     // what max_seconds keeps together
}

// TileRef points at one picture; paths are relative to the lab directory.
type TileRef struct {
	Run   string `json:"run"`
	Cell  string `json:"cell"`
	Model string `json:"model"`
	Style string `json:"style"`
	Img   string `json:"img"`
	Thumb string `json:"thumb"`
}

// VideoPart is one output file: slides [From, To).
type VideoPart struct {
	Name    string            `json:"name"`
	Per     map[string]string `json:"per,omitempty"`
	From    int               `json:"from"`
	To      int               `json:"to"`
	Seconds float64           `json:"seconds"`
	Groups  []string          `json:"groups,omitempty"`
	// With time.sync: Times[k] is when slide From+k starts (seconds from the
	// part start, len To-From+1, last = end); Fades[k] its crossfade share.
	Times      []float64 `json:"times,omitempty"`
	Fades      []float64 `json:"fades,omitempty"`
	AudioStart float64   `json:"audioStart,omitempty"`
}

type Stats struct {
	Pictures int            `json:"pictures"` // in the selection
	Slides   int            `json:"slides"`
	Seconds  float64        `json:"seconds"`
	Dropped  map[string]int `json:"dropped"`
	Match    map[string]int `json:"match,omitempty"`
}

// PlanError is a recipe that cannot be planned. Missing lists the axes
// without a role, so a UI can offer the fixes as buttons.
type PlanError struct {
	Problems []string      `json:"problems"`
	Missing  []MissingRole `json:"missing,omitempty"`
}

// MissingRole: an axis with several values and no role.
type MissingRole struct {
	Axis   string     `json:"axis"`
	Name   string     `json:"name"`
	Values []Labelled `json:"values"`
}

func (e *PlanError) Error() string { return strings.Join(e.Problems, "\n  ") }

// Plan turns a recipe into a storyboard over the collection.
func Plan(col *Collection, r Recipe) (*Storyboard, error) {
	r.Defaults()
	if err := r.Validate(); err != nil {
		return nil, err
	}
	runs, err := sourceRuns(col, r.Source)
	if err != nil {
		return nil, err
	}
	pool, err := NewPool(runs, r.Source.PromptIdentity, r.Source.Prefer)
	if err != nil {
		return nil, err
	}
	before := len(pool.Pics)
	pool = pool.Select(selection(r.Select))
	if len(pool.Pics) == 0 {
		return nil, fmt.Errorf("výběru neodpovídá žádný obrázek")
	}
	sb := &Storyboard{Recipe: r, Axes: map[string][]Labelled{},
		Stats: Stats{Pictures: len(pool.Pics), Dropped: map[string]int{}, Match: map[string]int{}}}
	sb.Stats.Dropped["filtered"] = before - len(pool.Pics)
	if f, ok := r.Select[MinReaction]; ok {
		min, _ := f.MinValue()
		kept := pool.Pics[:0:0]
		unscored := map[string]bool{}
		for _, p := range pool.Pics {
			switch {
			case p.Style == Baseline:
			case p.Reaction == nil:
				unscored[p.Run] = true
			case *p.Reaction < min:
				sb.Stats.Dropped["reaction"]++
				continue
			}
			kept = append(kept, p)
		}
		pool.Pics = kept
		for run := range unscored {
			sb.Warnings = append(sb.Warnings, fmt.Sprintf(
				"běh %s nemá metriky (lab score %s) — min_reaction jeho obrázky nefiltruje", run, run))
		}
		sort.Strings(sb.Warnings)
		if len(pool.Pics) == 0 {
			return nil, fmt.Errorf("min_reaction %g vyřadil všechny obrázky", min)
		}
	}
	sb.Stats.Dropped["empty_file"] = pool.Empty
	sb.Stats.Dropped["collision"] = len(pool.Collisions)

	// The role rule: every axis with several values has exactly one role.
	// Time axes the recipe leaves out are filled in canonical order.
	multi := map[string][]string{}
	for _, a := range AllAxes {
		vals := pool.Values(a)
		if a == AxRun || a == AxSetup {
			if len(vals) > 1 {
				sb.Axes[a] = pool.labelled(a, vals)
			}
			continue
		}
		sb.Axes[a] = pool.labelled(a, vals)
		if len(vals) > 1 {
			multi[a] = vals
		}
	}
	hasRole := map[string]bool{}
	if r.Frame.Tiles != "" {
		hasRole[r.Frame.Tiles] = true
	}
	for _, a := range r.Output.Per {
		hasRole[a] = true
	}
	for _, a := range r.Time.Axes {
		hasRole[a] = true
	}
	timeAxes := append([]string{}, r.Time.Axes...)
	if len(r.Time.Axes) == 0 {
		for _, a := range ContentAxes {
			if len(multi[a]) > 1 && !hasRole[a] {
				timeAxes = append(timeAxes, a)
				hasRole[a] = true
			}
		}
		if len(timeAxes) == 0 {
			timeAxes = []string{AxStyle}
		}
		sb.Recipe.Time.Axes = timeAxes
	}
	pe := &PlanError{}
	for _, a := range ContentAxes {
		if vals := multi[a]; len(vals) > 1 && !hasRole[a] {
			pe.Problems = append(pe.Problems, fmt.Sprintf(
				"osa %s má %d hodnot (%s) a nemá roli: přidej ji do time.axes, do output.per, nebo vyber jednu v select.%s",
				AxisName(a), len(vals), preview(pool, a, vals), a))
			pe.Missing = append(pe.Missing, MissingRole{Axis: a, Name: AxisName(a), Values: pool.labelled(a, vals)})
		}
	}
	if len(pe.Problems) > 0 {
		return nil, pe
	}
	for _, a := range []string{AxRun, AxSetup} {
		if hasRole[a] {
			continue
		}
		if a == AxSetup && pool.DifferentSetups > 0 {
			sb.Warnings = append(sb.Warnings, fmt.Sprintf(
				"%d obrázků je ve víc bězích s jiným nastavením (seed, postava, síla úpravy…); bere se %s běh — jinak dej ose setup nebo run roli",
				pool.DifferentSetups, r.Source.Prefer))
		}
	}

	ord := newOrderer(pool, r.Time.Order)
	loose := map[string]bool{}
	for _, a := range r.Time.Loose {
		loose[a] = true
	}
	var strictAxes []string
	for _, a := range timeAxes {
		if !loose[a] {
			strictAxes = append(strictAxes, a)
		}
	}
	splitAt := ""
	if r.Output.Split != nil {
		splitAt = r.Output.Split.At
		if splitAt == "" && len(strictAxes) > 0 {
			splitAt = strictAxes[0]
		}
		sb.Recipe.Output.Split.At = splitAt
	} else if r.Time.Sync != nil && len(strictAxes) > 0 {
		// Music cuts the video into parts too; keep the outer axis whole.
		splitAt = strictAxes[0]
	}

	// Tiles: fixed slots for the whole video, in the axis' order.
	var slots []string
	if r.Frame.Tiles != "" {
		slots = ord.sorted(r.Frame.Tiles, pool.Values(r.Frame.Tiles))
		sb.Tiles = pool.labelled(r.Frame.Tiles, slots)
		if r.Frame.Reference {
			sb.Tiles = append([]Labelled{{ID: refSlot, Label: "předloha"}}, sb.Tiles...)
		}
	}
	refs := refFinder(col, pool)
	sb.Aspect = commonAspect(col, pool)

	// One video (set) per value of the output.per axes.
	perGroups := groupBy(pool.Pics, func(p Pic) string { return joinValues(pool, p, r.Output.Per) })
	perKeys := ord.sortedKeys(r.Output.Per, perGroups)
	for _, pk := range perKeys {
		pics := perGroups[pk]
		var slides []Slide
		if r.Frame.Tiles == "" {
			slides = singleSlides(pool, ord, pics, timeAxes)
		} else {
			slides = tileSlides(pool, ord, pics, r, slots, strictAxes, r.Time.Loose)
			if r.Frame.Reference {
				for i := range slides {
					slides[i].Tiles = append([]*TileRef{refs(slides[i].Tiles)}, slides[i].Tiles...)
				}
			}
		}
		if *r.Time.Complete && r.Frame.Tiles != "" {
			kept := slides[:0]
			for _, s := range slides {
				full := true
				for k, t := range s.Tiles {
					if k == 0 && r.Frame.Reference {
						continue // a missing reference does not make a slide incomplete
					}
					full = full && t != nil
				}
				if full {
					kept = append(kept, s)
				} else {
					sb.Stats.Dropped["incomplete"]++
				}
			}
			slides = kept
		}
		for i := range slides {
			s := &slides[i]
			if splitAt != "" {
				s.group = s.Key[splitAt]
			}
			titleCaptions(pool, &r, s, timeAxes)
		}
		slides = shorten(slides, r.Output.MaxSeconds, r.Time.Rate)
		if len(slides) == 0 {
			continue
		}
		start := len(sb.Slides)
		sb.Slides = append(sb.Slides, slides...)
		per := map[string]string{}
		if len(r.Output.Per) > 0 {
			sample := pics[0]
			for _, a := range r.Output.Per {
				per[a] = pool.Value(sample, a)
			}
		}
		name := r.Name
		if len(per) > 0 {
			var parts []string
			for _, a := range r.Output.Per {
				parts = append(parts, slug(per[a]))
			}
			name += "-" + strings.Join(parts, "-")
		}
		sb.Videos = append(sb.Videos, parts(name, per, sb.Slides, start, len(sb.Slides), r)...)
	}
	if len(sb.Slides) == 0 {
		return nil, fmt.Errorf("po vyřazení neúplných snímků nezbyl žádný (complete: false je ukáže s prázdnými dlaždicemi)")
	}
	for _, s := range sb.Slides {
		if s.Match != "" {
			sb.Stats.Match[s.Match]++
		}
	}
	sb.Stats.Slides = len(sb.Slides)
	sb.Stats.Seconds = float64(len(sb.Slides)) / r.Time.Rate
	for _, v := range sb.Videos {
		if v.Seconds > 180 {
			sb.Warnings = append(sb.Warnings, fmt.Sprintf(
				"%s má %.0f s — YouTube Shorts a Reels berou nejvýš 180 s (output.split)", v.Name, v.Seconds))
		}
	}
	if w, h, err := ParseSize(r.Output.Size); err == nil {
		l := ComputeLayout(w, h, len(sb.Tiles), int(r.Frame.Cols), sb.Aspect, r.Frame.Title != "none",
			captionLines(sb), r.Frame.Tiles != "")
		sb.Layout = &l
		if len(slots) > 0 && l.TileW < 220 {
			sb.Warnings = append(sb.Warnings, fmt.Sprintf(
				"dlaždice mají jen %d px na šířku — v telefonu budou malé; zkus frame.cols s víc řádky", l.TileW))
		}
	}
	return sb, nil
}

// refSlot marks the reference tile (frame.reference).
const refSlot = "__reference"

// refFinder returns the reference picture of a slide: the position photo a
// restyle was drawn over, or the run's reference picture — of the slide's
// first picture that has one. Paths are relative to the lab directory.
func refFinder(col *Collection, p *Pool) func([]*TileRef) *TileRef {
	byCell := map[string]Pic{}
	for _, pic := range p.Pics {
		byCell[pic.Run+"/"+pic.Cell] = pic
	}
	return func(tiles []*TileRef) *TileRef {
		for _, t := range tiles {
			if t == nil {
				continue
			}
			pic, ok := byCell[t.Run+"/"+t.Cell]
			if !ok {
				continue
			}
			rel := ""
			if pic.RefCell != "" {
				rel = path.Join(pic.Run, "img", pic.RefCell+".png")
			} else if run := col.Run(pic.Run); run != nil && run.RefFile != "" {
				lab := filepath.Dir(run.Dir)
				if r, err := filepath.Rel(lab, run.RefFile); err == nil && !strings.HasPrefix(r, "..") {
					rel = filepath.ToSlash(r)
				}
			}
			if rel != "" {
				return &TileRef{Run: pic.Run, Model: refSlot, Img: rel, Thumb: rel}
			}
		}
		return nil
	}
}

func preview(p *Pool, axis string, vals []string) string {
	var out []string
	for i, v := range vals {
		if i == 4 {
			out = append(out, "…")
			break
		}
		out = append(out, p.Label(axis, v))
	}
	return strings.Join(out, ", ")
}

func sourceRuns(col *Collection, s Source) ([]*Run, error) {
	if s.Family != "" {
		runs := col.FamilyOf(s.Family)
		if runs == nil {
			return nil, fmt.Errorf("source.family: běh %s není nebo nemá obrázky", s.Family)
		}
		return runs, nil
	}
	var runs []*Run
	var missing []string
	for _, id := range s.Runs {
		if r := col.Run(id); r != nil {
			runs = append(runs, r)
		} else {
			missing = append(missing, id)
		}
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("source.runs: v build/lab nejsou %s", strings.Join(missing, ", "))
	}
	return runs, nil
}

func selection(s SelectSpec) Selection {
	sel := Selection{Only: map[string][]string{}, Not: map[string][]string{}}
	for axis, f := range s {
		if axis == MinReaction {
			continue
		}
		if len(f.Only) > 0 {
			sel.Only[axis] = f.Only
		}
		if len(f.Not) > 0 {
			sel.Not[axis] = f.Not
		}
		sel.Kinds = append(sel.Kinds, f.Kind...)
	}
	return sel
}

// ── order ───────────────────────────────────────────────────

type orderer struct {
	pool *Pool
	by   map[string]string
}

func newOrderer(p *Pool, by map[string]string) *orderer { return &orderer{pool: p, by: by} }

func (o *orderer) less(axis, a, b string) bool {
	switch o.by[axis] {
	case "label":
		la, lb := o.pool.Label(axis, a), o.pool.Label(axis, b)
		if la != lb {
			return compareCzech(la, lb) < 0
		}
	case "year":
		if axis == AxStyle && (a == Baseline) != (b == Baseline) {
			return a == Baseline
		}
		ya, yb := o.pool.styleMeta[a].Year, o.pool.styleMeta[b].Year
		switch {
		case ya != nil && yb != nil && *ya != *yb:
			return *ya < *yb
		case (ya == nil) != (yb == nil):
			return ya != nil
		}
	}
	ra, rb := o.pool.Rank(axis, a), o.pool.Rank(axis, b)
	if ra != rb {
		return ra < rb
	}
	return a < b
}

func (o *orderer) sorted(axis string, vals []string) []string {
	out := append([]string{}, vals...)
	sort.SliceStable(out, func(i, j int) bool { return o.less(axis, out[i], out[j]) })
	return out
}

// sortedKeys orders group keys built by joinValues over axes.
func (o *orderer) sortedKeys(axes []string, groups map[string][]Pic) []string {
	keys := make([]string, 0, len(groups))
	for k := range groups {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		a, b := groups[keys[i]][0], groups[keys[j]][0]
		for _, ax := range axes {
			va, vb := o.pool.Value(a, ax), o.pool.Value(b, ax)
			if va != vb {
				return o.less(ax, va, vb)
			}
		}
		return keys[i] < keys[j]
	})
	return keys
}

func (o *orderer) picLess(axes []string, a, b Pic) bool {
	for _, ax := range axes {
		va, vb := o.pool.Value(a, ax), o.pool.Value(b, ax)
		if va != vb {
			return o.less(ax, va, vb)
		}
	}
	return false
}

// compareCzech orders labels roughly as Czech does: case and diacritics
// second (Č after C, but „Čapek“ before „Dali“).
func compareCzech(a, b string) int {
	fa, fb := foldCzech(a), foldCzech(b)
	if fa != fb {
		if fa < fb {
			return -1
		}
		return 1
	}
	return strings.Compare(a, b)
}

func foldCzech(s string) string {
	r := strings.NewReplacer("á", "a", "č", "c", "ď", "d", "é", "e", "ě", "e", "í", "i", "ň", "n",
		"ó", "o", "ř", "r", "š", "s", "ť", "t", "ú", "u", "ů", "u", "ý", "y", "ž", "z")
	return r.Replace(strings.ToLower(s))
}

// ── slides ──────────────────────────────────────────────────

func groupBy(pics []Pic, key func(Pic) string) map[string][]Pic {
	out := map[string][]Pic{}
	for _, p := range pics {
		k := key(p)
		out[k] = append(out[k], p)
	}
	return out
}

func joinValues(p *Pool, pic Pic, axes []string) string {
	parts := make([]string, len(axes))
	for i, a := range axes {
		parts[i] = p.Value(pic, a)
	}
	return strings.Join(parts, "\x1f")
}

func keyOf(p *Pool, pic Pic, axes []string) map[string]string {
	k := make(map[string]string, len(axes))
	for _, a := range axes {
		k[a] = p.Value(pic, a)
	}
	return k
}

func tileRef(pic Pic) *TileRef {
	return &TileRef{Run: pic.Run, Cell: pic.Cell, Model: pic.Model, Style: pic.Style,
		Img: path.Join(pic.Run, "img", pic.Cell+".png"), Thumb: path.Join(pic.Run, "thumb", pic.Cell+".jpg")}
}

// singleSlides: one picture per slide, ordered by the time axes.
func singleSlides(p *Pool, o *orderer, pics []Pic, timeAxes []string) []Slide {
	sorted := append([]Pic{}, pics...)
	sort.SliceStable(sorted, func(i, j int) bool { return o.picLess(timeAxes, sorted[i], sorted[j]) })
	unitAxes := timeAxes
	if n := len(timeAxes); n > 1 && timeAxes[n-1] == AxModel {
		// A stroboscope across models keeps every model of a style together.
		unitAxes = timeAxes[:n-1]
	}
	out := make([]Slide, len(sorted))
	for i, pic := range sorted {
		out[i] = Slide{Key: keyOf(p, pic, timeAxes), Tiles: []*TileRef{tileRef(pic)},
			unit: joinValues(p, pic, unitAxes)}
		if len(unitAxes) == len(timeAxes) {
			out[i].unit = fmt.Sprint(i)
		}
		out[i].Key[AxModel] = pic.Model
		out[i].Key[AxStyle] = pic.Style
	}
	return out
}

// tileSlides: one slide per value of the strict time axes; with loose axes,
// per strict group first what every tile has, then each tile on its own way.
func tileSlides(p *Pool, o *orderer, pics []Pic, r Recipe, slots, strict, loose []string) []Slide {
	tiles := r.Frame.Tiles
	slot := index(slots)
	allAxes := append(append([]string{}, strict...), loose...)
	groups := groupBy(pics, func(pic Pic) string { return joinValues(p, pic, strict) })
	keys := o.sortedKeys(strict, groups)
	var out []Slide
	for _, gk := range keys {
		g := groups[gk]
		if len(loose) == 0 {
			// Strict: one slide per group, a tile per slot.
			s := Slide{Key: keyOf(p, g[0], strict), Tiles: make([]*TileRef, len(slots)), unit: gk}
			for _, pic := range g {
				if i, ok := slot[p.Value(pic, tiles)]; ok && s.Tiles[i] == nil {
					s.Tiles[i] = tileRef(pic)
				}
			}
			out = append(out, s)
			continue
		}
		// Loose: per slot, its pictures in loose-axis order.
		per := make([][]Pic, len(slots))
		for _, pic := range g {
			if i, ok := slot[p.Value(pic, tiles)]; ok {
				per[i] = append(per[i], pic)
			}
		}
		for i := range per {
			sort.SliceStable(per[i], func(a, b int) bool { return o.picLess(loose, per[i][a], per[i][b]) })
		}
		base := keyOf(p, g[0], strict)
		for _, row := range pairLoose(p, per, loose, r.Time.Pair) {
			s := Slide{Key: copyKey(base), Match: row.match, Tiles: make([]*TileRef, len(slots)), unit: gk + "\x1e" + fmt.Sprint(len(out))}
			for i, pic := range row.pics {
				if pic != nil {
					s.Tiles[i] = tileRef(*pic)
				}
			}
			if row.match == "exact" {
				for _, a := range loose {
					s.Key[a] = p.Value(*firstPic(row.pics), a)
				}
			}
			out = append(out, s)
		}
	}
	_ = allAxes
	return out
}

func copyKey(k map[string]string) map[string]string {
	out := make(map[string]string, len(k))
	for a, v := range k {
		out[a] = v
	}
	return out
}

func firstPic(ps []*Pic) *Pic {
	for _, p := range ps {
		if p != nil {
			return p
		}
	}
	return nil
}

type pairedRow struct {
	pics  []*Pic
	match string
}

// pairLoose lays loose values side by side. The ladder (plan §6c): values
// every slot has (exact), then the same style kind with the nearest year
// (kind), then whatever is left in order (order). pair: exact stops after the
// first rung, pair: order skips the second.
func pairLoose(p *Pool, per [][]Pic, loose []string, pair string) []pairedRow {
	n := len(per)
	key := func(pic Pic) string { return joinValues(p, pic, loose) }
	present := make([]map[string]int, n)
	for i := range per {
		present[i] = map[string]int{}
		for j, pic := range per[i] {
			present[i][key(pic)] = j
		}
	}
	used := make([]map[int]bool, n)
	for i := range used {
		used[i] = map[int]bool{}
	}
	var rows []pairedRow
	// 1. exact: in the first slot's order.
	if n > 0 {
		for _, pic := range per[0] {
			k := key(pic)
			all := true
			for i := 1; i < n; i++ {
				_, ok := present[i][k]
				all = all && ok
			}
			if !all {
				continue
			}
			row := pairedRow{pics: make([]*Pic, n), match: "exact"}
			for i := 0; i < n; i++ {
				j := present[i][k]
				row.pics[i] = &per[i][j]
				used[i][j] = true
			}
			rows = append(rows, row)
		}
	}
	if pair == "exact" {
		return rows
	}
	rest := make([][]int, n)
	for i := range per {
		for j := range per[i] {
			if !used[i][j] {
				rest[i] = append(rest[i], j)
			}
		}
	}
	// 2. kind: only for styles — kind by kind (in the order the first slot
	// meets them), while every slot still has an unused style of that kind,
	// the first slot's next one meets the nearest year in each other slot.
	if pair == "kind" && len(loose) == 1 && loose[0] == AxStyle && n > 0 {
		kindOf := func(i, j int) string { return p.styleMeta[per[i][j].Style].Kind }
		var kinds []string
		seenKind := map[string]bool{}
		for i := range rest {
			for _, j := range rest[i] {
				if k := kindOf(i, j); k != "" && !seenKind[k] {
					seenKind[k] = true
					kinds = append(kinds, k)
				}
			}
		}
		for _, kind := range kinds {
			for {
				picks := make([]int, n) // index into rest[i]
				ok := true
				lead := -1
				for idx, j := range rest[0] {
					if kindOf(0, j) == kind {
						lead, picks[0] = j, idx
						break
					}
				}
				if lead < 0 {
					break
				}
				for i := 1; i < n && ok; i++ {
					best, bestD := -1, 1<<30
					for idx, j := range rest[i] {
						if kindOf(i, j) != kind {
							continue
						}
						if d := yearDistance(p, per[0][lead].Style, per[i][j].Style); d < bestD {
							best, bestD = idx, d
						}
					}
					if best < 0 {
						ok = false
					}
					picks[i] = best
				}
				if !ok {
					break
				}
				row := pairedRow{pics: make([]*Pic, n), match: "kind"}
				for i := 0; i < n; i++ {
					j := rest[i][picks[i]]
					row.pics[i] = &per[i][j]
					rest[i] = append(rest[i][:picks[i]], rest[i][picks[i]+1:]...)
				}
				rows = append(rows, row)
			}
		}
	}
	// 3. order: what is left, side by side in each slot's order.
	longest := 0
	for i := range rest {
		if len(rest[i]) > longest {
			longest = len(rest[i])
		}
	}
	for k := 0; k < longest; k++ {
		row := pairedRow{pics: make([]*Pic, n), match: "order"}
		for i := 0; i < n; i++ {
			if k < len(rest[i]) {
				row.pics[i] = &per[i][rest[i][k]]
			}
		}
		rows = append(rows, row)
	}
	return rows
}

func yearDistance(p *Pool, a, b string) int {
	ya, yb := p.styleMeta[a].Year, p.styleMeta[b].Year
	if ya == nil || yb == nil {
		if a == b {
			return 0
		}
		return 1 << 20
	}
	d := *ya - *yb
	if d < 0 {
		d = -d
	}
	return d
}

// titleCaptions fills the slide's title and per-tile caption lines.
func titleCaptions(p *Pool, r *Recipe, s *Slide, timeAxes []string) {
	tiles := r.Frame.Tiles
	title := r.Frame.Title
	if title == "auto" {
		title = ""
		// The innermost strict time axis: what changes from slide to slide
		// and is shared by every tile.
		for i := len(timeAxes) - 1; i >= 0; i-- {
			a := timeAxes[i]
			if _, ok := s.Key[a]; ok && !contains(r.Time.Loose, a) && len(p.Values(a)) > 1 {
				title = a
				break
			}
		}
		if title == "" && len(timeAxes) > 0 {
			title = timeAxes[0]
		}
	}
	if title != "none" && title != "" {
		if v, ok := s.Key[title]; ok {
			s.Title = p.Label(title, v)
		}
	}
	var axes []string
	switch r.Frame.Captions.Mode {
	case "none":
		return
	case "auto":
		if tiles != "" {
			axes = append([]string{tiles}, r.Time.Loose...)
		} else {
			axes = []string{AxStyle, AxModel}
		}
	default:
		axes = r.Frame.Captions.Axes
	}
	s.Captions = make([][]string, len(s.Tiles))
	for i, t := range s.Tiles {
		if t == nil {
			continue
		}
		if t.Model == refSlot {
			s.Captions[i] = []string{"předloha"}
			continue
		}
		pic := Pic{Run: t.Run, Model: t.Model, Style: t.Style}
		for _, a := range axes {
			v, ok := s.Key[a]
			switch a {
			case AxModel:
				v, ok = pic.Model, true
			case AxStyle:
				v, ok = pic.Style, true
			case AxRun:
				v, ok = pic.Run, true
			}
			if ok {
				s.Captions[i] = append(s.Captions[i], p.Label(a, v))
			}
		}
	}
}

func contains(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

func captionLines(sb *Storyboard) int {
	n := 0
	for _, s := range sb.Slides {
		for _, c := range s.Captions {
			if len(c) > n {
				n = len(c)
			}
		}
	}
	return n
}

// shorten keeps an even selection of whole units within maxSeconds.
func shorten(slides []Slide, maxSeconds, rate float64) []Slide {
	if maxSeconds <= 0 || float64(len(slides))/rate <= maxSeconds {
		return slides
	}
	var units [][]Slide
	for _, s := range slides {
		if len(units) > 0 && units[len(units)-1][0].unit == s.unit {
			units[len(units)-1] = append(units[len(units)-1], s)
		} else {
			units = append(units, []Slide{s})
		}
	}
	per := len(slides) / len(units)
	keep := int(maxSeconds * rate / float64(max(1, per)))
	if keep < 1 {
		keep = 1
	}
	if keep >= len(units) {
		return slides
	}
	var out []Slide
	for i := 0; i < keep; i++ {
		j := 0
		if keep > 1 {
			j = (i*(len(units)-1) + (keep-1)/2) / (keep - 1)
		}
		out = append(out, units[j]...)
	}
	return out
}

// parts cuts slides [from, to) into files: whole, or with output.split at
// most N seconds each, only where the split axis changes.
func parts(name string, per map[string]string, slides []Slide, from, to int, r Recipe) []VideoPart {
	secs := func(a, b int) float64 { return float64(b-a) / r.Time.Rate }
	groupsIn := func(a, b int) []string {
		var g []string
		for i := a; i < b; i++ {
			if v := slides[i].group; v != "" && (len(g) == 0 || g[len(g)-1] != v) {
				g = append(g, v)
			}
		}
		return g
	}
	if r.Output.Split == nil || r.Time.Sync != nil { // sync: ApplySync cuts
		return []VideoPart{{Name: name, Per: per, From: from, To: to, Seconds: secs(from, to), Groups: groupsIn(from, to)}}
	}
	keys := make([]string, 0, to-from)
	for i := from; i < to; i++ {
		keys = append(keys, slides[i].group)
	}
	var out []VideoPart
	for i, pr := range SplitRanges(keys, 1/r.Time.Rate, r.Output.Split.Seconds) {
		a, b := from+pr[0], from+pr[1]
		out = append(out, VideoPart{Name: fmt.Sprintf("%s-%02d", name, i+1), Per: per, From: a, To: b,
			Seconds: secs(a, b), Groups: groupsIn(a, b)})
	}
	return out
}

// SplitRanges cuts a list of group keys into [start, end) ranges of at most
// limit seconds, only where the key changes: a group never spans two parts,
// one longer than the limit gets a part of its own.
func SplitRanges(keys []string, secondsEach, limit float64) [][2]int {
	var runs [][2]int
	for i, k := range keys {
		if len(runs) > 0 && keys[runs[len(runs)-1][0]] == k {
			runs[len(runs)-1][1] = i + 1
		} else {
			runs = append(runs, [2]int{i, i + 1})
		}
	}
	var parts [][2]int
	for _, r := range runs {
		if len(parts) > 0 && float64(r[1]-parts[len(parts)-1][0])*secondsEach <= limit+1e-9 {
			parts[len(parts)-1][1] = r[1]
		} else {
			parts = append(parts, r)
		}
	}
	return parts
}

func slug(s string) string {
	var b strings.Builder
	for _, c := range strings.ToLower(foldCzech(s)) {
		switch {
		case c >= 'a' && c <= 'z', c >= '0' && c <= '9', c == '-', c == '_', c == '.':
			b.WriteRune(c)
		default:
			b.WriteRune('-')
		}
	}
	out := strings.Trim(b.String(), "-")
	if out == "" {
		out = "x"
	}
	return out
}

// ErrNoPictures is returned when a plan ends up empty.
var ErrNoPictures = errors.New("žádný obrázek")
