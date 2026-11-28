package video

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestTourFollowsALine(t *testing.T) {
	xs := []float64{5, 1, 7, 3, 0, 6, 2, 4}
	d := make([][]float64, len(xs))
	for i := range d {
		d[i] = make([]float64, len(xs))
		for j := range d[i] {
			d[i][j] = math.Abs(xs[i] - xs[j])
		}
	}
	o := tour(d)
	dir := xs[o[1]] - xs[o[0]]
	for k := 1; k < len(o); k++ {
		if (xs[o[k]]-xs[o[k-1]])*dir <= 0 || math.Abs(xs[o[k]]-xs[o[k-1]]) != 1 {
			t.Fatalf("trasa má jít po přímce: %v", o)
		}
	}
}

// Eight styles, each picture a red/blue mix with k/7 red; the picker order is
// shuffled, smooth must bring the gradient back.
func TestOrderSmoothSortsByLook(t *testing.T) {
	lab := t.TempDir()
	ids := []string{"s3", "s0", "s6", "s1", "s7", "s2", "s5", "s4"}
	var styles []StyleMeta
	var cells []fakeCell
	for _, s := range ids {
		styles = append(styles, StyleMeta{ID: s, Label: s})
		cells = append(cells, fakeCell{model: "m", style: s})
	}
	writeRun(t, lab, fakeRun{id: "20990101-000001", status: "done", styles: styles, cells: cells})
	col := mustLoad(t, lab)
	for _, pic := range col.Run("20990101-000001").Pics {
		k := int(pic.Style[1] - '0')
		img := image.NewRGBA(image.Rect(0, 0, 70, 10))
		for x := 0; x < 70; x++ {
			c := color.RGBA{0, 0, 255, 255}
			if x < k*10 {
				c = color.RGBA{255, 0, 0, 255}
			}
			for y := 0; y < 10; y++ {
				img.Set(x, y, c)
			}
		}
		var buf bytes.Buffer
		_ = png.Encode(&buf, img)
		if err := os.WriteFile(filepath.Join(lab, pic.Run, "img", pic.Cell+".png"), buf.Bytes(), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	sb := mustPlan(t, col, "source: {runs: [20990101-000001]}\ntime: {axes: [style], order: {style: smooth}}\n")
	var got []string
	for _, s := range sb.Slides {
		got = append(got, s.Key[AxStyle])
	}
	seq := strings.Join(got, " ")
	if seq != "s0 s1 s2 s3 s4 s5 s6 s7" && seq != "s7 s6 s5 s4 s3 s2 s1 s0" {
		t.Fatalf("plynulé pořadí: %s", seq)
	}
	if in := sb.Smooth[AxStyle]; in.Values != 8 || in.After >= in.Before {
		t.Fatalf("skok má klesnout: %+v", in)
	}
	if _, err := os.Stat(filepath.Join(lab, "_video", ".index", "hist-20990101-000001.gob")); err != nil {
		t.Fatal("histogramy se mají uložit do cache")
	}
}
