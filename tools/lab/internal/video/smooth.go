package video

import (
	"bytes"
	"encoding/gob"
	"fmt"
	"image"
	"math"
	"os"
	"path/filepath"
	"sync"
)

// order: smooth — the values of an axis in the order with the smallest jumps
// in the picture: each value's mean colour histogram (of its thumbnails),
// cosine distance, nearest neighbour + 2-opt (as tools/stylemap's tour).

// Histogram is a 512-bin RGB histogram (8 levels per channel) of a downscaled
// image — the measure the lab's metrics and the style matrix use.
func Histogram(data []byte) ([]float64, error) {
	img, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	return histOf(img), nil
}

func histOf(img image.Image) []float64 {
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
	return h
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

// ── histogram cache: memory + <lab>/_video/.index/hist-<run>.gob ──

type histEntry struct {
	Mod  int64 // thumbnail mtime, ns
	Hist []float32
}

type runHists struct {
	mu    sync.Mutex
	cells map[string]histEntry
	dirty bool
}

var histCache sync.Map // run dir → *runHists

func histFile(runDir string) string {
	return filepath.Join(filepath.Dir(runDir), "_video", ".index", "hist-"+filepath.Base(runDir)+".gob")
}

func hists(runDir string) *runHists {
	if v, ok := histCache.Load(runDir); ok {
		return v.(*runHists)
	}
	rh := &runHists{cells: map[string]histEntry{}}
	if f, err := os.Open(histFile(runDir)); err == nil {
		_ = gob.NewDecoder(f).Decode(&rh.cells)
		f.Close()
	}
	v, _ := histCache.LoadOrStore(runDir, rh)
	return v.(*runHists)
}

func (rh *runHists) save(runDir string) {
	rh.mu.Lock()
	defer rh.mu.Unlock()
	if !rh.dirty {
		return
	}
	path := histFile(runDir)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return
	}
	var buf bytes.Buffer
	if gob.NewEncoder(&buf).Encode(rh.cells) == nil && os.WriteFile(path+".tmp", buf.Bytes(), 0o644) == nil {
		if os.Rename(path+".tmp", path) == nil {
			rh.dirty = false
		}
	}
}

// picHist: the thumbnail's histogram (the original when there is none).
func picHist(runDir, cell string) []float32 {
	file := filepath.Join(runDir, "thumb", cell+".jpg")
	st, err := os.Stat(file)
	if err != nil {
		file = filepath.Join(runDir, "img", cell+".png")
		if st, err = os.Stat(file); err != nil || st.Size() == 0 {
			return nil
		}
	}
	rh := hists(runDir)
	rh.mu.Lock()
	e, ok := rh.cells[cell]
	rh.mu.Unlock()
	if ok && e.Mod == st.ModTime().UnixNano() {
		return e.Hist
	}
	data, err := os.ReadFile(file)
	if err != nil {
		return nil
	}
	h, err := Histogram(data)
	if err != nil {
		return nil
	}
	f := make([]float32, len(h))
	for i, v := range h {
		f[i] = float32(v)
	}
	rh.mu.Lock()
	rh.cells[cell] = histEntry{Mod: st.ModTime().UnixNano(), Hist: f}
	rh.dirty = true
	rh.mu.Unlock()
	return f
}

// SmoothInfo tells how much smoother the order got: the mean histogram jump
// between neighbouring values before (picker/run order) and after.
type SmoothInfo struct {
	Values int     `json:"values"`
	Before float64 `json:"before"`
	After  float64 `json:"after"`
}

// smoothRank orders the values of an axis by their look. Values without a
// readable picture keep their place after the rest; the style-less baseline
// stays first. base is the default order (picker / run).
func smoothRank(p *Pool, axis string, base []string) (map[string]int, SmoothInfo) {
	dirOf := map[string]string{}
	for _, r := range p.Runs {
		dirOf[r.ID] = r.Dir
	}
	type job struct {
		value     string
		dir, cell string
	}
	var jobs []job
	for _, pic := range p.Pics {
		if d := dirOf[pic.Run]; d != "" {
			jobs = append(jobs, job{p.Value(pic, axis), d, pic.Cell})
		}
	}
	sums := map[string][]float64{}
	var mu sync.Mutex
	var wg sync.WaitGroup
	sem := make(chan struct{}, 8)
	for _, j := range jobs {
		wg.Add(1)
		sem <- struct{}{}
		go func() {
			defer wg.Done()
			defer func() { <-sem }()
			h := picHist(j.dir, j.cell)
			if h == nil {
				return
			}
			mu.Lock()
			defer mu.Unlock()
			s := sums[j.value]
			if s == nil {
				s = make([]float64, len(h))
				sums[j.value] = s
			}
			for i, v := range h {
				s[i] += float64(v)
			}
		}()
	}
	wg.Wait()
	for _, d := range uniqueDirs(jobs, func(j job) string { return j.dir }) {
		hists(d).save(d)
	}

	var head, vals, tail []string
	for _, v := range base {
		switch {
		case axis == AxStyle && v == Baseline:
			head = append(head, v)
		case sums[v] != nil:
			vals = append(vals, v)
		default:
			tail = append(tail, v)
		}
	}
	n := len(vals)
	d := make([][]float64, n)
	for i := range d {
		d[i] = make([]float64, n)
		for j := 0; j < i; j++ {
			d[i][j] = CosDist(sums[vals[i]], sums[vals[j]])
			d[j][i] = d[i][j]
		}
	}
	order := tour(d)
	rank := map[string]int{}
	k := 0
	for _, v := range head {
		rank[v] = k
		k++
	}
	for _, i := range order {
		rank[vals[i]] = k
		k++
	}
	for _, v := range tail {
		rank[v] = k
		k++
	}
	info := SmoothInfo{Values: n}
	if n > 1 {
		for i := 1; i < n; i++ {
			info.Before += d[i-1][i]
			info.After += d[order[i-1]][order[i]]
		}
		info.Before /= float64(n - 1)
		info.After /= float64(n - 1)
	}
	return rank, info
}

func uniqueDirs[T any](xs []T, key func(T) string) []string {
	seen := map[string]bool{}
	var out []string
	for _, x := range xs {
		if k := key(x); !seen[k] {
			seen[k] = true
			out = append(out, k)
		}
	}
	return out
}

// tour: an open path with small steps — nearest neighbour from the outlier,
// then 2-opt on the path. (tools/stylemap closes a cycle and cuts it at the
// longest step; on gradient-like data that leaves a there-and-back path, so
// this one never closes the loop.)
func tour(d [][]float64) []int {
	n := len(d)
	order := make([]int, n)
	for i := range order {
		order[i] = i
	}
	if n < 3 {
		return order
	}
	// Start at the outlier: it has to go somewhere, best at an end.
	cur, worst := 0, -1.0
	for i := range d {
		s := 0.0
		for _, v := range d[i] {
			s += v
		}
		if s > worst {
			cur, worst = i, s
		}
	}
	left := make([]bool, n)
	for i := range left {
		left[i] = true
	}
	for i := 0; i < n; i++ {
		order[i] = cur
		left[cur] = false
		best, bd := -1, math.Inf(1)
		for j := 0; j < n; j++ {
			if left[j] && d[cur][j] < bd {
				best, bd = j, d[cur][j]
			}
		}
		cur = best
	}
	reverse := func(lo, hi int) {
		for ; lo < hi; lo, hi = lo+1, hi-1 {
			order[lo], order[hi] = order[hi], order[lo]
		}
	}
	// 2-opt: reverse order[i+1..j] when that shortens the path; i = -1
	// reverses a prefix, j = n-1 a suffix (an end has no edge to drop).
	for pass := 0; pass < 100; pass++ {
		improved := false
		for i := -1; i < n-1; i++ {
			for j := i + 2; j < n; j++ {
				if i == -1 && j == n-1 {
					continue
				}
				b, c := order[i+1], order[j]
				delta := 0.0
				if i >= 0 {
					a := order[i]
					delta += d[a][c] - d[a][b]
				}
				if j < n-1 {
					e := order[j+1]
					delta += d[b][e] - d[c][e]
				}
				if delta < -1e-12 {
					reverse(i+1, j)
					improved = true
				}
			}
		}
		if !improved {
			break
		}
	}
	return order
}

func (s SmoothInfo) String() string {
	return fmt.Sprintf("%d hodnot, průměrný skok %.3f → %.3f", s.Values, s.Before, s.After)
}
