package main

import (
	"flag"
	"fmt"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// `lab learn` — the step that makes each release know more than the last one.
//
//	gallery eval → decide.go → lib/generated/learned.dart → git diff → release
//
// Learning happens at build time on purpose. The alternative (the app pulling
// eval at runtime) needs a cache, a fallback and an invalidation story, moves
// CF Access into the phone, and makes "what did the app see" unanswerable
// after the fact. Here the knowledge is a committed file: it works offline, a
// release is a diffable snapshot, and every behaviour change goes past a human
// in review — which is the app's own rule that auto-selection must never be
// silent, satisfied by construction.
//
// The generator never touches kImageModels or kStylePresets. Those ids are
// persisted on nodes and exported to the gallery; a bad run that rewrote them
// would detach every rating already collected. This emits a separate overlay
// and nothing else.

// ── the shape of GET /api/eval ─────────────────────────────

type EvalCell struct {
	Up       int      `json:"up"`
	Down     int      `json:"down"`
	Rated    int      `json:"rated"`
	Eligible int      `json:"eligible"`
	Rate     *float64 `json:"rate"`
	Lower    *float64 `json:"lower"`
	Upper    *float64 `json:"upper"`
}

type EvalRow struct {
	Key      string               `json:"key"`
	Label    string               `json:"label"`
	N        int                  `json:"n"`
	Liked    int                  `json:"liked"`
	Disliked int                  `json:"disliked"`
	Unrated  int                  `json:"unrated"`
	Like     EvalCell             `json:"like"`
	Criteria map[string]*EvalCell `json:"criteria"`
}

type EvalResponse struct {
	Group    string     `json:"group"`
	Groups   []string   `json:"groups"`
	Criteria []string   `json:"criteria"`
	MinRated int        `json:"minRated"`
	Rows     []*EvalRow `json:"rows"`
	Total    EvalRow    `json:"total"`
}

// ── what a run of the generator produced ───────────────────

type LearnedModelFacts struct {
	PoseAdherence  *LearnedRate
	SourceIdentity *LearnedRate
	SourceStyle    *LearnedRate
	LikeRate       *LearnedRate
}

func (m LearnedModelFacts) empty() bool {
	return m.PoseAdherence == nil && m.SourceIdentity == nil &&
		m.SourceStyle == nil && m.LikeRate == nil
}

// intents are the app's GenIntent enum, in the order they are emitted.
var intents = []string{"txt2img", "img2img", "repose"}

// nowUTC is a variable so the golden test can pin the snapshot. Nothing else
// in the generator reads a clock — the emitted file has to be a pure function
// of the eval it was built from, or the golden diff is noise.
var nowUTC = func() time.Time { return time.Now().UTC() }

type Learned struct {
	SnapshotAt  string
	GalleryHost string
	RatedImages int
	TotalImages int
	MinRatings  int
	// SessionCount is every session that contributed; Sessions holds only the
	// lab run ids among them (app sessions have no id worth quoting).
	SessionCount int
	Sessions     []string

	Models       map[string]LearnedModelFacts
	LoraStrength map[string]Decision[float64]
	DefaultModel map[string]Decision[Candidate] // intent → decision
	StyleFlags   map[string]map[string]StyleFlag
}

// Decisions counts what actually got decided, which is the number worth
// looking at in --dry: on a young corpus it should be much smaller than the
// number of fallbacks, and a guard that "usually produces an answer" is a
// guard set too loose.
func (l *Learned) Decisions() (decided, fallback int) {
	for _, d := range l.LoraStrength {
		if d.Decided() {
			decided++
		} else {
			fallback++
		}
	}
	for _, d := range l.DefaultModel {
		if d.Decided() {
			decided++
		} else {
			fallback++
		}
	}
	return
}

// ── the command ────────────────────────────────────────────

func learnCLI(env *Env, args []string) error {
	fs := flag.NewFlagSet("learn", flag.ExitOnError)
	out := fs.String("out", "lib/generated/learned.dart", "kam zapsat (relativně ke kořeni repa)")
	min := fs.Int("min", 10, "kolik hodnocení musí rameno mít, aby se počítalo")
	dry := fs.Bool("dry", false, "jen vypsat rozhodnutí a diff, nic nezapisovat")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *min < 1 {
		// min=0 would make every arm eligible, including one-off ratings, and
		// the "clear winner" rule would start naming winners out of noise.
		return fmt.Errorf("--min musí být aspoň 1 (dostal jsem %d)", *min)
	}

	learned, err := Learn(env.Finetune, *min)
	if err != nil {
		return err
	}
	dart := EmitDart(learned)

	path := *out
	if !filepath.IsAbs(path) {
		path = filepath.Join(env.RepoRoot, path)
	}

	printLearnSummary(learned)

	old, readErr := os.ReadFile(path)
	if readErr == nil && string(old) == dart {
		fmt.Println("\nbeze změny — " + rel(env.RepoRoot, path))
		return nil
	}
	if *dry {
		fmt.Println()
		if readErr != nil {
			fmt.Printf("nový soubor %s (%d řádků)\n", rel(env.RepoRoot, path),
				strings.Count(dart, "\n"))
		} else {
			printDiff(rel(env.RepoRoot, path), string(old), dart)
		}
		fmt.Println("\nnic nezapsáno — spusť znovu bez --dry")
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(path, []byte(dart), 0o644); err != nil {
		return err
	}
	fmt.Printf("\nzapsáno %s — projdi `git diff`, ta změna je release note\n",
		rel(env.RepoRoot, path))
	return nil
}

// Learn fetches every slice the rules need and applies them.
//
// Without credentials or without the network this returns an error and writes
// nothing. Emitting an empty overlay instead would satisfy "never worse than
// today" — and would silently delete everything already learned, which is the
// same failure wearing a friendlier face.
func Learn(ft *Finetune, min int) (*Learned, error) {
	if !ft.HasCreds() {
		return nil, fmt.Errorf("chybí CF_ACCESS_CLIENT_ID / CF_ACCESS_CLIENT_SECRET (viz .env.local) — bez nich se eval nedá přečíst")
	}

	// The four top-level slices are independent, so they go together.
	var (
		byModel, byLora, bySession *EvalResponse
		errs                       [3]error
		wg                         sync.WaitGroup
	)
	wg.Add(3)
	go func() { defer wg.Done(); byModel, errs[0] = ft.Eval("model", nil) }()
	go func() { defer wg.Done(); byLora, errs[1] = ft.Eval("lora", nil) }()
	go func() { defer wg.Done(); bySession, errs[2] = ft.Eval("session", nil) }()
	wg.Wait()
	for _, err := range errs {
		if err != nil {
			return nil, err
		}
	}

	l := &Learned{
		SnapshotAt:   nowUTC().Format(time.RFC3339),
		GalleryHost:  hostOf(ft.Base),
		RatedImages:  byModel.Total.Liked + byModel.Total.Disliked,
		TotalImages:  byModel.Total.N,
		MinRatings:   min,
		Models:       map[string]LearnedModelFacts{},
		LoraStrength: map[string]Decision[float64]{},
		DefaultModel: map[string]Decision[Candidate]{},
		StyleFlags:   map[string]map[string]StyleFlag{},
	}
	// Provenance is the run, never the prompt. A session's title *is* the
	// user's prompt, and 119 of them would put that text into a committed,
	// reviewed source file — noise at best, and not ours to publish. The lab
	// tags its own sessions "<prompt> [lab <id>]", so the id is both short and
	// the thing anyone would actually trace back.
	for _, r := range bySession.Rows {
		if r.Key == "" {
			continue
		}
		l.SessionCount++
		if id := labRunID(r.Label); id != "" {
			l.Sessions = append(l.Sessions, id)
		}
	}
	sort.Strings(l.Sessions)

	learnModels(l, byModel)
	learnDefaultModel(l, byModel, min)
	learnLoraStrength(l, byLora, min)

	// Style flags are per model, so this fan-out is as wide as the model list.
	if err := learnStyleFlags(l, ft, byModel, min); err != nil {
		return nil, err
	}
	return l, nil
}

// learnModels transcribes the per-model cells. No guard: this is the picker's
// replacement for a hand-written sentence, and a number with its n attached is
// already more honest than prose.
func learnModels(l *Learned, byModel *EvalResponse) {
	for _, r := range byModel.Rows {
		if r.Key == "" {
			continue // "(unknown model)" — nothing the app can key on
		}
		facts := LearnedModelFacts{
			PoseAdherence:  rateOf(r.Criteria["pose_adherence"]),
			SourceIdentity: rateOf(r.Criteria["source_identity"]),
			SourceStyle:    rateOf(r.Criteria["source_style"]),
			LikeRate:       rateOf(&r.Like),
		}
		if !facts.empty() {
			l.Models[r.Key] = facts
		}
	}
}

// learnDefaultModel picks the default model per intent.
//
// Repose is decided on pose_adherence, not on like (I6): like is taste, and
// holding a pose is a fact about the output against its reference. The other
// two intents have no relational criterion of their own — nothing in the
// gallery says "this image was a txt2img" — so they fall back to like, and
// their guard has to carry the weight instead.
func learnDefaultModel(l *Learned, byModel *EvalResponse, min int) {
	like := make([]Candidate, 0, len(byModel.Rows))
	pose := make([]Candidate, 0, len(byModel.Rows))
	for _, r := range byModel.Rows {
		if r.Key == "" {
			continue
		}
		like = append(like, Candidate{r.Key, r.Label, &r.Like})
		// pose_adherence's eligibility counts only images with a pose template,
		// so a repose round (which has none — the reference *is* the pose)
		// understates coverage. The up/down tally it is judged on is unaffected.
		if c := r.Criteria["pose_adherence"]; c != nil {
			pose = append(pose, Candidate{r.Key, r.Label, c})
		}
	}
	for _, intent := range intents {
		switch intent {
		case "repose":
			l.DefaultModel[intent] = decideWinner(pose, min)
		default:
			l.DefaultModel[intent] = decideWinner(like, min)
		}
	}
}

// learnLoraStrength decides, per LoRA file, which strength to default to.
//
// The gallery groups LoRA runs by "name @ strength" precisely because the name
// alone cannot tell a 0.4 run from a 1.4 one. Splitting that key back apart
// turns one row set into one comparison per file, which is the question worth
// asking: not "is this LoRA good" but "at what strength".
func learnLoraStrength(l *Learned, byLora *EvalResponse, min int) {
	arms := map[string][]Candidate{}
	for _, r := range byLora.Rows {
		if r.Key == "" {
			continue // "(no LoRA)" is not a strength of anything
		}
		name, strength, ok := strings.Cut(r.Key, " @ ")
		if !ok {
			// A run recorded before schema v2 has a name and no strength. It
			// cannot be an arm in a comparison of strengths — including it
			// would let an unknown value win.
			continue
		}
		arms[name] = append(arms[name], Candidate{strength, strength + " síla", &r.Like})
	}
	for name, cands := range arms {
		if len(cands) < 2 {
			// One strength ever tried is not a comparison. Saying so is more
			// useful than emitting the only value as if it had won something.
			l.LoraStrength[name] = Decision[float64]{
				Reason: fmt.Sprintf("jen jedna síla kdy zkoušená (%s) — není co porovnat",
					describeArms(cands)),
			}
			continue
		}
		d := decideWinner(cands, min)
		if !d.Decided() {
			l.LoraStrength[name] = Decision[float64]{Reason: d.Reason}
			continue
		}
		v, err := strconv.ParseFloat(d.Value.Key, 64)
		if err != nil {
			l.LoraStrength[name] = Decision[float64]{
				Reason: fmt.Sprintf("nečitelná síla %q v klíči evalu", d.Value.Key),
			}
			continue
		}
		l.LoraStrength[name] = Decision[float64]{
			Value: &v, Reason: d.Reason, N: d.N, Lower: d.Lower,
		}
	}
}

// learnStyleFlags asks the gallery for the style breakdown of each model. One
// request per model: the scope filter is what makes a two-dimensional view out
// of a one-dimensional endpoint.
func learnStyleFlags(l *Learned, ft *Finetune, byModel *EvalResponse, min int) error {
	var models []string
	for _, r := range byModel.Rows {
		if r.Key != "" {
			models = append(models, r.Key)
		}
	}
	sort.Strings(models)

	type result struct {
		model string
		resp  *EvalResponse
		err   error
	}
	out := make([]result, len(models))
	var wg sync.WaitGroup
	for i, m := range models {
		wg.Add(1)
		go func(i int, m string) {
			defer wg.Done()
			resp, err := ft.Eval("style", map[string]string{"model": m})
			out[i] = result{m, resp, err}
		}(i, m)
	}
	wg.Wait()

	for _, r := range out {
		if r.err != nil {
			return r.err
		}
		flags := map[string]StyleFlag{}
		for _, row := range r.resp.Rows {
			if row.Key == "" {
				continue // "(no style)" is the baseline, not a style
			}
			if f, ok := decideStyleFlag(&row.Like, min); ok {
				flags[row.Key] = f
			}
		}
		if len(flags) > 0 {
			l.StyleFlags[r.model] = flags
		}
	}
	return nil
}

// ── emitting Dart ──────────────────────────────────────────

// EmitDart renders the overlay. Deterministic by construction — every map is
// walked in sorted key order — so re-running on unchanged data produces a
// byte-identical file and `git diff` shows only what actually moved.
func EmitDart(l *Learned) string {
	var b strings.Builder
	b.WriteString("// GENERATED by `lab learn` — do not edit. Regenerate before release.\n")
	fmt.Fprintf(&b, "// snapshot: %s  gallery: %s\n", l.SnapshotAt, l.GalleryHost)
	fmt.Fprintf(&b, "// eval: %d obrázků, %d hodnocených, práh %d\n",
		l.TotalImages, l.RatedImages, l.MinRatings)
	fmt.Fprintf(&b, "// sessions: %d", l.SessionCount)
	if len(l.Sessions) > 0 {
		fmt.Fprintf(&b, " · lab: %s", joinCapped(l.Sessions, 6))
	}
	b.WriteString("\n")
	b.WriteString("//\n")
	b.WriteString("// A `null` below is not a gap — it is a measured refusal, with the reason\n")
	b.WriteString("// on the line above it. The app then keeps its own constant.\n")
	// A package import, not a relative one: the same text then also compiles
	// as test/fixtures/learned_golden.dart, which is how the analyzer gets to
	// prove this emitter produces valid Dart at all.
	b.WriteString("\nimport 'package:ol1n_llm/models/learned.dart';\n\nconst kLearned = Learned(\n")
	fmt.Fprintf(&b, "  snapshotAt: %s,\n", dartString(l.SnapshotAt))
	fmt.Fprintf(&b, "  ratedImages: %d,\n", l.RatedImages)
	fmt.Fprintf(&b, "  totalImages: %d,\n", l.TotalImages)
	fmt.Fprintf(&b, "  minRatings: %d,\n", l.MinRatings)

	emitModels(&b, l)
	emitLoraStrength(&b, l)
	emitDefaultModel(&b, l)
	emitStyleFlags(&b, l)

	b.WriteString(");\n")
	return b.String()
}

func emitModels(b *strings.Builder, l *Learned) {
	if len(l.Models) == 0 {
		b.WriteString("  // Žádný model zatím nemá hodnocení — picker ukazuje styleNote jako dřív.\n")
		b.WriteString("  models: {},\n")
		return
	}
	b.WriteString("  models: {\n")
	for _, id := range sortedKeys(l.Models) {
		m := l.Models[id]
		fmt.Fprintf(b, "    %s: LearnedModel(\n", dartString(id))
		emitRate(b, "poseAdherence", m.PoseAdherence)
		emitRate(b, "sourceIdentity", m.SourceIdentity)
		emitRate(b, "sourceStyle", m.SourceStyle)
		emitRate(b, "likeRate", m.LikeRate)
		b.WriteString("    ),\n")
	}
	b.WriteString("  },\n")
}

func emitRate(b *strings.Builder, name string, r *LearnedRate) {
	if r == nil {
		return
	}
	fmt.Fprintf(b, "      %s: Rate(%s, lower: %s, upper: %s, n: %d),\n",
		name, dartRate(r.Value), dartRate(r.Lower), dartRate(r.Upper), r.N)
}

func emitLoraStrength(b *strings.Builder, l *Learned) {
	decided := 0
	for _, d := range l.LoraStrength {
		if d.Decided() {
			decided++
		}
	}
	if decided == 0 {
		b.WriteString("  // Žádná LoRA nemá dvě rozpojená ramena síly.\n")
		for _, name := range sortedKeys(l.LoraStrength) {
			fmt.Fprintf(b, "  //   %s: %s\n", name, l.LoraStrength[name].Reason)
		}
		b.WriteString("  loraStrength: {},\n")
		return
	}
	b.WriteString("  loraStrength: {\n")
	for _, name := range sortedKeys(l.LoraStrength) {
		d := l.LoraStrength[name]
		if !d.Decided() {
			// Refusals stay visible as comments: an empty line here would look
			// like nobody ever ran this LoRA at two strengths.
			fmt.Fprintf(b, "    // %s: %s\n", name, d.Reason)
			continue
		}
		fmt.Fprintf(b, "    %s: LearnedValue(%s, reason: %s),\n",
			dartString(name), dartDouble(*d.Value), dartString(d.Reason))
	}
	b.WriteString("  },\n")
}

func emitDefaultModel(b *strings.Builder, l *Learned) {
	b.WriteString("  defaultModel: {\n")
	for _, intent := range intents {
		d, ok := l.DefaultModel[intent]
		if !ok {
			continue
		}
		if !d.Decided() {
			fmt.Fprintf(b, "    // %s\n", d.Reason)
			fmt.Fprintf(b, "    GenIntent.%s: null,\n", intent)
			continue
		}
		fmt.Fprintf(b, "    GenIntent.%s: LearnedChoice(%s, reason: %s),\n",
			intent, dartString(d.Value.Key), dartString(d.Reason))
	}
	b.WriteString("  },\n")
}

func emitStyleFlags(b *strings.Builder, l *Learned) {
	if len(l.StyleFlags) == 0 {
		b.WriteString("  // Žádný styl na žádném modelu nevyšel dost jednoznačně na příznak.\n")
		b.WriteString("  styleFlags: {},\n")
		return
	}
	b.WriteString("  styleFlags: {\n")
	for _, model := range sortedKeys(l.StyleFlags) {
		fmt.Fprintf(b, "    %s: {\n", dartString(model))
		byStyle := l.StyleFlags[model]
		for _, style := range sortedKeys(byStyle) {
			f := byStyle[style]
			fmt.Fprintf(b, "      %s: StyleFlag.%s(reason: %s),\n",
				dartString(style), f.Verdict, dartString(f.Reason))
		}
		b.WriteString("    },\n")
	}
	b.WriteString("  },\n")
}

// ── printing ───────────────────────────────────────────────

func printLearnSummary(l *Learned) {
	decided, fallback := l.Decisions()
	fmt.Printf("galerie   %s\n", l.GalleryHost)
	fmt.Printf("eval      %d obrázků, %d hodnocených, práh %d\n",
		l.TotalImages, l.RatedImages, l.MinRatings)
	fmt.Printf("rozhodnut %d · fallback %d\n\n", decided, fallback)

	fmt.Println("výchozí model")
	for _, intent := range intents {
		d := l.DefaultModel[intent]
		if d.Decided() {
			fmt.Printf("  %-8s → %-16s %s\n", intent, d.Value.Key, d.Reason)
		} else {
			fmt.Printf("  %-8s   (zůstává v kódu)  %s\n", intent, d.Reason)
		}
	}
	if len(l.LoraStrength) > 0 {
		fmt.Println("\nsíla LoRA")
		for _, name := range sortedKeys(l.LoraStrength) {
			d := l.LoraStrength[name]
			if d.Decided() {
				fmt.Printf("  %-28s → %-5s %s\n", name, dartDouble(*d.Value), d.Reason)
			} else {
				fmt.Printf("  %-28s   (zůstává v kódu)  %s\n", name, d.Reason)
			}
		}
	}
	flags := 0
	for _, byStyle := range l.StyleFlags {
		flags += len(byStyle)
	}
	fmt.Printf("\npříznaky stylů  %d · modelů se znalostí  %d\n", flags, len(l.Models))
}

// printDiff is a plain line diff — enough to see what moved without pulling in
// a dependency for a file that is a few dozen lines long.
func printDiff(name, old, new string) {
	fmt.Printf("--- %s\n+++ %s (nový)\n", name, name)
	oldLines, newLines := strings.Split(old, "\n"), strings.Split(new, "\n")
	inOld := map[string]int{}
	for _, l := range oldLines {
		inOld[l]++
	}
	inNew := map[string]int{}
	for _, l := range newLines {
		inNew[l]++
	}
	for _, l := range oldLines {
		if inNew[l] == 0 && strings.TrimSpace(l) != "" {
			fmt.Println("- " + l)
		}
	}
	for _, l := range newLines {
		if inOld[l] == 0 && strings.TrimSpace(l) != "" {
			fmt.Println("+ " + l)
		}
	}
}

// ── small helpers ──────────────────────────────────────────

func sortedKeys[V any](m map[string]V) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// dartString quotes for Dart source. Single quotes and backslashes are the
// only things that can break out; reasons are generated text, but they carry
// LoRA filenames and style ids that came from a server.
func dartString(s string) string {
	r := strings.NewReplacer(`\`, `\\`, `'`, `\'`, "\n", `\n`, "$", `\$`)
	return "'" + r.Replace(s) + "'"
}

// dartRate rounds to three decimals. The app shows these as percentages, so
// the seventeen digits a float prints by default are noise — and worse, noise
// that reshuffles on the last digit between runs and fills the review diff
// with lines nobody can read. The decisions themselves are made in Go at full
// precision; only what gets written down is rounded.
func dartRate(v float64) string {
	return dartDouble(math.Round(v*1000) / 1000)
}

// dartDouble always renders a decimal point: `Rate(1, …)` would compile, but a
// file meant to be read by a human should not make its reader check whether
// Dart promotes int literals here.
func dartDouble(v float64) string {
	s := strconv.FormatFloat(v, 'f', -1, 64)
	if !strings.ContainsAny(s, ".eE") {
		s += ".0"
	}
	return s
}

func joinCapped(items []string, max int) string {
	if len(items) <= max {
		return strings.Join(items, ", ")
	}
	return strings.Join(items[:max], ", ") +
		fmt.Sprintf(" … (+%d)", len(items)-max)
}

// labRunID pulls the run id out of a lab-exported session title, which
// BuildExport writes as "<prompt> [lab <id>]" or "<prompt> [lab <id> · N
// modelů]". Anything else is an app session and contributes only to the count.
func labRunID(title string) string {
	i := strings.LastIndex(title, "[lab ")
	if i < 0 {
		return ""
	}
	rest := title[i+len("[lab "):]
	end := strings.IndexAny(rest, " ]")
	if end < 0 {
		return ""
	}
	return rest[:end]
}

func hostOf(base string) string {
	s := strings.TrimPrefix(strings.TrimPrefix(base, "https://"), "http://")
	return strings.TrimRight(strings.SplitN(s, "/", 2)[0], "/")
}

func rel(root, path string) string {
	if r, err := filepath.Rel(root, path); err == nil {
		return r
	}
	return path
}
