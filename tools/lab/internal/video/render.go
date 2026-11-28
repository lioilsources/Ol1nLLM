package video

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	"io"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"time"
)

// Progress reports rendering: which part, how many of its frames are done.
type Progress struct {
	Part        int     `json:"part"` // 1-based
	Parts       int     `json:"parts"`
	Name        string  `json:"name"`
	Frame       int     `json:"frame"`
	Frames      int     `json:"frames"`
	Done        []Done  `json:"done,omitempty"`
	ElapsedSecs float64 `json:"elapsed"`
}

// Done is one finished file.
type Done struct {
	Name    string  `json:"name"`
	File    string  `json:"file"`
	Bytes   int64   `json:"bytes"`
	Seconds float64 `json:"seconds"`
}

// RenderOptions: where to write, which parts, and how to report.
type RenderOptions struct {
	LabDir string
	OutDir string
	// Only renders the parts with these names (empty = all).
	Only []string
	// Thumbs draws from thumbnails — a quick draft, never the real thing.
	Thumbs   bool
	Progress func(Progress)
	// FFmpeg is the binary (default "ffmpeg" from PATH).
	FFmpeg string
}

// Render writes every part of the storyboard as MP4 into opt.OutDir, next to
// the recipe and a summary of the storyboard. A part is written to
// <name>.part.mp4 and renamed when complete; cancelling the context kills
// ffmpeg and removes the partial file.
func Render(ctx context.Context, sb *Storyboard, opt RenderOptions) ([]Done, error) {
	if sb.Layout == nil {
		return nil, fmt.Errorf("scénář nemá rozložení")
	}
	ff := opt.FFmpeg
	if ff == "" {
		ff = "ffmpeg"
	}
	if _, err := exec.LookPath(ff); err != nil {
		return nil, fmt.Errorf("chybí ffmpeg (brew install ffmpeg)")
	}
	if err := os.MkdirAll(opt.OutDir, 0o755); err != nil {
		return nil, err
	}
	if err := writeRecipeFiles(sb, opt.OutDir); err != nil {
		return nil, err
	}
	only := map[string]bool{}
	for _, n := range opt.Only {
		only[n] = true
	}
	var todo []VideoPart
	for _, v := range sb.Videos {
		if len(only) == 0 || only[v.Name] {
			todo = append(todo, v)
		}
	}
	if len(todo) == 0 {
		return nil, fmt.Errorf("žádný díl ke zpracování (--only %v)", opt.Only)
	}
	comp := &Composer{LabDir: opt.LabDir, SB: sb, Thumbs: opt.Thumbs}
	start := time.Now()
	var done []Done
	for pi, v := range todo {
		report := func(frame, frames int) {
			if opt.Progress != nil {
				opt.Progress(Progress{Part: pi + 1, Parts: len(todo), Name: v.Name, Frame: frame, Frames: frames,
					Done: done, ElapsedSecs: time.Since(start).Seconds()})
			}
		}
		d, err := renderPart(ctx, ff, comp, sb, v, opt.OutDir, report)
		if err != nil {
			return done, fmt.Errorf("%s: %w", v.Name, err)
		}
		done = append(done, d)
	}
	if opt.Progress != nil {
		opt.Progress(Progress{Part: len(todo), Parts: len(todo), Done: done, ElapsedSecs: time.Since(start).Seconds()})
	}
	return done, nil
}

func writeRecipeFiles(sb *Storyboard, dir string) error {
	y, err := MarshalRecipe(sb.Recipe)
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(dir, "recipe.yaml"), y, 0o644); err != nil {
		return err
	}
	summary := *sb
	summary.Slides = nil
	data, err := json.MarshalIndent(summary, "", " ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "storyboard.json"), data, 0o644)
}

// renderPart pipes the frames of one part to ffmpeg.
func renderPart(ctx context.Context, ff string, comp *Composer, sb *Storyboard, v VideoPart, dir string,
	report func(frame, frames int)) (Done, error) {
	r := sb.Recipe
	l := sb.Layout
	fps := r.Output.FPS
	n := v.To - v.From
	// starts[i]: the first video frame of slide i; starts[n] = total. With
	// time.sync each cut is the frame nearest its beat (never accumulating
	// rounding), otherwise every slide holds fps/rate frames.
	starts := make([]int, n+1)
	for i := 0; i <= n; i++ {
		if len(v.Times) == n+1 {
			starts[i] = int(math.Round(v.Times[i] * float64(fps)))
		} else {
			starts[i] = int(math.Round(float64(i) * float64(fps) / r.Time.Rate))
		}
	}
	total := max(1, starts[n])
	fades := v.Fades
	if len(fades) != n {
		fades = nil
	}
	final := filepath.Join(dir, v.Name+".mp4")
	part := filepath.Join(dir, v.Name+".part.mp4")

	args := []string{"-y", "-loglevel", "error",
		"-f", "rawvideo", "-pix_fmt", "rgb24", "-s", fmt.Sprintf("%dx%d", l.W, l.H), "-r", strconv.Itoa(fps), "-i", "-"}
	audio := r.Output.Audio
	if r.Time.Sync != nil {
		audio = r.Time.Sync.Audio
	}
	if audio != "" {
		secs := float64(total) / float64(fps)
		if v.AudioStart > 0 {
			args = append(args, "-ss", strconv.FormatFloat(v.AudioStart, 'f', 3, 64))
		}
		args = append(args, "-i", ResolvePath(comp.LabDir, audio), "-map", "0:v", "-map", "1:a",
			"-c:a", "aac", "-b:a", "192k", "-shortest")
		if r.Time.Sync != nil && secs > 3 {
			// The video ends before the track: fade the music out over the last second.
			args = append(args, "-af", fmt.Sprintf("afade=t=out:st=%.3f:d=1", secs-1))
		}
	}
	switch r.Output.Encoder {
	case "", "libx264":
		args = append(args, "-c:v", "libx264", "-preset", "medium", "-crf", strconv.Itoa(r.Output.CRF))
	case "videotoolbox", "h264_videotoolbox":
		// Hardware H.264 on a Mac: faster, larger for the same quality.
		args = append(args, "-c:v", "h264_videotoolbox", "-q:v", strconv.Itoa(max(1, 100-2*r.Output.CRF)))
	default:
		return Done{}, fmt.Errorf("output.encoder %q: libx264 nebo videotoolbox", r.Output.Encoder)
	}
	args = append(args, "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-f", "mp4", part)

	cctx, cancel := context.WithCancel(ctx)
	defer cancel()
	cmd := exec.CommandContext(cctx, ff, args...)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return Done{}, err
	}
	var stderr limitedBuffer
	cmd.Stderr = &stderr
	if err := cmd.Start(); err != nil {
		return Done{}, err
	}
	fail := func(err error) (Done, error) {
		cancel()
		_ = stdin.Close()
		_ = cmd.Wait()
		_ = os.Remove(part)
		if msg := stderr.String(); msg != "" {
			err = fmt.Errorf("%w — ffmpeg: %s", err, msg)
		}
		return Done{}, err
	}

	// Slides are composed ahead by a small pool of workers while frames go
	// out in order; ffmpeg's encoder is the other big consumer of cores.
	type composed struct {
		rgb []byte
		err error
	}
	ahead := max(2, runtime.NumCPU()/2)
	slots := make([]chan composed, n)
	for i := range slots {
		slots[i] = make(chan composed, 1)
	}
	jobs := make(chan int)
	go func() {
		defer close(jobs)
		for i := 0; i < n; i++ {
			select {
			case jobs <- i:
			case <-cctx.Done():
				return
			}
		}
	}()
	sem := make(chan struct{}, ahead) // at most `ahead` slides in memory beyond the current one
	for wk := 0; wk < ahead; wk++ {
		go func() {
			for i := range jobs {
				select {
				case sem <- struct{}{}:
				case <-cctx.Done():
					return
				}
				img, err := comp.Compose(v.From + i)
				if err != nil {
					slots[i] <- composed{err: err}
					continue
				}
				slots[i] <- composed{rgb: toRGB(img)}
			}
		}()
	}
	get := func(i int) ([]byte, error) {
		c := <-slots[i]
		<-sem
		return c.rgb, c.err
	}
	w := bufio.NewWriterSize(stdin, 4<<20)
	var cur, nxt []byte
	mix := make([]byte, l.W*l.H*3)
	fade := *r.Time.Fade
	slide := -1
	for k := 0; k < total; k++ {
		if err := ctx.Err(); err != nil {
			return fail(errors.New("zrušeno"))
		}
		i := slide
		if i < 0 {
			i = 0
		}
		for i+1 < n && starts[i+1] <= k {
			i++
		}
		if i != slide {
			// Slides too short for a single frame are skipped, but their
			// composed frames still have to be taken off the pool.
			for j := slide + 1; j < i; j++ {
				if j == slide+1 && nxt != nil {
					nxt = nil
					continue
				}
				if _, err := get(j); err != nil {
					return fail(err)
				}
			}
			if nxt != nil && i == slide+1 {
				cur, nxt = nxt, nil
			} else {
				var err error
				if cur, err = get(i); err != nil {
					return fail(err)
				}
			}
			slide = i
		}
		out := cur
		f := fade
		if fades != nil {
			f = fades[i]
		}
		span := starts[i+1] - starts[i]
		phase := 0.0
		if span > 0 {
			phase = float64(k-starts[i]) / float64(span)
		}
		if i+1 < n && f > 0 && phase > 1-f {
			if nxt == nil {
				var err error
				if nxt, err = get(i + 1); err != nil {
					return fail(err)
				}
			}
			a := int((phase - (1 - f)) / f * 256)
			blend(mix, cur, nxt, a)
			out = mix
		}
		if _, err := w.Write(out); err != nil {
			return fail(fmt.Errorf("zápis do ffmpeg: %w", err))
		}
		if report != nil && (k%fps == 0 || k == total-1) {
			report(k+1, total)
		}
	}
	if err := w.Flush(); err != nil {
		return fail(err)
	}
	if err := stdin.Close(); err != nil {
		return fail(err)
	}
	if err := cmd.Wait(); err != nil {
		_ = os.Remove(part)
		return Done{}, fmt.Errorf("ffmpeg: %v %s", err, stderr.String())
	}
	if err := os.Rename(part, final); err != nil {
		return Done{}, err
	}
	st, _ := os.Stat(final)
	size := int64(0)
	if st != nil {
		size = st.Size()
	}
	return Done{Name: v.Name, File: final, Bytes: size, Seconds: float64(total) / float64(fps)}, nil
}

// toRGB drops the alpha channel: a quarter less through the pipe.
func toRGB(img *image.RGBA) []byte {
	b := img.Bounds()
	out := make([]byte, b.Dx()*b.Dy()*3)
	j := 0
	for y := b.Min.Y; y < b.Max.Y; y++ {
		row := img.Pix[img.PixOffset(b.Min.X, y):]
		for x := 0; x < b.Dx(); x++ {
			out[j], out[j+1], out[j+2] = row[x*4], row[x*4+1], row[x*4+2]
			j += 3
		}
	}
	return out
}

// blend writes a·b + (1−a)·c into dst, a in 0..256.
func blend(dst, c, b []byte, a int) {
	ia := 256 - a
	for i := range dst {
		dst[i] = byte((int(c[i])*ia + int(b[i])*a) >> 8)
	}
}

// limitedBuffer keeps the first 4 KB of ffmpeg's stderr.
type limitedBuffer struct{ b []byte }

func (l *limitedBuffer) Write(p []byte) (int, error) {
	if room := 4096 - len(l.b); room > 0 {
		l.b = append(l.b, p[:min(room, len(p))]...)
	}
	return len(p), nil
}

func (l *limitedBuffer) String() string { return string(l.b) }

var _ io.Writer = (*limitedBuffer)(nil)
