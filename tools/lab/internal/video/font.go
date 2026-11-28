package video

import (
	"image"
	"image/color"
	"image/draw"
	"strings"
	"sync"

	"golang.org/x/image/font"
	"golang.org/x/image/font/gofont/gomedium"
	"golang.org/x/image/font/gofont/goregular"
	"golang.org/x/image/font/opentype"
	"golang.org/x/image/math/fixed"
)

// Text is set in the Go fonts, compiled into the binary: the video looks the
// same on every machine and does not depend on what the system has. Both
// cover WGL4, i.e. Czech and the „—“, „·“, „…“ the labels use (font_test.go).

var (
	fontOnce              sync.Once
	fontRegular, fontBold *opentype.Font
	faceMu                sync.Mutex
	faces                 = map[faceKey]font.Face{}
)

type faceKey struct {
	bold bool
	size int
}

func loadFonts() {
	fontRegular, _ = opentype.Parse(goregular.TTF)
	fontBold, _ = opentype.Parse(gomedium.TTF)
}

// face returns a cached face of the given pixel size.
func face(size int, bold bool) font.Face {
	fontOnce.Do(loadFonts)
	faceMu.Lock()
	defer faceMu.Unlock()
	k := faceKey{bold, size}
	if f, ok := faces[k]; ok {
		return f
	}
	src := fontRegular
	if bold {
		src = fontBold
	}
	f, err := opentype.NewFace(src, &opentype.FaceOptions{Size: float64(size), DPI: 72, Hinting: font.HintingFull})
	if err != nil {
		panic(err) // the fonts are compiled in; this cannot fail on input
	}
	faces[k] = f
	return f
}

// textWidth in pixels.
func textWidth(f font.Face, s string) int { return font.MeasureString(f, s).Ceil() }

// wrapText breaks s into lines no wider than maxW.
func wrapText(f font.Face, s string, maxW int) []string {
	var lines []string
	for _, word := range strings.Fields(s) {
		if n := len(lines); n > 0 && textWidth(f, lines[n-1]+" "+word) <= maxW {
			lines[n-1] += " " + word
		} else {
			lines = append(lines, word)
		}
	}
	return lines
}

// fitLines keeps at most n lines; the last one ends in an ellipsis when cut.
func fitLines(f font.Face, lines []string, n, maxW int) []string {
	if len(lines) <= n {
		return lines
	}
	out := append([]string{}, lines[:n-1]...)
	last := strings.Join(lines[n-1:], " ")
	for textWidth(f, last+"…") > maxW && strings.Contains(last, " ") {
		last = last[:strings.LastIndex(last, " ")]
	}
	return append(out, last+"…")
}

// shrinkToFit returns the largest size ≤ size (down to min) at which s fits.
func shrinkToFit(s string, size, min, maxW int, bold bool) font.Face {
	for ; size > min; size-- {
		if f := face(size, bold); textWidth(f, s) <= maxW {
			return f
		}
	}
	return face(min, bold)
}

// drawText draws s with its top-left at (x, y): y is the top of the line box
// of lineHeight(size), the baseline sits at the font's ascent within it.
func drawText(dst draw.Image, f font.Face, x, y, size int, s string, c color.Color) {
	m := f.Metrics()
	lh := lineHeight(size)
	asc := m.Ascent.Ceil()
	desc := m.Descent.Ceil()
	base := y + (lh-(asc+desc))/2 + asc
	d := font.Drawer{Dst: dst, Src: image.NewUniform(c), Face: f, Dot: fixed.P(x, base)}
	d.DrawString(s)
}

// hasGlyphs reports whether the face can draw every rune of s.
func hasGlyphs(f font.Face, s string) bool {
	for _, r := range s {
		if r == ' ' {
			continue
		}
		if _, ok := f.GlyphAdvance(r); !ok {
			return false
		}
	}
	return true
}
