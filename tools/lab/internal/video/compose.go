package video

import (
	"bytes"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"os"
	"path/filepath"
	"sync"

	xdraw "golang.org/x/image/draw"
)

// textMu serialises text drawing: font.Face is not safe for concurrent use.
var textMu sync.Mutex

// Colours of make_video.py, so the Go frames look like the Python ones.
var (
	colBackground = color.RGBA{16, 16, 18, 255}
	colTitleBox   = color.RGBA{40, 40, 44, 255}
	colEmptyTile  = color.RGBA{60, 60, 64, 255}
	colCaption1   = color.RGBA{210, 210, 210, 255}
	colCaption2   = color.RGBA{160, 160, 160, 255}
	colWhite      = color.RGBA{255, 255, 255, 255}
	colLabelBox   = color.RGBA{0, 0, 0, 150}
)

// Composer draws storyboard slides. Compose is safe for concurrent use: the
// pictures are decoded and scaled in parallel, text goes through textMu
// because font faces keep per-face buffers.
type Composer struct {
	LabDir string
	SB     *Storyboard
	// Thumbs draws from the 320 px thumbnails instead of the originals (quick
	// drafts and tests).
	Thumbs bool
}

// Compose draws slide i into a new RGBA image of the layout's size.
func (c *Composer) Compose(i int) (*image.RGBA, error) {
	l := c.SB.Layout
	if l == nil {
		return nil, fmt.Errorf("scénář nemá rozložení")
	}
	s := c.SB.Slides[i]
	dst := image.NewRGBA(image.Rect(0, 0, l.W, l.H))
	draw.Draw(dst, dst.Bounds(), image.NewUniform(colBackground), image.Point{}, draw.Src)

	pics := make([]image.Image, len(s.Tiles))
	errs := make([]error, len(s.Tiles))
	var wg sync.WaitGroup
	for k, t := range s.Tiles {
		if t == nil {
			continue
		}
		wg.Add(1)
		go func() {
			defer wg.Done()
			pics[k], errs[k] = c.load(t)
		}()
	}
	wg.Wait()
	for k, err := range errs {
		if err != nil {
			return nil, fmt.Errorf("%s: %w", s.Tiles[k].Img, err)
		}
	}

	if l.Single {
		textMu.Lock()
		defer textMu.Unlock()
		if pics[0] != nil {
			if c.SB.Recipe.Frame.Fit == "cover" {
				drawCover(dst, pics[0], dst.Bounds())
			} else {
				drawBlurredContain(dst, pics[0])
			}
		}
		if s.Title != "" && l.Title != nil {
			drawTitle(dst, l, s.Title)
		}
		if len(s.Captions) > 0 && len(s.Captions[0]) > 0 {
			drawLabelBox(dst, l, s.Captions[0])
		}
		return dst, nil
	}
	var wg2 sync.WaitGroup
	for k, box := range l.Tiles {
		if k >= len(pics) {
			break
		}
		r := image.Rect(box.Pic.X, box.Pic.Y, box.Pic.X+box.Pic.W, box.Pic.Y+box.Pic.H)
		if pics[k] == nil {
			strokeRect(dst, r, colEmptyTile, 2)
			continue
		}
		wg2.Add(1)
		go func(img image.Image, r image.Rectangle) {
			defer wg2.Done()
			drawContain(dst, img, r) // tiles do not overlap: parallel writes are disjoint
		}(pics[k], r)
	}
	wg2.Wait()
	textMu.Lock()
	defer textMu.Unlock()
	if s.Title != "" && l.Title != nil {
		drawTitle(dst, l, s.Title)
	}
	for k, box := range l.Tiles {
		if box.Caption == nil || k >= len(s.Tiles) {
			continue
		}
		var lines []string
		if k < len(s.Captions) {
			lines = s.Captions[k]
		}
		if len(lines) == 0 && s.Tiles[k] == nil && k < len(c.SB.Tiles) {
			lines = []string{c.SB.Tiles[k].Label}
		}
		drawCaption(dst, l, *box.Caption, lines, s.Tiles[k] == nil)
	}
	return dst, nil
}

func (c *Composer) load(t *TileRef) (image.Image, error) {
	rel := t.Img
	if c.Thumbs {
		rel = t.Thumb
	}
	// One read, then decode from memory: the PNG decoder pulls the file
	// through a 4 KB buffer, and on this disk each of those syscalls cost
	// more than the decoding (68 % of a render's CPU profile).
	data, err := os.ReadFile(filepath.Join(c.LabDir, filepath.FromSlash(rel)))
	if err != nil {
		return nil, err
	}
	img, _, err := image.Decode(bytes.NewReader(data))
	return img, err
}

// drawContain scales img to fit r (keeping its aspect) and centres it there.
func drawContain(dst draw.Image, img image.Image, r image.Rectangle) {
	b := img.Bounds()
	s := min(float64(r.Dx())/float64(b.Dx()), float64(r.Dy())/float64(b.Dy()))
	w, h := max(1, int(float64(b.Dx())*s+0.5)), max(1, int(float64(b.Dy())*s+0.5))
	x := r.Min.X + (r.Dx()-w)/2
	y := r.Min.Y + (r.Dy()-h)/2
	xdraw.BiLinear.Scale(dst, image.Rect(x, y, x+w, y+h), img, b, draw.Src, nil)
}

// drawCover scales img to cover r and crops the overflow.
func drawCover(dst draw.Image, img image.Image, r image.Rectangle) {
	b := img.Bounds()
	s := max(float64(r.Dx())/float64(b.Dx()), float64(r.Dy())/float64(b.Dy()))
	sw, sh := float64(r.Dx())/s, float64(r.Dy())/s
	src := image.Rect(
		b.Min.X+int((float64(b.Dx())-sw)/2), b.Min.Y+int((float64(b.Dy())-sh)/2),
		b.Min.X+int((float64(b.Dx())+sw)/2), b.Min.Y+int((float64(b.Dy())+sh)/2))
	xdraw.CatmullRom.Scale(dst, r, img, src, draw.Src, nil)
}

// drawBlurredContain: the whole picture over a blurred, darkened copy of
// itself — no black bars on 9:16.
func drawBlurredContain(dst *image.RGBA, img image.Image) {
	r := dst.Bounds()
	// Blur by going down to 1/16 and back up.
	small := image.NewRGBA(image.Rect(0, 0, max(1, r.Dx()/16), max(1, r.Dy()/16)))
	b := img.Bounds()
	s := max(float64(small.Bounds().Dx())/float64(b.Dx()), float64(small.Bounds().Dy())/float64(b.Dy()))
	sw, sh := float64(small.Bounds().Dx())/s, float64(small.Bounds().Dy())/s
	src := image.Rect(b.Min.X+int((float64(b.Dx())-sw)/2), b.Min.Y+int((float64(b.Dy())-sh)/2),
		b.Min.X+int((float64(b.Dx())+sw)/2), b.Min.Y+int((float64(b.Dy())+sh)/2))
	xdraw.ApproxBiLinear.Scale(small, small.Bounds(), img, src, draw.Src, nil)
	xdraw.ApproxBiLinear.Scale(dst, r, small, small.Bounds(), draw.Src, nil)
	for i := 0; i < len(dst.Pix); i += 4 {
		dst.Pix[i] = uint8(int(dst.Pix[i]) * 45 / 100)
		dst.Pix[i+1] = uint8(int(dst.Pix[i+1]) * 45 / 100)
		dst.Pix[i+2] = uint8(int(dst.Pix[i+2]) * 45 / 100)
	}
	drawContain(dst, img, r)
}

func drawTitle(dst *image.RGBA, l *Layout, title string) {
	f := face(l.TitleSize, true)
	maxW := l.Title.W - 4*l.Pad
	lines := fitLines(f, wrapText(f, title, maxW), 2, maxW)
	lh := lineHeight(l.TitleSize)
	gap := l.Pad * 2 / 5
	bh := lh*len(lines) + gap*(len(lines)-1) + 2*l.Pad
	y0 := l.Title.Y + (l.Title.H-bh)/2
	fillRoundRect(dst, image.Rect(l.Title.X, y0, l.Title.X+l.Title.W, y0+bh), l.Pad, colTitleBox)
	y := y0 + l.Pad
	for _, line := range lines {
		drawText(dst, f, (l.W-textWidth(f, line))/2, y, l.TitleSize, line, colWhite)
		y += lh + gap
	}
}

// drawCaption: the first line full size, the others a step smaller, each
// shrunk until it fits the tile.
func drawCaption(dst *image.RGBA, l *Layout, r Rect, lines []string, empty bool) {
	y := r.Y
	for j, line := range lines {
		size := l.CaptionSize
		col := colCaption1
		if j > 0 {
			size, col = l.CaptionSize2, colCaption2
		}
		if empty {
			col = color.RGBA{110, 110, 110, 255}
		}
		f := shrinkToFit(line, size, 12, r.W-l.Pad/2, false)
		drawText(dst, f, r.X+(r.W-textWidth(f, line))/2, y, size, line, col)
		y += lineHeight(size)
	}
}

// drawLabelBox: the single-picture label of make_video.py — the first line
// (style) larger and wrapped, the rest (model) smaller, on a dark box below
// the platform tabs.
func drawLabelBox(dst *image.RGBA, l *Layout, lines []string) {
	big := int(float64(l.W)*0.042 + 0.5)
	small := int(float64(l.W)*0.03 + 0.5)
	type row struct {
		text string
		size int
		col  color.RGBA
	}
	var rows []row
	maxW := l.W - 6*l.Pad
	fb := face(big, true)
	for i, line := range lines {
		if i == 0 {
			for _, w := range wrapText(fb, line, maxW) {
				rows = append(rows, row{w, big, colWhite})
			}
		} else {
			rows = append(rows, row{line, small, color.RGBA{220, 220, 220, 255}})
		}
	}
	bw := 0
	bh := 2 * l.Pad
	for _, r := range rows {
		bw = max(bw, textWidth(face(r.size, r.size == big), r.text))
		bh += lineHeight(r.size)
	}
	bw += 2 * l.Pad
	x0 := (l.W - bw) / 2
	box := image.Rect(x0, l.CaptionTop, x0+bw, l.CaptionTop+bh)
	fillRoundRectOver(dst, box, l.Pad, colLabelBox)
	y := l.CaptionTop + l.Pad
	for _, r := range rows {
		f := face(r.size, r.size == big)
		drawText(dst, f, (l.W-textWidth(f, r.text))/2, y, r.size, r.text, r.col)
		y += lineHeight(r.size)
	}
}

func strokeRect(dst *image.RGBA, r image.Rectangle, c color.RGBA, w int) {
	u := image.NewUniform(c)
	draw.Draw(dst, image.Rect(r.Min.X, r.Min.Y, r.Max.X, r.Min.Y+w), u, image.Point{}, draw.Src)
	draw.Draw(dst, image.Rect(r.Min.X, r.Max.Y-w, r.Max.X, r.Max.Y), u, image.Point{}, draw.Src)
	draw.Draw(dst, image.Rect(r.Min.X, r.Min.Y, r.Min.X+w, r.Max.Y), u, image.Point{}, draw.Src)
	draw.Draw(dst, image.Rect(r.Max.X-w, r.Min.Y, r.Max.X, r.Max.Y), u, image.Point{}, draw.Src)
}

// fillRoundRect fills an opaque rectangle with rounded corners.
func fillRoundRect(dst *image.RGBA, r image.Rectangle, rad int, c color.RGBA) {
	roundRect(dst, r, rad, func(x, y int) { dst.SetRGBA(x, y, c) })
}

// fillRoundRectOver blends a translucent rounded rectangle over dst.
func fillRoundRectOver(dst *image.RGBA, r image.Rectangle, rad int, c color.RGBA) {
	a := int(c.A)
	roundRect(dst, r, rad, func(x, y int) {
		i := dst.PixOffset(x, y)
		for ch, v := range []uint8{c.R, c.G, c.B} {
			dst.Pix[i+ch] = uint8((int(dst.Pix[i+ch])*(255-a) + int(v)*a) / 255)
		}
	})
}

func roundRect(dst *image.RGBA, r image.Rectangle, rad int, set func(x, y int)) {
	r = r.Intersect(dst.Bounds())
	rad = min(rad, r.Dx()/2, r.Dy()/2)
	for y := r.Min.Y; y < r.Max.Y; y++ {
		for x := r.Min.X; x < r.Max.X; x++ {
			cx, cy := 0, 0
			switch {
			case x < r.Min.X+rad:
				cx = r.Min.X + rad - x
			case x >= r.Max.X-rad:
				cx = x - (r.Max.X - rad - 1)
			}
			switch {
			case y < r.Min.Y+rad:
				cy = r.Min.Y + rad - y
			case y >= r.Max.Y-rad:
				cy = y - (r.Max.Y - rad - 1)
			}
			if cx*cx+cy*cy > rad*rad {
				continue
			}
			set(x, y)
		}
	}
}
