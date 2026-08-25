package main

import (
	"bytes"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	_ "image/png"
	"math"
	"os"
)

// thumbMax is the long edge of a grid thumbnail. A 400-cell page of full
// 832×1216 PNGs is ~600 MB down the socket; as thumbnails it is single-digit MB.
const thumbMax = 320

// Thumbnail downscales with a box filter — for downscaling only, it is both
// correct and dependency-free, which keeps this tool on the Go stdlib.
func Thumbnail(src []byte, max int) ([]byte, error) {
	img, _, err := image.Decode(bytes.NewReader(src))
	if err != nil {
		return nil, fmt.Errorf("dekódování obrázku: %w", err)
	}
	b := img.Bounds()
	scale := float64(max) / float64(maxInt(b.Dx(), b.Dy()))
	if scale >= 1 {
		var buf bytes.Buffer
		if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 82}); err != nil {
			return nil, err
		}
		return buf.Bytes(), nil
	}
	w := maxInt(1, int(float64(b.Dx())*scale))
	h := maxInt(1, int(float64(b.Dy())*scale))
	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	xr, yr := float64(b.Dx())/float64(w), float64(b.Dy())/float64(h)
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			var rs, gs, bs, n uint32
			for sy := int(float64(y) * yr); sy < int(float64(y+1)*yr) && sy < b.Dy(); sy++ {
				for sx := int(float64(x) * xr); sx < int(float64(x+1)*xr) && sx < b.Dx(); sx++ {
					r, g, bb, _ := img.At(b.Min.X+sx, b.Min.Y+sy).RGBA()
					rs += r >> 8
					gs += g >> 8
					bs += bb >> 8
					n++
				}
			}
			if n == 0 {
				n = 1
			}
			dst.Set(x, y, color.RGBA{uint8(rs / n), uint8(gs / n), uint8(bs / n), 255})
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, dst, &jpeg.Options{Quality: 82}); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

// Placeholder paints a dry-run stand-in: a flat panel whose hue is derived from
// the cell id, so a dry table still shows that every cell is distinct without
// spending a second of GPU.
func Placeholder(w, h int, id string) []byte {
	var seed uint32 = 2166136261
	for _, c := range id {
		seed = (seed ^ uint32(c)) * 16777619
	}
	hue := float64(seed%360) / 360
	r, g, b := hsv(hue, 0.18, 0.30)
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	draw.Draw(img, img.Bounds(), &image.Uniform{color.RGBA{r, g, b, 255}},
		image.Point{}, draw.Src)
	// A diagonal band keeps a dry-run image visually unmistakable next to a
	// real render at thumbnail size.
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			if (x+y)%64 < 6 {
				img.Set(x, y, color.RGBA{r + 24, g + 24, b + 24, 255})
			}
		}
	}
	var buf bytes.Buffer
	_ = jpeg.Encode(&buf, img, &jpeg.Options{Quality: 70})
	return buf.Bytes()
}

func hsv(h, s, v float64) (uint8, uint8, uint8) {
	i := math.Floor(h * 6)
	f := h*6 - i
	p, q, t := v*(1-s), v*(1-f*s), v*(1-(1-f)*s)
	var r, g, b float64
	switch int(i) % 6 {
	case 0:
		r, g, b = v, t, p
	case 1:
		r, g, b = q, v, p
	case 2:
		r, g, b = p, v, t
	case 3:
		r, g, b = p, q, v
	case 4:
		r, g, b = t, p, v
	default:
		r, g, b = v, p, q
	}
	return uint8(r * 255), uint8(g * 255), uint8(b * 255)
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func writeFile(path string, data []byte) error { return os.WriteFile(path, data, 0o644) }
