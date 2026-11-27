package video

import (
	"bufio"
	"context"
	"crypto/sha1"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"sync"
)

// Beats is the beat grid of one track, found from the kick drum: the energy
// of the 30–75 Hz band, its rises (onsets), the tempo from their
// autocorrelation and the phase that puts most onsets on the grid. Techno
// and trance have a kick on every beat, so a steady grid is the right model;
// a missing kick does not shift it.
type Beats struct {
	File     string    `json:"file"`
	Duration float64   `json:"duration"` // seconds of audio
	BPM      float64   `json:"bpm"`
	Times    []float64 `json:"times"`    // every beat, seconds from the start of the track
	Strength []float64 `json:"strength"` // kick energy at each beat, 1 = median
	// Breakdown marks beats without a kick (at least two bars of them).
	Breakdown []bool `json:"breakdown"`
	// Bar is the beat index of the first downbeat (0–3): bars are Bar+4k.
	Bar int `json:"bar"`
}

const (
	beatRate = 11025 // samples per second the audio is decoded at
	beatHop  = 64    // samples per envelope frame (5.8 ms)
)

// ResolvePath reads a recipe path: absolute as is, relative to the lab
// directory (build/lab), e.g. _video/_audio/techno.mp3.
func ResolvePath(labDir, p string) string {
	if p == "" || filepath.IsAbs(p) {
		return p
	}
	if labDir != "" {
		if _, err := os.Stat(filepath.Join(labDir, p)); err == nil {
			return filepath.Join(labDir, p)
		}
	}
	return p
}

var beatMem sync.Map // cache key → *Beats

// LoadBeats analyses a track once; the result is kept in memory and in
// labDir/_video/.index/beats-<hash>.json (keyed by path, size, mtime, hint).
func LoadBeats(ctx context.Context, ffmpeg, labDir, path string, bpmHint float64) (*Beats, error) {
	st, err := os.Stat(path)
	if err != nil {
		return nil, fmt.Errorf("hudba %s: %w", path, err)
	}
	h := sha1.Sum([]byte(fmt.Sprintf("v4|%s|%d|%d|%g", path, st.Size(), st.ModTime().UnixNano(), bpmHint)))
	key := hex.EncodeToString(h[:8])
	if b, ok := beatMem.Load(key); ok {
		return b.(*Beats), nil
	}
	cache := ""
	if labDir != "" {
		cache = filepath.Join(labDir, "_video", ".index", "beats-"+key+".json")
		if data, err := os.ReadFile(cache); err == nil {
			var b Beats
			if json.Unmarshal(data, &b) == nil && len(b.Times) > 0 {
				beatMem.Store(key, &b)
				return &b, nil
			}
		}
	}
	samples, err := decodeMono(ctx, ffmpeg, path)
	if err != nil {
		return nil, err
	}
	b, err := AnalyzeBeats(samples, beatRate, bpmHint)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", filepath.Base(path), err)
	}
	b.File = path
	beatMem.Store(key, b)
	if cache != "" {
		if data, err := json.Marshal(b); err == nil && os.MkdirAll(filepath.Dir(cache), 0o755) == nil {
			_ = os.WriteFile(cache, data, 0o644)
		}
	}
	return b, nil
}

func decodeMono(ctx context.Context, ffmpeg, path string) ([]float32, error) {
	if ffmpeg == "" {
		ffmpeg = "ffmpeg"
	}
	cmd := exec.CommandContext(ctx, ffmpeg, "-v", "error", "-i", path, "-vn", "-ac", "1",
		"-ar", fmt.Sprint(beatRate), "-f", "f32le", "-")
	out, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	var stderr limitedBuffer
	cmd.Stderr = &stderr
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("chybí ffmpeg (brew install ffmpeg): %w", err)
	}
	r := bufio.NewReaderSize(out, 1<<16)
	var s []float32
	buf := make([]byte, 4)
	for {
		if _, err := io.ReadFull(r, buf); err != nil {
			break
		}
		s = append(s, math.Float32frombits(binary.LittleEndian.Uint32(buf)))
	}
	if err := cmd.Wait(); err != nil {
		return nil, fmt.Errorf("ffmpeg %s: %v %s", filepath.Base(path), err, stderr.String())
	}
	return s, nil
}

// AnalyzeBeats finds the beat grid in mono samples. bpmHint (0 = none)
// narrows the tempo search to ±4 % around it; without it the search is
// 90–180 BPM, where techno and trance live (half or double tempo is the
// classic mistake of beat trackers).
func AnalyzeBeats(samples []float32, rate int, bpmHint float64) (*Beats, error) {
	fps := float64(rate) / beatHop // envelope frames per second
	n := len(samples) / beatHop
	if n < int(4*fps) {
		return nil, fmt.Errorf("skladba je kratší než 4 s")
	}
	// Kick band: high-pass 30 Hz, low-pass 75 Hz (twice, 24 dB/oct). Up to
	// 150 Hz the off-beat bass of techno is as loud as the kick and the grid
	// would land half a beat off — measured on a generated track.
	hp := newBiquad(rate, 30, true)
	lp := newBiquad(rate, 75, false)
	lp2 := newBiquad(rate, 75, false)
	env := make([]float64, n) // RMS of the kick band per frame
	for i := 0; i < n; i++ {
		var e float64
		for _, x := range samples[i*beatHop : (i+1)*beatHop] {
			y := lp2.step(lp.step(hp.step(float64(x))))
			e += y * y
		}
		env[i] = math.Sqrt(e / beatHop)
	}
	// Onsets: half-wave rectified rise of the compressed envelope.
	on := make([]float64, n)
	for i := 1; i < n; i++ {
		d := math.Log1p(100*env[i]) - math.Log1p(100*env[i-1])
		if d > 0 {
			on[i] = d
		}
	}

	lo, hi := 90.0, 180.0
	if bpmHint > 0 {
		lo, hi = bpmHint*0.96, bpmHint*1.04
	}
	minLag := int(math.Floor(60 * fps / hi))
	maxLag := int(math.Ceil(60 * fps / lo))
	ac := make([]float64, maxLag+2)
	for L := max(1, minLag-1); L <= maxLag+1 && L < n; L++ {
		var s float64
		for i := 0; i+L < n; i++ {
			s += on[i] * on[i+L]
		}
		ac[L] = s / float64(n-L)
	}
	best := minLag
	for L := minLag; L <= maxLag; L++ {
		if ac[L] > ac[best] {
			best = L
		}
	}
	if ac[best] == 0 {
		return nil, fmt.Errorf("v basech není rytmus (žádný kopák?)")
	}
	period := float64(best)
	if best > 1 && best+1 < len(ac) { // parabolic refinement
		a, b, c := ac[best-1], ac[best], ac[best+1]
		if d := a - 2*b + c; d < 0 {
			period += 0.5 * (a - c) / d
		}
	}

	// Sharpen the period on multiples: the autocorrelation peak 4, 8, 16
	// beats away pins it to a sixteenth of a frame, where one beat away
	// would drift by beats over a whole track.
	for _, m := range []int{4, 8, 16} {
		c := int(math.Round(float64(m) * period))
		if c+3 >= n/2 {
			break
		}
		lag := func(L int) float64 {
			var s float64
			for i := 0; i+L < n; i++ {
				s += on[i] * on[i+L]
			}
			return s / float64(n-L)
		}
		bi, bv := c, -1.0
		vals := map[int]float64{}
		for L := c - 3; L <= c+3; L++ {
			vals[L] = lag(L)
			if vals[L] > bv {
				bi, bv = L, vals[L]
			}
		}
		if bi == c-3 || bi == c+3 {
			continue
		}
		x := float64(bi)
		a, b, cc := vals[bi-1], vals[bi], vals[bi+1]
		if d := a - 2*b + cc; d < 0 {
			x += 0.5 * (a - cc) / d
		}
		period = x / float64(m)
	}
	// Period and phase together: the grid over the whole track that
	// collects most (lightly smoothed) onsets, ±0.5 % around the estimate.
	sm := make([]float64, n)
	for i := 1; i+1 < n; i++ {
		sm[i] = 0.25*on[i-1] + 0.5*on[i] + 0.25*on[i+1]
	}
	smAt := func(x float64) float64 {
		i := int(x)
		if i < 0 || i+1 >= n {
			return 0
		}
		f := x - float64(i)
		return sm[i]*(1-f) + sm[i+1]*f
	}
	phase, bestScore, base := 0.0, -1.0, period
	for q := -25; q <= 25; q++ {
		pp := base * (1 + float64(q)*0.0002)
		for p := 0.0; p < pp; p += 0.25 {
			var s float64
			for x := p; x < float64(n); x += pp {
				s += smAt(x)
			}
			if s > bestScore {
				period, phase, bestScore = pp, p, s
			}
		}
	}
	// Refine tempo and phase together: snap each beat to the strongest onset
	// nearby and fit a line through them, weighted by how strong they are.
	win := int(math.Max(2, 0.08*period))
	var sw, sk, st, skk, skt float64
	for k := 0; ; k++ {
		x := phase + float64(k)*period
		if x >= float64(n) {
			break
		}
		c := int(math.Round(x))
		bi, bv := c, 0.0
		for i := max(1, c-win); i <= min(n-1, c+win); i++ {
			if on[i] > bv {
				bi, bv = i, on[i]
			}
		}
		if bv <= 0 {
			continue
		}
		fk, ft := float64(k), float64(bi)
		sw += bv
		sk += bv * fk
		st += bv * ft
		skk += bv * fk * fk
		skt += bv * fk * ft
	}
	if den := sw*skk - sk*sk; sw > 0 && den > 0 {
		slope := (sw*skt - sk*st) / den
		icpt := (st - slope*sk) / sw
		if math.Abs(slope-period)/period < 0.02 {
			period, phase = slope, icpt
		}
	}
	for phase-period >= 0 {
		phase -= period
	}
	for phase < 0 {
		phase += period
	}

	b := &Beats{Duration: float64(len(samples)) / float64(rate), BPM: 60 * fps / period}
	for x := phase; x < float64(n); x += period {
		b.Times = append(b.Times, x/fps)
		c := int(math.Round(x))
		var peak float64
		for i := max(0, c-win); i <= min(n-1, c+2*win); i++ {
			peak = math.Max(peak, env[i])
		}
		b.Strength = append(b.Strength, peak)
	}
	sorted := append([]float64(nil), b.Strength...)
	sort.Float64s(sorted)
	med := sorted[len(sorted)/2]
	if med <= 0 {
		med = 1
	}
	for i := range b.Strength {
		b.Strength[i] /= med
	}
	b.Breakdown = make([]bool, len(b.Times))
	for i := 0; i < len(b.Times); {
		j := i
		for j < len(b.Times) && b.Strength[j] < 0.35 {
			j++
		}
		if j-i >= 8 { // two bars without a kick
			for k := i; k < j; k++ {
				b.Breakdown[k] = true
			}
		}
		i = max(j, i+1)
	}
	b.Bar = barPhase(b)
	return b, nil
}

// barPhase guesses where bars start: the first kick after a breakdown is a
// downbeat in practically every dance track; without a breakdown, the beat
// position (mod 4) with the strongest kicks.
func barPhase(b *Beats) int {
	for i := 1; i < len(b.Breakdown); i++ {
		if b.Breakdown[i-1] && !b.Breakdown[i] {
			return i % 4
		}
	}
	var sum [4]float64
	for i, s := range b.Strength {
		sum[i%4] += s
	}
	best := 0
	for m := 1; m < 4; m++ {
		if sum[m] > sum[best] {
			best = m
		}
	}
	return best
}

// beatTime is the time of a fractional beat index; beyond the grid it
// extrapolates with the tempo.
func (b *Beats) beatTime(x float64) float64 {
	p := 60 / b.BPM
	if len(b.Times) == 0 {
		return x * p
	}
	i := int(math.Floor(x))
	if i < 0 {
		return b.Times[0] + x*p
	}
	if i >= len(b.Times)-1 {
		return b.Times[len(b.Times)-1] + (x-float64(len(b.Times)-1))*p
	}
	f := x - float64(i)
	return b.Times[i]*(1-f) + b.Times[i+1]*f
}

func (b *Beats) breakdownAt(x float64) bool {
	i := int(math.Floor(x))
	return i >= 0 && i < len(b.Breakdown) && b.Breakdown[i]
}

type biquad struct{ b0, b1, b2, a1, a2, x1, x2, y1, y2 float64 }

// newBiquad is a Butterworth (Q = 1/√2) high- or low-pass (RBJ cookbook).
func newBiquad(rate int, f float64, high bool) *biquad {
	w := 2 * math.Pi * f / float64(rate)
	alpha := math.Sin(w) / math.Sqrt2 // sin(w) / 2Q
	c := math.Cos(w)
	a0 := 1 + alpha
	q := &biquad{a1: -2 * c / a0, a2: (1 - alpha) / a0}
	if high {
		q.b0, q.b1, q.b2 = (1+c)/2/a0, -(1+c)/a0, (1+c)/2/a0
	} else {
		q.b0, q.b1, q.b2 = (1-c)/2/a0, (1-c)/a0, (1-c)/2/a0
	}
	return q
}

func (q *biquad) step(x float64) float64 {
	y := q.b0*x + q.b1*q.x1 + q.b2*q.x2 - q.a1*q.y1 - q.a2*q.y2
	q.x2, q.x1 = q.x1, x
	q.y2, q.y1 = q.y1, y
	return y
}

// SyncInfo is what the plan tells about the music.
type SyncInfo struct {
	Audio    string  `json:"audio"` // resolved path
	URL      string  `json:"url,omitempty"`
	BPM      float64 `json:"bpm"`
	Duration float64 `json:"duration"`
	Beats    int     `json:"beats"`
	// Breakdowns: [start, end) in seconds of the track.
	Breakdowns [][2]float64 `json:"breakdowns,omitempty"`
}

// ApplySync puts the slides of a recipe with time.sync on the beat grid of
// its track: each part starts with the track (sync.start) and lasts at most
// as long as the track from there (or output.split.seconds), cut where the
// split axis changes, otherwise on a bar. A plan without sync is untouched.
func ApplySync(ctx context.Context, sb *Storyboard, labDir, ffmpeg string) error {
	sy := sb.Recipe.Time.Sync
	if sy == nil {
		return nil
	}
	path := ResolvePath(labDir, sy.Audio)
	b, err := LoadBeats(ctx, ffmpeg, labDir, path, sy.BPM)
	if err != nil {
		return err
	}
	return syncWith(sb, b, path, labDir)
}

func syncWith(sb *Storyboard, b *Beats, path, labDir string) error {
	sy := sb.Recipe.Time.Sync
	info := &SyncInfo{Audio: path, BPM: math.Round(b.BPM*10) / 10, Duration: b.Duration, Beats: len(b.Times)}
	if rel, err := filepath.Rel(labDir, path); err == nil && labDir != "" && filepath.IsLocal(rel) {
		info.URL = "/media/" + filepath.ToSlash(rel)
	}
	for i := 0; i < len(b.Breakdown); i++ {
		if !b.Breakdown[i] {
			continue
		}
		j := i
		for j < len(b.Breakdown) && b.Breakdown[j] {
			j++
		}
		info.Breakdowns = append(info.Breakdowns, [2]float64{b.Times[i], b.beatTime(float64(j))})
		i = j
	}
	sb.Sync = info

	r := sb.Recipe
	limit := b.Duration - sy.Start
	if r.Output.Split != nil && r.Output.Split.Seconds < limit {
		limit = r.Output.Split.Seconds
	}
	if limit < 1 {
		return fmt.Errorf("time.sync.start %.1f s je za koncem skladby (%.1f s)", sy.Start, b.Duration)
	}
	// First beat at or after the start: the first cut of every part.
	first := 0.0
	for first < float64(len(b.Times)) && b.beatTime(first)+sy.Offset < sy.Start-1e-6 {
		first++
	}
	every := sy.Every
	slow := *sy.Breakdown
	fade := *r.Time.Fade
	type cut struct {
		t    float64 // end of the slide, seconds from the part start
		bar  bool    // ends on a downbeat
		fade float64
	}
	// cuts walks the grid from the start: the end of slide 0, 1, 2… — up to
	// count slides, and never far past the limit (16 beyond, for the bar).
	cuts := func(count int) []cut {
		out := make([]cut, 0, min(count, 4096))
		x := first
		over := 0
		for len(out) < count && over < 16 {
			step := every
			f := fade
			if slow > 0 && b.breakdownAt(x) {
				step = math.Max(every, slow)
				f = 0.5
			}
			x += step
			t := b.beatTime(x) + sy.Offset - sy.Start
			xi := math.Round(x)
			bar := math.Abs(x-xi) < 1e-6 && (int(xi)-b.Bar)%4 == 0
			out = append(out, cut{t: t, bar: bar, fade: f})
			if t > limit {
				over++
			}
		}
		return out
	}

	var videos []VideoPart
	parted := 0
	for _, v := range sb.Videos {
		var pieces []VideoPart
		a := v.From
		for a < v.To {
			cs := cuts(v.To - a + 16)
			// The longest run of slides that ends within the limit…
			fit := 0
			for fit < len(cs) && fit < v.To-a && cs[fit].t <= limit+1e-6 {
				fit++
			}
			if fit == 0 {
				fit = 1
			}
			end := a + fit
			if end < v.To {
				// …cut where the split axis changes — on a bar if one is
				// near — else on a bar.
				change := func(k int) bool {
					g := sb.Slides[a+k-1].group
					return g == "" || g != sb.Slides[a+k].group
				}
				best := -1
				for k := fit; k >= max(1, fit*3/4); k-- {
					if change(k) && cs[k-1].bar {
						best = k
						break
					}
				}
				if best < 0 && sb.Slides[a].group != "" {
					for k := fit; k >= max(1, fit/2); k-- {
						if change(k) {
							best = k
							break
						}
					}
				}
				if best > 0 {
					end = a + best
				}
			}
			n := end - a
			times := make([]float64, n+1)
			fades := make([]float64, n)
			for k := 0; k < n; k++ {
				times[k+1] = cs[k].t
				fades[k] = cs[k].fade
			}
			fades[n-1] = 0
			// The last slide holds to the next bar, so the music ends on one.
			if end == v.To && !cs[n-1].bar {
				for k := n; k < len(cs) && cs[k].t <= limit+1e-6; k++ {
					if cs[k].bar {
						times[n] = cs[k].t
						break
					}
				}
			}
			pieces = append(pieces, VideoPart{Per: v.Per, From: a, To: end, Times: times, Fades: fades,
				AudioStart: sy.Start, Seconds: times[n]})
			a = end
		}
		for i := range pieces {
			p := &pieces[i]
			p.Name = v.Name
			if len(pieces) > 1 {
				p.Name = fmt.Sprintf("%s-%02d", v.Name, i+1)
			}
			for k := p.From; k < p.To; k++ {
				if g := sb.Slides[k].group; g != "" && (len(p.Groups) == 0 || p.Groups[len(p.Groups)-1] != g) {
					p.Groups = append(p.Groups, g)
				}
			}
		}
		if len(pieces) > 1 && r.Output.Split == nil {
			parted++
		}
		videos = append(videos, pieces...)
	}
	sb.Videos = videos
	sb.Stats.Seconds = 0
	for _, v := range videos {
		sb.Stats.Seconds += v.Seconds
	}
	if parted > 0 {
		sb.Warnings = append(sb.Warnings, fmt.Sprintf(
			"snímků je víc, než unese skladba (%.0f s) — rozděleno na %d videí, každé hraje skladbu od začátku",
			b.Duration-sy.Start, len(videos)))
	}
	minFrames := math.MaxFloat64
	for _, v := range videos {
		for k := 0; k+1 < len(v.Times); k++ {
			minFrames = math.Min(minFrames, (v.Times[k+1]-v.Times[k])*float64(r.Output.FPS))
		}
	}
	if minFrames < 2 {
		sb.Warnings = append(sb.Warnings, fmt.Sprintf(
			"při %.0f BPM a every %g má snímek jen %.1f snímku videa — zvol větší every nebo output.fps 60",
			b.BPM, every, minFrames))
	}
	return nil
}

// PlanSynced is Plan followed by ApplySync: what every caller wants.
func PlanSynced(ctx context.Context, col *Collection, r Recipe, labDir, ffmpeg string) (*Storyboard, error) {
	sb, err := Plan(col, r)
	if err != nil {
		return nil, err
	}
	if err := ApplySync(ctx, sb, labDir, ffmpeg); err != nil {
		return nil, err
	}
	return sb, nil
}
