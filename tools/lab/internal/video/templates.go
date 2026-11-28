package video

import (
	"fmt"
	"strings"
)

// Templates are the four starting points of the studio (plan §3).
var Templates = []struct {
	ID, Name, What string
}{
	{"stroboskop", "Stroboskop", "jeden obrázek, styl za stylem rychle a střihem — co všechno model se stylem udělá"},
	{"prulet", "Průlet", "jeden obrázek, prompt → styly, minutová videa po promptech"},
	{"platno", "Plátno", "mřížka modelů: týž prompt i styl vedle sebe"},
	{"mix", "Mix", "mřížka modelů: týž prompt, každý model ve svém stylu (běhy s jinými styly)"},
}

// TemplateID normalises a template name ("Plátno" → "platno").
func TemplateID(name string) (string, error) {
	id := slug(name)
	for _, t := range Templates {
		if t.ID == id {
			return id, nil
		}
	}
	var ids []string
	for _, t := range Templates {
		ids = append(ids, t.ID)
	}
	return "", fmt.Errorf("neznámá šablona %q (šablony: %s)", name, strings.Join(ids, ", "))
}

// FromTemplate builds a recipe for the pool from a template: the axes with
// several values get the roles the template gives them, flows other than the
// first are left out (with a note), so the result plans as it is.
func FromTemplate(id, name string, src Source, p *Pool) (Recipe, []string) {
	r := Recipe{Version: 1, Name: name, Source: src, Select: SelectSpec{}}
	var notes []string
	values := func(a string) []string { return p.Values(a) }
	if flows := values(AxFlow); len(flows) > 1 {
		r.Select[AxFlow] = AxisFilter{Only: []string{flows[0]}}
		notes = append(notes, fmt.Sprintf("běhy mají flow %s; recept bere %s (select.flow), další flow = další recept nebo output.per: [flow]",
			strings.Join(flows, ", "), flows[0]))
	}
	multi := func(a string) bool { return len(values(a)) > 1 }
	var timeAxes []string
	for _, a := range []string{AxPrompt, AxCharacter, AxPrefix} {
		if multi(a) {
			timeAxes = append(timeAxes, a)
		}
	}
	f := func(v float64) *float64 { return &v }
	t := true
	switch id {
	case "stroboskop", "prulet":
		timeAxes = append(timeAxes, AxStyle)
		if multi(AxModel) {
			r.Output.Per = append(r.Output.Per, AxModel)
		}
		if id == "stroboskop" {
			r.Time.Rate, r.Time.Fade = 12, f(0)
		} else {
			r.Time.Rate, r.Time.Fade = 4, f(0.2)
		}
	case "platno", "mix":
		r.Frame.Tiles = AxModel
		r.Frame.Title = "auto"
		timeAxes = append(timeAxes, AxStyle)
		r.Time.Complete = &t
		r.Time.Rate, r.Time.Fade = 2, f(0.2)
		if id == "mix" {
			r.Time.Loose = []string{AxStyle}
			r.Time.Pair = "kind"
			r.Frame.Title = AxPrompt
			r.Frame.Captions = Captions{Mode: "list", Axes: []string{AxModel, AxStyle}}
		}
	}
	if multi(AxVariant) {
		r.Output.Per = append(r.Output.Per, AxVariant)
	}
	r.Time.Axes = timeAxes
	if (id == "prulet" || id == "mix" || id == "platno") && multi(AxPrompt) {
		r.Output.Split = &Split{Seconds: 60, At: AxPrompt}
	}
	if len(r.Select) == 0 {
		r.Select = nil
	}
	return r, notes
}

// TemplateYAML writes a recipe with a commented header: what the runs hold
// and the keys worth knowing.
func TemplateYAML(r Recipe, p *Pool, notes []string) (string, error) {
	data, err := MarshalRecipe(r)
	if err != nil {
		return "", err
	}
	var b strings.Builder
	b.WriteString("# Recept videa — návod: tools/lab/README.md („Video napříč běhy“),\n")
	b.WriteString("# plán: docs/plan-video-studio.md §5. Spusť: lab video plan <soubor>, lab video render <soubor>\n#\n")
	for _, a := range []string{AxModel, AxStyle, AxPrompt, AxCharacter, AxFlow, AxVariant} {
		vals := p.Values(a)
		if len(vals) <= 1 && a != AxModel {
			continue
		}
		fmt.Fprintf(&b, "# %-14s %3d  %s\n", AxisName(a)+":", len(vals), preview(p, a, vals))
	}
	for _, n := range notes {
		fmt.Fprintf(&b, "# pozn.: %s\n", n)
	}
	b.WriteString("#\n# Klíče navíc: select.<osa>: [hodnoty] | {not: […]} | {kind: [artist]};\n")
	b.WriteString("# frame.cols: auto | N; frame.captions: none | auto | [osy]; time.order: {style: picker | year | label};\n")
	b.WriteString("# output: {per: [osa], split: {seconds: 60}, max_seconds: 170, crf: 23, audio: hudba.mp3}\n\n")
	b.Write(data)
	return b.String(), nil
}
