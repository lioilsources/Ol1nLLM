package main

import (
	"fmt"
	"sort"
)

// The rules that turn rated images into a value the app may use — and, far
// more often, into a refusal to name one.
//
// Everything here is a pure function of eval rows. No HTTP, no templates, no
// clock: `lab learn` fetches and emits, this file decides, and the tests can
// therefore state a rule as a table instead of a scenario.
//
// The guards are deliberately strict. At ~36 ratings a 71 % arm and a 27 % arm
// barely pull their Wilson intervals apart (see the gallery README), so any
// rule loose enough to "usually produce an answer" is a rule that produces
// noise. When the intervals still overlap the answer is "don't know yet", and
// the generated file has to say so rather than pick the bigger number.

const (
	// A style whose upper bound is below this is one the model demonstrably
	// does not do — 35 % is low enough that no plausible true rate above it
	// survives the interval, and high enough not to fire on thin samples.
	styleWeakUpper = 0.35
	// Above this lower bound the style is worth pointing at. Informational
	// only: the picker never reorders on it (I5).
	styleStrongLower = 0.75
)

// Decision is an answer or a documented refusal. Reason is filled in either
// way — a fallback without a reason is indistinguishable from "nobody looked".
type Decision[T any] struct {
	// Value nil = keep the app's own constant.
	Value  *T
	Reason string
	// N and Lower describe the winning arm, and stay zero on a fallback.
	N     int
	Lower float64
}

func (d Decision[T]) Decided() bool { return d.Value != nil }

// Candidate is one arm of a comparison: an addressable key, a human label and
// the cell that was measured for it.
type Candidate struct {
	Key   string
	Label string
	Cell  *EvalCell
}

// decideWinner implements the "clear winner" rule.
//
//	candidates  = arms with rated >= min
//	none        → fallback, "no arm reached min"
//	winner      = highest Wilson lower bound
//	overlap     → fallback, naming both intervals
//	otherwise   → winner, quoting the separation
//
// Non-overlap, not "highest mean", is the bar. The gallery's own leaderboard
// ranks by lower bound and stops there; a leader is "the best evidence so
// far", which is not the same claim as "better than the next one" — and only
// the second claim justifies changing what the app does by default.
func decideWinner(cands []Candidate, min int) Decision[Candidate] {
	var eligible []Candidate
	for _, c := range cands {
		if c.Cell != nil && c.Cell.Rated >= min && c.Cell.Lower != nil {
			eligible = append(eligible, c)
		}
	}
	if len(eligible) == 0 {
		return Decision[Candidate]{
			Reason: fmt.Sprintf("žádné rameno nedosáhlo min=%d (%s)",
				min, describeArms(cands)),
		}
	}
	// Sort by lower bound, ties broken by key so the same input always yields
	// the same output — a golden test on the emitted file needs that.
	sort.SliceStable(eligible, func(i, j int) bool {
		li, lj := *eligible[i].Cell.Lower, *eligible[j].Cell.Lower
		if li != lj {
			return li > lj
		}
		return eligible[i].Key < eligible[j].Key
	})
	win := eligible[0]
	if len(eligible) == 1 {
		// One arm cleared the threshold. There is nothing to be better than,
		// so this is evidence the value works, not that it beats the others.
		return Decision[Candidate]{
			Value: &eligible[0],
			Reason: fmt.Sprintf("jediné rameno nad prahem: %s %s, n=%d",
				win.Label, pctRange(win.Cell), win.Cell.Rated),
			N:     win.Cell.Rated,
			Lower: *win.Cell.Lower,
		}
	}
	run := eligible[1]
	if *win.Cell.Lower <= *run.Cell.Upper {
		return Decision[Candidate]{
			Reason: fmt.Sprintf("intervaly se překrývají: %s %s vs %s %s",
				win.Label, pctRange(win.Cell), run.Label, pctRange(run.Cell)),
		}
	}
	return Decision[Candidate]{
		Value: &eligible[0],
		Reason: fmt.Sprintf("dolní mez %.2f > horní %.2f druhého (%s), n=%d/%d",
			*win.Cell.Lower, *run.Cell.Upper, run.Label,
			win.Cell.Rated, run.Cell.Rated),
		N:     win.Cell.Rated,
		Lower: *win.Cell.Lower,
	}
}

// StyleVerdict mirrors the Dart enum; "" means no flag.
type StyleVerdict string

const (
	StyleWeak   StyleVerdict = "weak"
	StyleStrong StyleVerdict = "strong"
)

type StyleFlag struct {
	Verdict StyleVerdict
	Reason  string
}

// decideStyleFlag flags a style on a model. It never hides and never reorders:
// a hidden style stops collecting ratings and can therefore never come back,
// which turns one thin sample into a permanent verdict (I5).
func decideStyleFlag(cell *EvalCell, min int) (StyleFlag, bool) {
	if cell == nil || cell.Rated < min || cell.Lower == nil || cell.Upper == nil {
		return StyleFlag{}, false
	}
	switch {
	case *cell.Upper < styleWeakUpper:
		return StyleFlag{StyleWeak, fmt.Sprintf("like %s, n=%d",
			pctRange(cell), cell.Rated)}, true
	case *cell.Lower > styleStrongLower:
		return StyleFlag{StyleStrong, fmt.Sprintf("like %s, n=%d",
			pctRange(cell), cell.Rated)}, true
	}
	return StyleFlag{}, false
}

// LearnedRate is a cell transcribed for emission — no guard, no decision. The
// UI shows n next to it and the reader judges; a per-model note that hid its
// own sample size would be worse than no note.
type LearnedRate struct {
	Value float64
	Lower float64
	Upper float64
	N     int
}

func rateOf(cell *EvalCell) *LearnedRate {
	if cell == nil || cell.Rated == 0 || cell.Rate == nil ||
		cell.Lower == nil || cell.Upper == nil {
		return nil
	}
	return &LearnedRate{*cell.Rate, *cell.Lower, *cell.Upper, cell.Rated}
}

// pctRange renders an interval the way the reason lines quote it.
func pctRange(c *EvalCell) string {
	if c == nil || c.Lower == nil || c.Upper == nil {
		return "?"
	}
	return fmt.Sprintf("%.0f–%.0f %%", *c.Lower*100, *c.Upper*100)
}

// describeArms says what was there instead of what was needed, so a fallback
// reads as "hodnoť víc" rather than "nic nenalezeno".
func describeArms(cands []Candidate) string {
	if len(cands) == 0 {
		return "žádná ramena"
	}
	sorted := append([]Candidate(nil), cands...)
	sort.SliceStable(sorted, func(i, j int) bool { return sorted[i].Key < sorted[j].Key })
	out := ""
	for i, c := range sorted {
		if i > 0 {
			out += ", "
		}
		n := 0
		if c.Cell != nil {
			n = c.Cell.Rated
		}
		out += fmt.Sprintf("%s n=%d", c.Label, n)
	}
	return out
}
