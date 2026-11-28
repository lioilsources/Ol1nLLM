package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/lioilsources/ol1n-lab/internal/video"
)

// lab video …: the video studio from the terminal (docs/plan-video-studio.md).
func videoCLI(env *Env, args []string) error {
	if len(args) == 0 {
		videoUsage()
		return nil
	}
	labDir := filepath.Join(env.RepoRoot, "build", "lab")
	switch args[0] {
	case "index":
		return videoIndexCLI(labDir, args[1:])
	case "coverage":
		return videoCoverageCLI(labDir, args[1:])
	case "suggest":
		return videoSuggestCLI(labDir, args[1:])
	case "new":
		return videoNewCLI(labDir, args[1:])
	case "plan":
		return videoPlanCLI(labDir, args[1:])
	case "render":
		return videoRenderCLI(labDir, args[1:])
	default:
		videoUsage()
		return fmt.Errorf("neznámý příkaz lab video %s", args[0])
	}
}

func videoUsage() {
	fmt.Fprint(os.Stderr, `lab video — videa napříč běhy (docs/plan-video-studio.md)

  lab video index [--min 50] [--refresh] [--json]
        rodiny běhů (stejné prompty), jejich modely, flow a počty obrázků
  lab video coverage (--runs a,b | --family BĚH) [--rows model] [--cols style] [--count prompt]
        [--where osa=hodnota …] [--json]
        matice: u kolika promptů má model daný styl
  lab video suggest (--runs a,b | --family BĚH) [--tiles model] [--loose style] [--k 4] [--top 3]
        [--where osa=hodnota …] [--json]
        které modely dát vedle sebe: úplné snímky striktně (stejný prompt i styl)
        a volně (stejný prompt, každý model svůj styl)
  lab video new (--runs a,b | --family BĚH) --template stroboskop|prulet|platno|mix [--name N] > recept.yaml
        kostra receptu se všemi osami, které běhy mají
  lab video plan recept.yaml [--slides] [--json]
        scénář: snímky, videa, délky, co vypadlo a proč — nic nerenderuje
  lab video render recept.yaml [--only jméno-01,jméno-02] [--out DIR] [--draft]
        MP4 do build/lab/_video/<jméno>/ (s receptem a souhrnem scénáře);
        --draft kreslí z náhledů 320 px — rychlý koncept, ne výsledek
`)
}

// parseArgs parses flags wherever they stand: `lab video plan r.yaml --json`
// as well as `lab video plan --json r.yaml`. Go's flag package stops at the
// first positional argument and would ignore everything after it.
func parseArgs(fs *flag.FlagSet, args []string) []string {
	var pos []string
	for {
		_ = fs.Parse(args)
		rest := fs.Args()
		if len(rest) == 0 {
			return pos
		}
		pos = append(pos, rest[0])
		args = rest[1:]
	}
}

type multiFlag []string

func (m *multiFlag) String() string     { return strings.Join(*m, ",") }
func (m *multiFlag) Set(v string) error { *m = append(*m, v); return nil }

func videoIndexCLI(labDir string, args []string) error {
	fs := flag.NewFlagSet("video index", flag.ExitOnError)
	minPics := fs.Int("min", 50, "jen běhy s aspoň tolika obrázky")
	refresh := fs.Bool("refresh", false, "zahodit cache indexu")
	asJSON := fs.Bool("json", false, "JSON")
	if extra := parseArgs(fs, args); len(extra) > 0 {
		return fmt.Errorf("nečekaný argument %q", extra[0])
	}
	if *refresh {
		if err := video.ClearCache(labDir); err != nil {
			return err
		}
	}
	col, err := video.Load(labDir)
	if err != nil {
		return err
	}
	fams := col.Families(*minPics)
	if *asJSON {
		return printJSON(map[string]any{"families": fams, "runs": col.Runs, "errors": col.Errors})
	}
	tw := tabwriter.NewWriter(os.Stdout, 0, 2, 2, ' ', 0)
	for i, f := range fams {
		kind := "promptů"
		if f.Scenes {
			kind = "scén"
		}
		fmt.Fprintf(tw, "\nrodina %d (%s) · %d %s · %d běhů · %d modelů · %d obrázků · flow %s\n",
			i+1, f.Key, f.Prompts, kind, len(f.Runs), len(f.Models), f.Pics, strings.Join(f.Flows, ", "))
		for _, r := range f.Runs {
			models := map[string]int{}
			var order []string
			for _, p := range r.Pics {
				if models[p.Model] == 0 {
					order = append(order, p.Model)
				}
				models[p.Model]++
			}
			var parts []string
			for _, m := range order {
				parts = append(parts, fmt.Sprintf("%s %d", m, models[m]))
			}
			note := ""
			if r.Empty > 0 {
				note = fmt.Sprintf("  ⚠ %d prázdných souborů", r.Empty)
			}
			if r.Placeholder {
				note += "  (nanečisto)"
			}
			fmt.Fprintf(tw, "  %s\t%s\t%d/%d\t%d stylů\t%s%s\n", r.ID, r.Status, len(r.Pics), r.Total,
				r.StyleCount(), strings.Join(parts, ", "), note)
		}
	}
	tw.Flush()
	small := 0
	for _, r := range col.Runs {
		if len(r.Pics) < *minPics {
			small++
		}
	}
	fmt.Printf("\n%d běhů, %d rodin; %d běhů pod %d obrázků vynecháno (--min 1 je ukáže)\n",
		len(col.Runs), len(fams), small, *minPics)
	for _, e := range col.Errors {
		fmt.Println("⚠", e)
	}
	return nil
}

// poolFlags are the run selection shared by coverage and suggest.
type poolFlags struct {
	runs, family, identity, prefer *string
	where                          multiFlag
}

func addPoolFlags(fs *flag.FlagSet) *poolFlags {
	pf := &poolFlags{
		runs:     fs.String("runs", "", "běhy čárkami"),
		family:   fs.String("family", "", "všechny běhy z rodiny tohoto běhu"),
		identity: fs.String("identity", "", "identita promptu: scene | column (výchozí podle běhů)"),
		prefer:   fs.String("prefer", "first", "dvakrát tentýž obrázek: first | newest | error"),
	}
	fs.Var(&pf.where, "where", "filtr osa=hodnota (opakovatelné)")
	return pf
}

func (pf *poolFlags) pool(labDir string) (*video.Pool, error) {
	col, err := video.Load(labDir)
	if err != nil {
		return nil, err
	}
	var runs []*video.Run
	switch {
	case *pf.runs != "":
		for _, id := range strings.Split(*pf.runs, ",") {
			id = strings.TrimSpace(id)
			r := col.Run(id)
			if r == nil {
				return nil, fmt.Errorf("běh %s v build/lab není", id)
			}
			runs = append(runs, r)
		}
	case *pf.family != "":
		runs = col.FamilyOf(*pf.family)
		if runs == nil {
			return nil, fmt.Errorf("běh %s v build/lab není nebo nemá obrázky", *pf.family)
		}
	default:
		return nil, fmt.Errorf("chybí --runs nebo --family")
	}
	pool, err := video.NewPool(runs, *pf.identity, *pf.prefer)
	if err != nil {
		return nil, err
	}
	sel, err := video.ParseWhere(pf.where)
	if err != nil {
		return nil, err
	}
	pool = pool.Select(sel)
	if len(pool.Pics) == 0 {
		return nil, fmt.Errorf("výběru neodpovídá žádný obrázek")
	}
	if pool.DifferentSetups > 0 {
		fmt.Fprintf(os.Stderr, "⚠ %d obrázků je ve víc bězích s jiným nastavením (seed, síla úpravy…); bere se %s\n",
			pool.DifferentSetups, *pf.prefer)
	}
	return pool, nil
}

func videoCoverageCLI(labDir string, args []string) error {
	fs := flag.NewFlagSet("video coverage", flag.ExitOnError)
	pf := addPoolFlags(fs)
	rows := fs.String("rows", video.AxModel, "osa řádků")
	cols := fs.String("cols", video.AxStyle, "osa sloupců")
	count := fs.String("count", video.AxPrompt, "co se v buňce počítá")
	asJSON := fs.Bool("json", false, "JSON")
	if extra := parseArgs(fs, args); len(extra) > 0 {
		return fmt.Errorf("nečekaný argument %q", extra[0])
	}
	pool, err := pf.pool(labDir)
	if err != nil {
		return err
	}
	cov, err := pool.Coverage(*rows, *cols, *count)
	if err != nil {
		return err
	}
	if *asJSON {
		return printJSON(cov)
	}
	tw := tabwriter.NewWriter(os.Stdout, 0, 2, 1, ' ', tabwriter.AlignRight)
	// Many styles do not fit a terminal: then a column per style kind, the
	// cell saying how many (style, prompt) pairs of that kind are covered.
	if *cols == video.AxStyle && len(cov.Cols) > 16 {
		kinds := []string{}
		kindCols := map[string][]int{}
		for j, c := range cov.Cols {
			k := c.Kind
			if c.ID == video.Baseline {
				k = "bez stylu"
			} else if k == "" {
				k = "jiné"
			}
			if kindCols[k] == nil {
				kinds = append(kinds, k)
			}
			kindCols[k] = append(kindCols[k], j)
		}
		fmt.Fprintf(tw, "\t%s\t\n", strings.Join(kinds, "\t"))
		for i, r := range cov.Rows {
			cells := []string{}
			for _, k := range kinds {
				got := 0
				for _, j := range kindCols[k] {
					got += cov.Cells[i][j]
				}
				cells = append(cells, fmt.Sprintf("%d%%", 100*got/max(1, len(kindCols[k])*cov.Of)))
			}
			fmt.Fprintf(tw, "%s\t%s\t\n", r.Label, strings.Join(cells, "\t"))
		}
		tw.Flush()
		fmt.Printf("\nbuňka = kolik dvojic (styl, %s) daného druhu má obrázek; %d stylů ve sloupcích po druzích (--json ukáže všechny)\n",
			*count, len(cov.Cols))
		return nil
	}
	heads := []string{}
	for _, c := range cov.Cols {
		heads = append(heads, truncate(c.Label, 14))
	}
	fmt.Fprintf(tw, "\t%s\t\n", strings.Join(heads, "\t"))
	for i, r := range cov.Rows {
		cells := []string{}
		for _, n := range cov.Cells[i] {
			cells = append(cells, fmt.Sprint(n))
		}
		fmt.Fprintf(tw, "%s\t%s\t\n", r.Label, strings.Join(cells, "\t"))
	}
	tw.Flush()
	fmt.Printf("\nbuňka = počet hodnot osy %s z %d\n", *count, cov.Of)
	return nil
}

func videoSuggestCLI(labDir string, args []string) error {
	fs := flag.NewFlagSet("video suggest", flag.ExitOnError)
	pf := addPoolFlags(fs)
	tiles := fs.String("tiles", video.AxModel, "osa dlaždic")
	loose := fs.String("loose", video.AxStyle, "osy, které se mezi dlaždicemi smí lišit (čárkami, prázdné = žádné)")
	k := fs.Int("k", 6, "nejvýš tolik dlaždic")
	top := fs.Int("top", 3, "kolik návrhů na počet dlaždic")
	asJSON := fs.Bool("json", false, "JSON")
	if extra := parseArgs(fs, args); len(extra) > 0 {
		return fmt.Errorf("nečekaný argument %q", extra[0])
	}
	pool, err := pf.pool(labDir)
	if err != nil {
		return err
	}
	var looseAxes []string
	for _, a := range strings.Split(*loose, ",") {
		if a = strings.TrimSpace(a); a != "" {
			looseAxes = append(looseAxes, a)
		}
	}
	sg, err := pool.Suggest(*tiles, looseAxes, *k, *top)
	if err != nil {
		return err
	}
	if *asJSON {
		return printJSON(sg)
	}
	if sg.Note != "" {
		fmt.Println("⚠", sg.Note)
	}
	fmt.Printf("hodnoty osy %s:", video.AxisName(*tiles))
	for _, v := range sg.Values {
		fmt.Printf("  %s (%d)", v.Label, v.N)
	}
	fmt.Println()
	var looseNames []string
	for _, a := range looseAxes {
		looseNames = append(looseNames, video.AxisName(a))
	}
	looseName := strings.Join(looseNames, "+")
	for _, n := range sg.Ks() {
		fmt.Printf("\n%d dlaždice — úplných snímků: striktně (vše stejné) / volně (%s se smí lišit)\n", n, looseName)
		shown := map[string]bool{}
		for _, s := range append(append([]video.Suggestion{}, sg.ByK[n]...), sg.ByLoose[n]...) {
			key := strings.Join(s.Values, ",")
			if shown[key] {
				continue
			}
			shown[key] = true
			fmt.Printf("  %6d / %-6d  %s\n", s.Strict, s.Loose, strings.Join(s.Labels, " + "))
		}
	}
	return nil
}

func truncate(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n-1]) + "…"
}

func printJSON(v any) error {
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", " ")
	return enc.Encode(v)
}

func videoNewCLI(labDir string, args []string) error {
	fs := flag.NewFlagSet("video new", flag.ExitOnError)
	pf := addPoolFlags(fs)
	tmpl := fs.String("template", "platno", "stroboskop | prulet | platno | mix")
	name := fs.String("name", "", "jméno videa (výchozí podle šablony)")
	if extra := parseArgs(fs, args); len(extra) > 0 {
		return fmt.Errorf("nečekaný argument %q", extra[0])
	}
	id, err := video.TemplateID(*tmpl)
	if err != nil {
		return err
	}
	pool, err := pf.pool(labDir)
	if err != nil {
		return err
	}
	src := video.Source{PromptIdentity: *pf.identity}
	if *pf.prefer != "first" {
		src.Prefer = *pf.prefer
	}
	if *pf.family != "" {
		src.Family = *pf.family
	} else {
		for _, r := range strings.Split(*pf.runs, ",") {
			src.Runs = append(src.Runs, strings.TrimSpace(r))
		}
	}
	n := *name
	if n == "" {
		n = id
	}
	r, notes := video.FromTemplate(id, n, src, pool)
	// --where narrows the pool; keep it in the recipe.
	if sel, err := video.ParseWhere(pf.where); err == nil {
		for axis, vals := range sel.Only {
			if r.Select == nil {
				r.Select = video.SelectSpec{}
			}
			r.Select[axis] = video.AxisFilter{Only: vals}
		}
	}
	text, err := video.TemplateYAML(r, pool, notes)
	if err != nil {
		return err
	}
	fmt.Print(text)
	return nil
}

func videoPlanCLI(labDir string, args []string) error {
	fs := flag.NewFlagSet("video plan", flag.ExitOnError)
	slides := fs.Bool("slides", false, "vypsat i snímky")
	asJSON := fs.Bool("json", false, "JSON")
	pos := parseArgs(fs, args)
	if len(pos) != 1 {
		return fmt.Errorf("lab video plan recept.yaml")
	}
	data, err := os.ReadFile(pos[0])
	if err != nil {
		return err
	}
	recipes, err := video.ParseRecipes(data)
	if err != nil {
		return err
	}
	col, err := video.Load(labDir)
	if err != nil {
		return err
	}
	for _, r := range recipes {
		sb, err := video.Plan(col, r)
		if err != nil {
			return fmt.Errorf("%s:\n  %w", r.Name, err)
		}
		if *asJSON {
			if !*slides {
				sb.Slides = nil
			}
			if err := printJSON(sb); err != nil {
				return err
			}
			continue
		}
		printStoryboard(sb, *slides)
	}
	return nil
}

func printStoryboard(sb *video.Storyboard, withSlides bool) {
	r := sb.Recipe
	l := sb.Layout
	frame := "jeden obrázek"
	if r.Frame.Tiles != "" && l != nil {
		frame = fmt.Sprintf("%d dlaždic %s (%d×%d, obrázek %d px)", len(sb.Tiles), video.AxisName(r.Frame.Tiles),
			l.Cols, l.Rows, l.TileW)
	}
	fmt.Printf("\n%s · %d snímků · %s · %g/s · %s celkem\n", r.Name, sb.Stats.Slides, frame, r.Time.Rate,
		clock(sb.Stats.Seconds))
	var axes []string
	for _, a := range r.Time.Axes {
		n := video.AxisName(a)
		if hasString(r.Time.Loose, a) {
			n += " (volně)"
		}
		axes = append(axes, n)
	}
	fmt.Printf("  čas: %s", strings.Join(axes, " → "))
	if len(r.Output.Per) > 0 {
		var per []string
		for _, a := range r.Output.Per {
			per = append(per, video.AxisName(a))
		}
		fmt.Printf(" · video na %s", strings.Join(per, ", "))
	}
	fmt.Println()
	d := sb.Stats.Dropped
	fmt.Printf("  obrázků ve výběru %d · vyřazeno: neúplné snímky %d, prázdné soubory %d, kolize %d, filtr %d\n",
		sb.Stats.Pictures, d["incomplete"], d["empty_file"], d["collision"], d["filtered"])
	if m := sb.Stats.Match; len(m) > 0 {
		total := m["exact"] + m["kind"] + m["order"]
		fmt.Printf("  shoda volné osy: přesná %d %%, stejný druh %d %%, jiná %d %%\n",
			pct(m["exact"], total), pct(m["kind"], total), pct(m["order"], total))
	}
	fmt.Printf("  videa (%d):\n", len(sb.Videos))
	for _, v := range sb.Videos {
		groups := ""
		if len(v.Groups) > 0 {
			groups = fmt.Sprintf("  %d× %s", len(v.Groups), video.AxisName(r.Output.Split.At))
		}
		fmt.Printf("    %-36s %7s  %5d snímků%s\n", v.Name+".mp4", clock(v.Seconds), v.To-v.From, groups)
	}
	for _, w := range sb.Warnings {
		fmt.Println("  ⚠", w)
	}
	if withSlides {
		for i, s := range sb.Slides {
			var tiles []string
			for _, t := range s.Tiles {
				if t == nil {
					tiles = append(tiles, "—")
				} else {
					tiles = append(tiles, t.Model+"/"+t.Style)
				}
			}
			fmt.Printf("    %5d  %-6s %-30s %s\n", i, s.Match, truncate(s.Title, 30), strings.Join(tiles, "  "))
		}
	}
}

func pct(a, total int) int {
	if total == 0 {
		return 0
	}
	return int(float64(a)*100/float64(total) + 0.5)
}

func clock(sec float64) string {
	s := int(sec + 0.5)
	if s < 60 {
		return fmt.Sprintf("%d s", s)
	}
	return fmt.Sprintf("%d:%02d", s/60, s%60)
}

func hasString(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

func videoRenderCLI(labDir string, args []string) error {
	fs := flag.NewFlagSet("video render", flag.ExitOnError)
	only := fs.String("only", "", "jen tyto díly (jména čárkami)")
	out := fs.String("out", "", "výstupní adresář (výchozí build/lab/_video/<jméno receptu>)")
	draft := fs.Bool("draft", false, "kreslit z náhledů 320 px (rychlý koncept)")
	pos := parseArgs(fs, args)
	if len(pos) != 1 {
		return fmt.Errorf("lab video render recept.yaml")
	}
	data, err := os.ReadFile(pos[0])
	if err != nil {
		return err
	}
	recipes, err := video.ParseRecipes(data)
	if err != nil {
		return err
	}
	col, err := video.Load(labDir)
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	defer stop()
	var onlyList []string
	for _, n := range strings.Split(*only, ",") {
		if n = strings.TrimSpace(n); n != "" {
			onlyList = append(onlyList, n)
		}
	}
	rendered := 0
	for _, r := range recipes {
		sb, err := video.Plan(col, r)
		if err != nil {
			return fmt.Errorf("%s:\n  %w", r.Name, err)
		}
		// --only names parts; a recipe without any of them is skipped.
		if len(onlyList) > 0 {
			has := false
			for _, v := range sb.Videos {
				for _, n := range onlyList {
					has = has || v.Name == n
				}
			}
			if !has {
				continue
			}
		}
		rendered++
		if *out != "" && rendered > 1 {
			return fmt.Errorf("--out jde jen s jedním receptem (vyber ho přes --only)")
		}
		printStoryboard(sb, false)
		dir := *out
		if dir == "" {
			dir = filepath.Join(labDir, "_video", sb.Recipe.Name)
		}
		last := time.Time{}
		done, err := video.Render(ctx, sb, video.RenderOptions{
			LabDir: labDir, OutDir: dir, Only: onlyList, Thumbs: *draft,
			Progress: func(p video.Progress) {
				if p.Frames == 0 || time.Since(last) < 2*time.Second && p.Frame < p.Frames {
					return
				}
				last = time.Now()
				fmt.Printf("\r  %d/%d %-32s %3d %%  (%.0f s)   ", p.Part, p.Parts, p.Name, 100*p.Frame/p.Frames, p.ElapsedSecs)
			},
		})
		fmt.Println()
		for _, d := range done {
			fmt.Printf("  ✓ %s  %s  %.1f MB\n", d.File, clock(d.Seconds), float64(d.Bytes)/1e6)
		}
		if err != nil {
			return err
		}
	}
	if rendered == 0 {
		return fmt.Errorf("žádný recept nemá díl %s", strings.Join(onlyList, ", "))
	}
	return nil
}
