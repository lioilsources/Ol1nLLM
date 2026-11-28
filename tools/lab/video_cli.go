package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/tabwriter"

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
`)
}

type multiFlag []string

func (m *multiFlag) String() string     { return strings.Join(*m, ",") }
func (m *multiFlag) Set(v string) error { *m = append(*m, v); return nil }

func videoIndexCLI(labDir string, args []string) error {
	fs := flag.NewFlagSet("video index", flag.ExitOnError)
	minPics := fs.Int("min", 50, "jen běhy s aspoň tolika obrázky")
	refresh := fs.Bool("refresh", false, "zahodit cache indexu")
	asJSON := fs.Bool("json", false, "JSON")
	_ = fs.Parse(args)
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
	_ = fs.Parse(args)
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
	_ = fs.Parse(args)
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
