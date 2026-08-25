package main

import (
	"bytes"
	"image"
	"math"
	"sort"
)

// Histogram is a 512-bin RGB histogram (8 levels per channel) of a downscaled
// image — the same measure the style matrix was calibrated with, so numbers
// from the lab and from docs/style-matrix.md stay comparable.
func Histogram(data []byte) ([]float64, error) {
	img, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	b := img.Bounds()
	const side = 96
	h := make([]float64, 512)
	n := 0.0
	for y := 0; y < side; y++ {
		for x := 0; x < side; x++ {
			sx := b.Min.X + x*b.Dx()/side
			sy := b.Min.Y + y*b.Dy()/side
			r, g, bb, _ := img.At(sx, sy).RGBA()
			h[(r>>13)*64+(g>>13)*8+(bb>>13)]++
			n++
		}
	}
	for i := range h {
		h[i] /= n
	}
	return h, nil
}

// CosDist is 1 - cosine similarity: 0 = identical palettes, 1 = nothing shared.
func CosDist(a, b []float64) float64 {
	var num, da, db float64
	for i := range a {
		num += a[i] * b[i]
		da += a[i] * a[i]
		db += b[i] * b[i]
	}
	if da == 0 || db == 0 {
		return 1
	}
	return 1 - num/(math.Sqrt(da)*math.Sqrt(db))
}

type CellMetric struct {
	// Reaction is the distance from this group's style-less baseline: "did the
	// style block change anything at all for this model".
	Reaction *float64 `json:"reaction,omitempty"`
	// NeighbourDelta is the distance from the previous sweep value — the number
	// that answers "did that knob do anything".
	NeighbourDelta *float64 `json:"neighbourDelta,omitempty"`
}

type GroupMetric struct {
	// Spread is the mean pairwise distance among the styles of one
	// (flow, model, prompt) group. Low = the model ignores style blocks.
	Spread float64 `json:"spread"`
	N      int     `json:"n"`
}

type Metrics struct {
	Cells  map[string]CellMetric  `json:"cells"`
	Groups map[string]GroupMetric `json:"groups"`
	// Note is shown next to the numbers; without it they get over-read.
	Note string `json:"note"`
}

// ComputeMetrics needs the histogram of every finished cell plus the manifest
// rows, and groups strictly by manifest fields — filenames are not parsed.
func ComputeMetrics(cells []ManifestCell, hist map[string][]float64) Metrics {
	m := Metrics{
		Cells:  map[string]CellMetric{},
		Groups: map[string]GroupMetric{},
		Note: "Metriky měří barvu, ne převzetí stylu: slouží k předvýběru, " +
			"rozhodnout musí pohled na obrázky.",
	}
	type key struct {
		flow, model, variant string
		prompt               int
	}
	groups := map[key][]ManifestCell{}
	for _, c := range cells {
		if _, ok := hist[c.ID]; !ok {
			continue
		}
		v := ""
		if c.Variant != nil {
			v = c.Variant.Label + "=" + c.Variant.Value
		}
		k := key{c.Flow, c.Model, v, c.PromptIndex}
		groups[k] = append(groups[k], c)
	}

	for k, list := range groups {
		var baseline []float64
		var styled [][]float64
		for _, c := range list {
			if c.Style == "__baseline" {
				baseline = hist[c.ID]
				continue
			}
			styled = append(styled, hist[c.ID])
		}
		for _, c := range list {
			cm := m.Cells[c.ID]
			if baseline != nil && c.Style != "__baseline" {
				d := CosDist(baseline, hist[c.ID])
				cm.Reaction = &d
			}
			m.Cells[c.ID] = cm
		}
		if len(styled) > 1 {
			var sum float64
			var n int
			for i := range styled {
				for j := i + 1; j < len(styled); j++ {
					sum += CosDist(styled[i], styled[j])
					n++
				}
			}
			m.Groups[groupKey(k.flow, k.model, k.prompt, k.variant)] =
				GroupMetric{Spread: sum / float64(n), N: len(styled)}
		}
	}

	// Sweep neighbours: same cell in every respect but the variant value, in
	// the order the sweep was declared.
	type sweepKey struct {
		flow, model, style string
		prompt             int
	}
	sweeps := map[sweepKey][]ManifestCell{}
	for _, c := range cells {
		if c.Variant == nil {
			continue
		}
		if _, ok := hist[c.ID]; !ok {
			continue
		}
		k := sweepKey{c.Flow, c.Model, c.Style, c.PromptIndex}
		sweeps[k] = append(sweeps[k], c)
	}
	for _, list := range sweeps {
		sort.SliceStable(list, func(i, j int) bool {
			return list[i].Variant.Order < list[j].Variant.Order
		})
		for i := 1; i < len(list); i++ {
			d := CosDist(hist[list[i-1].ID], hist[list[i].ID])
			cm := m.Cells[list[i].ID]
			cm.NeighbourDelta = &d
			m.Cells[list[i].ID] = cm
		}
	}
	return m
}

func groupKey(flow, model string, prompt int, variant string) string {
	k := flow + "|" + model + "|p" + itoa(prompt)
	if variant != "" {
		k += "|" + variant
	}
	return k
}

func itoa(i int) string {
	if i == 0 {
		return "0"
	}
	var b [8]byte
	p := len(b)
	for i > 0 {
		p--
		b[p] = byte('0' + i%10)
		i /= 10
	}
	return string(b[p:])
}
