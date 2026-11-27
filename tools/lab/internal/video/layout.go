package video

import (
	"fmt"
	"image"
	_ "image/jpeg" // lab pictures from gen-queue are JPEG under .png names
	_ "image/png"
	"math"
	"os"
	"path/filepath"
)

// Layout is the geometry of a frame. The storyboard carries it, so the
// browser preview places thumbnails into the very rectangles the renderer
// draws into — the two cannot disagree. Proportions follow make_video.py:
// a margin of 2 % of the width, the TikTok/Shorts tabs above 8.5 % of the
// height, their caption below 88 %.
type Layout struct {
	W     int `json:"w"`
	H     int `json:"h"`
	Cols  int `json:"cols"`
	Rows  int `json:"rows"`
	Pad   int `json:"pad"`
	TileW int `json:"tileW"`
	TileH int `json:"tileH"`
	// Title is the title band (always two lines tall, so the grid does not
	// jump when a long name wraps); nil without a title.
	Title     *Rect `json:"title,omitempty"`
	TitleSize int   `json:"titleSize"`
	// Tiles: picture box and caption box per tile slot. Without tiles there
	// is one entry covering the frame.
	Tiles []TileBox `json:"tiles"`
	// CaptionSize is the first caption line, CaptionSize2 the following ones.
	CaptionSize  int `json:"captionSize"`
	CaptionSize2 int `json:"captionSize2"`
	LineHeight   int `json:"lineHeight"`
	// Single: one picture per frame (contain over a blurred copy, or cover);
	// its caption box hangs at CaptionTop.
	Single     bool `json:"single"`
	CaptionTop int  `json:"captionTop"`
}

type Rect struct {
	X int `json:"x"`
	Y int `json:"y"`
	W int `json:"w"`
	H int `json:"h"`
}

type TileBox struct {
	Pic     Rect  `json:"pic"`
	Caption *Rect `json:"caption,omitempty"`
}

// lineHeight of text set in size px: the renderer uses the same ratio.
func lineHeight(size int) int { return int(math.Round(float64(size) * 1.22)) }

// ComputeLayout places n tile slots (0 = one picture per frame) of pictures
// with the given aspect (w/h) on a w×h frame. cols 0 picks the split that
// makes the pictures largest.
func ComputeLayout(w, h, n, cols int, aspect float64, title bool, captionLines int, tiles bool) Layout {
	if aspect <= 0 {
		aspect = 1
	}
	pad := int(math.Round(float64(w) * 0.02))
	l := Layout{W: w, H: h, Pad: pad,
		TitleSize:    int(math.Round(float64(w) * 0.042)),
		CaptionSize:  int(math.Round(float64(w) * 0.026)),
		CaptionSize2: int(math.Round(float64(w) * 0.021)),
	}
	l.LineHeight = lineHeight(l.CaptionSize)
	top := int(math.Round(float64(h) * 0.085))
	bottom := int(math.Round(float64(h) * 0.88))
	if title {
		th := lineHeight(l.TitleSize)
		band := 2*th + int(math.Round(float64(pad)*0.4)) + 2*pad
		l.Title = &Rect{X: pad, Y: top, W: w - 2*pad, H: band}
		top += band + pad
	}
	if !tiles || n == 0 {
		l.Single, l.Cols, l.Rows = true, 1, 1
		l.CaptionTop = int(math.Round(float64(h) * 0.12))
		l.Tiles = []TileBox{{Pic: Rect{0, 0, w, h}}}
		l.TileW, l.TileH = w, h
		return l
	}
	capH := 0
	if captionLines > 0 {
		capH = l.LineHeight + (captionLines-1)*lineHeight(l.CaptionSize2) + pad/2
	}
	place := func(c int) (pw, ph float64, rows int) {
		rows = (n + c - 1) / c
		tw := float64(w-pad) / float64(c)
		th := float64(bottom-top) / float64(rows)
		pw = math.Min(tw-float64(pad), (th-float64(pad)-float64(capH))*aspect)
		return pw, pw / aspect, rows
	}
	if cols <= 0 {
		best := -1.0
		for c := 1; c <= n; c++ {
			if pw, ph, _ := place(c); pw > 0 && pw*ph > best {
				best, cols = pw*ph, c
			}
		}
	}
	if cols > n {
		cols = n
	}
	pw, ph, rows := place(cols)
	if pw < 1 {
		pw, ph = 1, 1/aspect
	}
	l.Cols, l.Rows = cols, rows
	l.TileW, l.TileH = int(pw), int(ph)
	tw := float64(w-pad) / float64(cols)
	cellH := ph + float64(capH) + float64(pad)
	yStart := float64(top) + (float64(bottom-top)-float64(rows)*cellH)/2
	for k := 0; k < n; k++ {
		r, c := k/cols, k%cols
		x := float64(pad)/2 + float64(c)*tw + (tw-pw)/2
		y := yStart + float64(r)*cellH + float64(pad)/2
		box := TileBox{Pic: Rect{int(math.Round(x)), int(math.Round(y)), int(pw), int(ph)}}
		if capH > 0 {
			box.Caption = &Rect{
				X: int(math.Round(float64(pad)/2 + float64(c)*tw)), Y: int(math.Round(y + ph + float64(pad)/4)),
				W: int(tw), H: capH,
			}
		}
		l.Tiles = append(l.Tiles, box)
	}
	return l
}

// commonAspect is the most common width/height of the pool's pictures, read
// from the header of one picture per (run, model, flow).
func commonAspect(col *Collection, p *Pool) float64 {
	count := map[float64]int{}
	seen := map[string]bool{}
	for _, pic := range p.Pics {
		k := pic.Run + "|" + pic.Model + "|" + pic.Flow
		if seen[k] {
			continue
		}
		seen[k] = true
		r := col.Run(pic.Run)
		if r == nil {
			continue
		}
		if a, err := imageAspect(filepath.Join(r.Dir, "img", pic.Cell+".png")); err == nil {
			count[math.Round(a*1000)/1000]++
		}
	}
	best, bestN := 1.0, -1
	for a, n := range count {
		if n > bestN || (n == bestN && a < best) {
			best, bestN = a, n
		}
	}
	return best
}

func imageAspect(path string) (float64, error) {
	f, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer f.Close()
	cfg, _, err := image.DecodeConfig(f)
	if err != nil {
		return 0, err
	}
	if cfg.Height == 0 {
		return 0, fmt.Errorf("výška 0")
	}
	return float64(cfg.Width) / float64(cfg.Height), nil
}
