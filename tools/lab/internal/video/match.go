package video

import (
	"fmt"
	"math/bits"
	"sort"
	"strings"
)

// Coverage is a rows × cols matrix: in each cell, how many distinct values of
// the count axis have a picture (typically model × style, counted in prompts).
type Coverage struct {
	RowAxis   string     `json:"rowAxis"`
	ColAxis   string     `json:"colAxis"`
	CountAxis string     `json:"countAxis"`
	Rows      []Labelled `json:"rows"`
	Cols      []Labelled `json:"cols"`
	Cells     [][]int    `json:"cells"`
	// Of is the number of count-axis values in the whole selection — what a
	// full cell would say.
	Of int `json:"of"`
}

// Labelled is an axis value with its label (and for styles their kind).
type Labelled struct {
	ID    string `json:"id"`
	Label string `json:"label"`
	Kind  string `json:"kind,omitempty"`
	N     int    `json:"n,omitempty"`
}

// Coverage counts, per (row, col), the distinct count-axis values with a picture.
func (p *Pool) Coverage(rows, cols, count string) (*Coverage, error) {
	for _, a := range []string{rows, cols, count} {
		if !IsAxis(a) {
			return nil, fmt.Errorf("neznámá osa %q", a)
		}
	}
	if rows == cols {
		return nil, fmt.Errorf("řádky a sloupce musí být různé osy")
	}
	rv, cv := p.Values(rows), p.Values(cols)
	ri, ci := index(rv), index(cv)
	seen := map[[3]string]bool{}
	cov := &Coverage{RowAxis: rows, ColAxis: cols, CountAxis: count, Of: len(p.Values(count))}
	cov.Cells = make([][]int, len(rv))
	for i := range cov.Cells {
		cov.Cells[i] = make([]int, len(cv))
	}
	for _, pic := range p.Pics {
		r, c, n := p.Value(pic, rows), p.Value(pic, cols), p.Value(pic, count)
		k := [3]string{r, c, n}
		if seen[k] {
			continue
		}
		seen[k] = true
		cov.Cells[ri[r]][ci[c]]++
	}
	cov.Rows, cov.Cols = p.labelled(rows, rv), p.labelled(cols, cv)
	return cov, nil
}

func (p *Pool) labelled(axis string, vals []string) []Labelled {
	out := make([]Labelled, len(vals))
	for i, v := range vals {
		out[i] = Labelled{ID: v, Label: p.Label(axis, v)}
		if axis == AxStyle {
			out[i].Kind = p.styleMeta[v].Kind
		}
	}
	return out
}

func index(vals []string) map[string]int {
	m := make(map[string]int, len(vals))
	for i, v := range vals {
		m[v] = i
	}
	return m
}

// Suggestion is a set of tile values (typically models) and how many slides
// they fill completely.
type Suggestion struct {
	Values []string `json:"values"`
	Labels []string `json:"labels"`
	// Strict: slides where every tile has the same values on every other
	// content axis (same prompt and style). Loose: slides where the loose axes
	// may differ between tiles (same prompt, each model its own style) — the
	// count a MIX video with complete slides would have.
	Strict int `json:"strict"`
	Loose  int `json:"loose"`
}

// Suggestions lists, per number of tiles k, the best sets by strict and by
// loose completeness.
type Suggestions struct {
	Tiles   string               `json:"tiles"`
	Loose   []string             `json:"loose"`
	Values  []Labelled           `json:"values"`
	ByK     map[int][]Suggestion `json:"byK"`
	ByLoose map[int][]Suggestion `json:"byLoose"`
	Note    string               `json:"note,omitempty"`
	order   []int
}

// maxSuggestValues bounds the subset search: 2^16 sets of tile values.
const maxSuggestValues = 16

// Suggest finds which values of the tiles axis to put side by side. loose
// names the axes that may differ between tiles (usually style).
func (p *Pool) Suggest(tiles string, loose []string, kmax, top int) (*Suggestions, error) {
	if !IsAxis(tiles) {
		return nil, fmt.Errorf("neznámá osa %q", tiles)
	}
	isLoose := map[string]bool{}
	for _, a := range loose {
		if !IsAxis(a) {
			return nil, fmt.Errorf("neznámá osa %q", a)
		}
		if a == tiles {
			return nil, fmt.Errorf("osa dlaždic nemůže být zároveň volná")
		}
		isLoose[a] = true
	}
	vals := p.Values(tiles)
	res := &Suggestions{Tiles: tiles, Loose: loose, ByK: map[int][]Suggestion{}, ByLoose: map[int][]Suggestion{}}
	if len(vals) > maxSuggestValues {
		// Keep the values with the most pictures; say so.
		count := map[string]int{}
		for _, pic := range p.Pics {
			count[p.Value(pic, tiles)]++
		}
		sort.SliceStable(vals, func(i, j int) bool { return count[vals[i]] > count[vals[j]] })
		res.Note = fmt.Sprintf("hodnot osy %s je %d, návrhy berou %d s nejvíc obrázky", tiles, len(vals), maxSuggestValues)
		vals = vals[:maxSuggestValues]
	}
	vi := index(vals)
	for _, v := range vals {
		n := 0
		for _, pic := range p.Pics {
			if p.Value(pic, tiles) == v {
				n++
			}
		}
		res.Values = append(res.Values, Labelled{ID: v, Label: p.Label(tiles, v), N: n})
	}

	// Strict: a mask of tile values per slide key, histogrammed by mask.
	strictMask := map[string]uint32{}
	// Loose: per loose key, per tile value, how many distinct loose values.
	looseCount := map[string][]int{}
	looseSeen := map[string]bool{}
	for _, pic := range p.Pics {
		t, ok := vi[p.Value(pic, tiles)]
		if !ok {
			continue
		}
		var sk, lk, lv []string
		for _, a := range ContentAxes {
			if a == tiles {
				continue
			}
			v := p.Value(pic, a)
			sk = append(sk, v)
			if isLoose[a] {
				lv = append(lv, v)
			} else {
				lk = append(lk, v)
			}
		}
		strictMask[strings.Join(sk, "|")] |= 1 << t
		lkey := strings.Join(lk, "|")
		seenKey := lkey + "\x00" + strings.Join(lv, "|") + "\x00" + vals[t]
		if !looseSeen[seenKey] {
			looseSeen[seenKey] = true
			if looseCount[lkey] == nil {
				looseCount[lkey] = make([]int, len(vals))
			}
			looseCount[lkey][t]++
		}
	}
	masks := map[uint32]int{}
	for _, m := range strictMask {
		masks[m]++
	}
	n := len(vals)
	if kmax <= 0 || kmax > n {
		kmax = n
	}
	if top <= 0 {
		top = 3
	}
	all := map[int][]Suggestion{}
	for s := uint32(1); s < 1<<n; s++ {
		k := bits.OnesCount32(s)
		if k < 2 || k > kmax {
			continue
		}
		strict := 0
		for m, c := range masks {
			if m&s == s {
				strict += c
			}
		}
		looseN := 0
		for _, counts := range looseCount {
			min := -1
			for t := 0; t < n; t++ {
				if s&(1<<t) == 0 {
					continue
				}
				if min < 0 || counts[t] < min {
					min = counts[t]
				}
			}
			if min > 0 {
				looseN += min
			}
		}
		if strict == 0 && looseN == 0 {
			continue
		}
		sg := Suggestion{Strict: strict, Loose: looseN}
		for t := 0; t < n; t++ {
			if s&(1<<t) != 0 {
				sg.Values = append(sg.Values, vals[t])
				sg.Labels = append(sg.Labels, p.Label(tiles, vals[t]))
			}
		}
		all[k] = append(all[k], sg)
	}
	for k, list := range all {
		byStrict := append([]Suggestion{}, list...)
		sort.SliceStable(byStrict, func(i, j int) bool {
			if byStrict[i].Strict != byStrict[j].Strict {
				return byStrict[i].Strict > byStrict[j].Strict
			}
			return byStrict[i].Loose > byStrict[j].Loose
		})
		byLoose := append([]Suggestion{}, list...)
		sort.SliceStable(byLoose, func(i, j int) bool {
			if byLoose[i].Loose != byLoose[j].Loose {
				return byLoose[i].Loose > byLoose[j].Loose
			}
			return byLoose[i].Strict > byLoose[j].Strict
		})
		res.ByK[k] = head(byStrict, top)
		res.ByLoose[k] = head(byLoose, top)
		res.order = append(res.order, k)
	}
	sort.Ints(res.order)
	return res, nil
}

// Ks lists the tile counts that have suggestions, ascending.
func (s *Suggestions) Ks() []int { return s.order }

func head(list []Suggestion, n int) []Suggestion {
	if len(list) > n {
		return list[:n]
	}
	return list
}
