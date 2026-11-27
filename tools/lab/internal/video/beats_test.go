package video

import (
	"math"
	"math/rand"
	"strings"
	"testing"
)

// synthTrack: a kick (decaying 55 Hz sine) on every beat from phase, a
// hi-hat (noise burst) on every off-beat, no kick in beats [bdFrom, bdTo).
func synthTrack(bpm, phase, seconds float64, bdFrom, bdTo int) []float32 {
	rate := beatRate
	s := make([]float32, int(seconds*float64(rate)))
	rnd := rand.New(rand.NewSource(1))
	p := 60 / bpm
	for k := 0; ; k++ {
		t := phase + float64(k)*p
		if t >= seconds {
			break
		}
		start := int(t * float64(rate))
		if k < bdFrom || k >= bdTo {
			for i := 0; i < rate/6 && start+i < len(s); i++ {
				x := float64(i) / float64(rate)
				s[start+i] += float32(0.8 * math.Exp(-x*25) * math.Sin(2*math.Pi*55*x))
			}
		}
		off := int((t + p/2) * float64(rate))
		for i := 0; i < rate/40 && off+i < len(s); i++ {
			s[off+i] += float32(0.2 * (rnd.Float64()*2 - 1) * math.Exp(-float64(i)/80))
		}
	}
	// A pad under everything, so silence is not the clue.
	for i := range s {
		s[i] += float32(0.05 * math.Sin(2*math.Pi*220*float64(i)/float64(rate)))
	}
	return s
}

func TestBeatsFindTempoPhaseAndBreakdown(t *testing.T) {
	for _, bpm := range []float64{126, 138, 145} {
		phase := 0.31
		b, err := AnalyzeBeats(synthTrack(bpm, phase, 40, 32, 48), beatRate, 0)
		if err != nil {
			t.Fatal(err)
		}
		if math.Abs(b.BPM-bpm) > 0.1 {
			t.Fatalf("%g BPM: našel %.3f", bpm, b.BPM)
		}
		// Every beat within 8 ms of the truth (one envelope frame is 5.8 ms).
		for k, got := range b.Times {
			want := phase + float64(k)*60/bpm
			for want < got-30/bpm { // grid may start a beat later
				k++
				want = phase + float64(k)*60/bpm
			}
			if math.Abs(got-want) > 0.008 {
				t.Fatalf("%g BPM: doba %d v %.4f s, má být %.4f", bpm, k, got, want)
			}
		}
		bd := 0
		for _, x := range b.Breakdown {
			if x {
				bd++
			}
		}
		if bd < 14 || bd > 17 {
			t.Fatalf("%g BPM: breakdown 16 dob, našel %d", bpm, bd)
		}
		if b.Bar != 0 { // first kick after the breakdown: beat 48
			t.Fatalf("takt má začínat dobou 0 mod 4, ne %d", b.Bar)
		}
	}
}

func TestBeatsHintAvoidsHalfTempo(t *testing.T) {
	b, err := AnalyzeBeats(synthTrack(128, 0.1, 30, 1000, 1000), beatRate, 128)
	if err != nil || math.Abs(b.BPM-128) > 0.1 {
		t.Fatalf("s nápovědou 128: %v %v", b, err)
	}
}

// gridBeats: an exact grid, for the planner tests.
func gridBeats(bpm, seconds float64, bdFrom, bdTo int) *Beats {
	b := &Beats{BPM: bpm, Duration: seconds}
	for t := 0.0; t < seconds; t += 60 / bpm {
		b.Times = append(b.Times, t)
		b.Strength = append(b.Strength, 1)
		b.Breakdown = append(b.Breakdown, len(b.Times)-1 >= bdFrom && len(b.Times)-1 < bdTo)
	}
	return b
}

func TestSyncCutsOnBeatsAndSplitsByTrack(t *testing.T) {
	col := mustLoad(t, fixture(t))
	// 120 BPM = 0.5 s a beat; a 4 s track holds 8 beats.
	sb := mustPlan(t, col, "name: m\nsource: {runs: ["+runA+", "+runB+"]}\n"+
		"time: {axes: [model, prompt, style], fade: 0, sync: {audio: x.mp3, every: 1, breakdown: 0}}\n")
	slides := len(sb.Slides)
	if err := syncWith(sb, gridBeats(120, 4, 99, 99), "x.mp3", ""); err != nil {
		t.Fatal(err)
	}
	got := 0
	for _, v := range sb.Videos {
		got += v.To - v.From
		if v.Seconds > 4+1e-9 {
			t.Fatalf("%s: %.2f s je delší než skladba", v.Name, v.Seconds)
		}
		for k := 1; k < len(v.Times); k++ {
			if d := v.Times[k] - v.Times[k-1]; d < 0.5-1e-9 {
				t.Fatalf("%s: snímek %d trvá %.3f s, doba je 0.5 s", v.Name, k, d)
			}
			if r := math.Mod(v.Times[k]+1e-9, 0.5); r > 1e-6 {
				t.Fatalf("%s: střih v %.3f s není na dobu", v.Name, v.Times[k])
			}
		}
		// Parts never mix models: the outer axis is kept whole.
		m := sb.Slides[v.From].Key[AxModel]
		for k := v.From; k < v.To; k++ {
			if sb.Slides[k].Key[AxModel] != m {
				t.Fatalf("%s míchá modely", v.Name)
			}
		}
	}
	if got != slides {
		t.Fatalf("rozdělením se snímky nesmí ztratit: %d z %d", got, slides)
	}
	if len(sb.Videos) < 2 || !strings.HasSuffix(sb.Videos[0].Name, "-01") {
		t.Fatalf("delší než skladba → víc dílů: %+v", sb.Videos)
	}
}

func TestSyncSlowsDownInBreakdown(t *testing.T) {
	col := mustLoad(t, fixture(t))
	sb := mustPlan(t, col, "source: {runs: ["+runB+"]}\ntime: {axes: [prompt, style, model], fade: 0, "+
		"sync: {audio: x.mp3, every: 0.5, breakdown: 2}}\n")
	// Beats 2–3 have no kick: half-beat slides before, two-beat slides inside.
	if err := syncWith(sb, gridBeats(120, 60, 2, 4), "x.mp3", ""); err != nil {
		t.Fatal(err)
	}
	v := sb.Videos[0]
	want := []float64{0, 0.25, 0.5, 0.75, 1, 2, 2.25}
	for i, w := range want {
		if i >= len(v.Times) || math.Abs(v.Times[i]-w) > 1e-9 {
			t.Fatalf("časy %v, čekám začátek %v", v.Times, want)
		}
	}
	if v.Fades[4] != 0.5 || v.Fades[0] != 0 {
		t.Fatalf("v breakdownu prolínačka, jinde tvrdý střih: %v", v.Fades[:6])
	}
}

func TestSyncValidation(t *testing.T) {
	_, err := ParseRecipes([]byte("source: {runs: [a]}\ntime: {sync: {every: 0.5}}\noutput: {max_seconds: 30}\n"))
	if err == nil || !strings.Contains(err.Error(), "sync.audio") || !strings.Contains(err.Error(), "max_seconds") {
		t.Fatalf("sync bez skladby a s max_seconds: %v", err)
	}
}
