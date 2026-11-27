package video

import (
	"context"
	"image/color"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// Every character the labels use: Czech, the separators of style labels,
// years BCE.
func TestFontHasEveryGlyphTheLabelsUse(t *testing.T) {
	sample := "ěščřžýáíéúůťďňó ĚŠČŘŽÝÁÍÉÚŮŤĎŇÓ — · … – „“ () 0123456789 př. n. l. ×"
	for _, bold := range []bool{false, true} {
		if f := face(24, bold); !hasGlyphs(f, sample) {
			for _, r := range sample {
				if !hasGlyphs(f, string(r)) {
					t.Errorf("písmo (bold %v) nemá %q", bold, r)
				}
			}
		}
	}
}

func TestWrapAndFit(t *testing.T) {
	f := face(20, false)
	lines := wrapText(f, "Picasso — kubistický portrét (Dora Maar) (1881)", 200)
	if len(lines) < 2 {
		t.Fatalf("dlouhý název se má zalomit: %q", lines)
	}
	for _, l := range lines {
		if textWidth(f, l) > 200 && strings.Contains(l, " ") {
			t.Fatalf("řádek %q je širší než 200 px", l)
		}
	}
	fit := fitLines(f, []string{"a", "b", "c d e"}, 2, 1000)
	if len(fit) != 2 || !strings.HasSuffix(fit[1], "…") {
		t.Fatalf("víc řádků než dva → výpustka: %q", fit)
	}
}

// planFixture plans a small grid over runs A and B (models a, b, c).
func planFixture(t *testing.T, lab, extra string) *Storyboard {
	t.Helper()
	col := mustLoad(t, lab)
	sb, err := Plan(col, mustRecipe(t, "name: t\nsource: {runs: ["+runA+", "+runB+"]}\n"+extra))
	if err != nil {
		t.Fatal(err)
	}
	return sb
}

func TestComposeGridDrawsTilesAndEmptyFrames(t *testing.T) {
	lab := fixture(t)
	sb := planFixture(t, lab, "frame: {tiles: model, title: auto, captions: auto}\ntime: {axes: [prompt, style], complete: false}\noutput: {size: 270x480}\n")
	c := &Composer{LabDir: lab, SB: sb}
	// Slide 1: s1 × cave — only a has it; b and c are empty frames.
	var idx = -1
	for i, s := range sb.Slides {
		if s.Key[AxStyle] == "cave" {
			idx = i
		}
	}
	img, err := c.Compose(idx)
	if err != nil {
		t.Fatal(err)
	}
	l := sb.Layout
	if got := img.RGBAAt(1, l.H-2); got != colBackground {
		t.Fatalf("pozadí %v", got)
	}
	a := l.Tiles[0].Pic
	if got := img.RGBAAt(a.X+a.W/2, a.Y+a.H/2); got == colBackground {
		t.Fatal("dlaždice a má obrázek")
	}
	b := l.Tiles[1].Pic
	if got := img.RGBAAt(b.X, b.Y+b.H/2); got != colEmptyTile {
		t.Fatalf("prázdná dlaždice má rámeček, je tam %v", got)
	}
	if got := img.RGBAAt(b.X+b.W/2, b.Y+b.H/2); got != colBackground {
		t.Fatalf("prázdná dlaždice je uvnitř prázdná, je tam %v", got)
	}
	if got := img.RGBAAt(l.Title.X+2, l.Title.Y+l.Title.H/2); got == colBackground {
		t.Fatal("titulek má box")
	}
}

func TestComposeSingleContainOverBlur(t *testing.T) {
	lab := fixture(t)
	sb := planFixture(t, lab, "select: {model: a}\nframe: {captions: auto}\noutput: {size: 270x480}\n")
	img, err := (&Composer{LabDir: lab, SB: sb}).Compose(0)
	if err != nil {
		t.Fatal(err)
	}
	// The 4×6 test picture is grey (128) with one red pixel: a 2:3 picture on
	// 9:16 leaves bands above and below — the blurred copy, darkened to 45 %.
	top := img.RGBAAt(135, 5)
	if top == (color.RGBA{}) || top.R > 100 {
		t.Fatalf("pás nad obrázkem má být ztmavená kopie, je %v", top)
	}
	mid := img.RGBAAt(135, 400)
	if mid.G < 100 {
		t.Fatalf("uprostřed je obrázek, ne %v", mid)
	}
}

func TestRenderWritesPartsAndRecipe(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg chybí")
	}
	lab := fixture(t)
	sb := planFixture(t, lab, "frame: {tiles: model}\ntime: {axes: [prompt, style], complete: false, rate: 4, fade: 0.5}\noutput: {size: 180x320, fps: 8, split: {seconds: 1.5}}\n")
	out := t.TempDir()
	var last Progress
	done, err := Render(context.Background(), sb, RenderOptions{LabDir: lab, OutDir: out,
		Progress: func(p Progress) { last = p }})
	if err != nil {
		t.Fatal(err)
	}
	// 8 slides at 4/s, split at 1.5 s between prompts: s1 has 5 slides (1.25 s),
	// s2 has 3 (0.75 s).
	if len(done) != 2 || len(sb.Videos) != 2 {
		t.Fatalf("dílů %d, čekám 2", len(done))
	}
	for i, d := range done {
		if filepath.Base(d.File) != sb.Videos[i].Name+".mp4" || d.Bytes == 0 {
			t.Fatalf("díl %d: %+v", i, d)
		}
		if _, err := os.Stat(strings.TrimSuffix(d.File, ".mp4") + ".part.mp4"); err == nil {
			t.Fatal(".part soubor má po dokončení zmizet")
		}
	}
	if got := probeFrames(t, done[0].File); got != 10 { // 5 slides × 8/4 frames
		t.Fatalf("snímků videa %d, čekám 10", got)
	}
	for _, f := range []string{"recipe.yaml", "storyboard.json"} {
		if _, err := os.Stat(filepath.Join(out, f)); err != nil {
			t.Fatalf("vedle videí má být %s", f)
		}
	}
	if len(last.Done) != 2 {
		t.Fatalf("poslední hlášení průběhu nese hotové díly: %+v", last)
	}
	// --only one part.
	only, err := Render(context.Background(), sb, RenderOptions{LabDir: lab, OutDir: t.TempDir(), Only: []string{sb.Videos[1].Name}})
	if err != nil || len(only) != 1 {
		t.Fatalf("only: %v %v", only, err)
	}
}

func TestRenderCancelRemovesPartialFile(t *testing.T) {
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg chybí")
	}
	lab := fixture(t)
	sb := planFixture(t, lab, "frame: {tiles: model}\ntime: {axes: [prompt, style], complete: false, rate: 1}\noutput: {size: 180x320}\n")
	ctx, cancel := context.WithCancel(context.Background())
	out := t.TempDir()
	_, err := Render(ctx, sb, RenderOptions{LabDir: lab, OutDir: out, Progress: func(p Progress) {
		if p.Frame > 5 {
			cancel()
		}
	}})
	if err == nil {
		t.Fatal("zrušený render má vrátit chybu")
	}
	files, _ := filepath.Glob(filepath.Join(out, "*.mp4"))
	if len(files) != 0 {
		t.Fatalf("po zrušení nemá zůstat video: %v", files)
	}
}

func probeFrames(t *testing.T, path string) int {
	t.Helper()
	out, err := exec.Command("ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
		"-show_entries", "stream=nb_read_frames", "-of", "csv=p=0", path).Output()
	if err != nil {
		t.Fatal(err)
	}
	n, _ := strconv.Atoi(strings.TrimSpace(string(out)))
	return n
}
