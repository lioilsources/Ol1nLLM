package video

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"strconv"
	"strings"

	"gopkg.in/yaml.v3"
)

// Recipe is one video (or one set of videos) in YAML: what to take, which
// role each axis plays, the pace and the output. docs/plan-video-studio.md §5.
type Recipe struct {
	Version int        `yaml:"version" json:"version"`
	Name    string     `yaml:"name" json:"name"`
	Source  Source     `yaml:"source" json:"source"`
	Select  SelectSpec `yaml:"select,omitempty" json:"select,omitempty"`
	Frame   Frame      `yaml:"frame,omitempty" json:"frame"`
	Time    Time       `yaml:"time,omitempty" json:"time"`
	Output  Output     `yaml:"output,omitempty" json:"output"`
}

type Source struct {
	Runs []string `yaml:"runs,omitempty" json:"runs,omitempty"`
	// Family: every run of this run's family (same prompts).
	Family         string `yaml:"family,omitempty" json:"family,omitempty"`
	PromptIdentity string `yaml:"prompt_identity,omitempty" json:"promptIdentity,omitempty"`
	Prefer         string `yaml:"prefer,omitempty" json:"prefer,omitempty"`
}

// SelectSpec filters per axis. A value is a single value, a list (allowed
// values, in this order), or {only: […], not: […], kind: […]} (kind: styles).
type SelectSpec map[string]AxisFilter

type AxisFilter struct {
	Only []string `yaml:"only,omitempty" json:"only,omitempty"`
	Not  []string `yaml:"not,omitempty" json:"not,omitempty"`
	Kind []string `yaml:"kind,omitempty" json:"kind,omitempty"`
}

func (f *AxisFilter) UnmarshalYAML(n *yaml.Node) error {
	switch n.Kind {
	case yaml.ScalarNode:
		f.Only = []string{n.Value}
		return nil
	case yaml.SequenceNode:
		return n.Decode(&f.Only)
	case yaml.MappingNode:
		type plain AxisFilter
		var p plain
		dec := yaml.NewDecoder(bytes.NewReader(mustMarshal(n)))
		dec.KnownFields(true)
		if err := dec.Decode(&p); err != nil {
			return fmt.Errorf("řádek %d: %w (čekám only, not nebo kind)", n.Line, err)
		}
		*f = AxisFilter(p)
		return nil
	}
	return fmt.Errorf("řádek %d: filtr osy je hodnota, seznam nebo {only, not, kind}", n.Line)
}

// MinReaction is the select key that keeps pictures where the style did
// something: select: {min_reaction: 0.15}.
const MinReaction = "min_reaction"

// MinValue reads select.min_reaction (a scalar lands in Only).
func (f AxisFilter) MinValue() (float64, error) {
	if len(f.Only) != 1 {
		return 0, fmt.Errorf("čekám jedno číslo")
	}
	return strconv.ParseFloat(f.Only[0], 64)
}

func mustMarshal(n *yaml.Node) []byte {
	b, _ := yaml.Marshal(n)
	return b
}

type Frame struct {
	// Tiles is the axis whose values share one frame; empty = one picture.
	Tiles string `yaml:"tiles,omitempty" json:"tiles,omitempty"`
	// Cols: "auto" or a number.
	Cols     IntOrAuto `yaml:"cols,omitempty" json:"cols"`
	Fit      string    `yaml:"fit,omitempty" json:"fit,omitempty"`
	Title    string    `yaml:"title,omitempty" json:"title,omitempty"`
	Captions Captions  `yaml:"captions,omitempty" json:"captions"`
	// Reference puts the picture the tiles were drawn from (the run's
	// reference, a restyle's position photo) in a first tile.
	Reference bool `yaml:"reference,omitempty" json:"reference,omitempty"`
}

// IntOrAuto is 0 for auto.
type IntOrAuto int

func (v *IntOrAuto) UnmarshalYAML(n *yaml.Node) error {
	if n.Value == "auto" || n.Value == "" {
		*v = 0
		return nil
	}
	i, err := strconv.Atoi(n.Value)
	if err != nil || i < 1 {
		return fmt.Errorf("řádek %d: cols je auto nebo kladné číslo, ne %q", n.Line, n.Value)
	}
	*v = IntOrAuto(i)
	return nil
}

func (v IntOrAuto) MarshalYAML() (any, error) {
	if v == 0 {
		return "auto", nil
	}
	return int(v), nil
}

// Captions: "none", "auto" or a list of axes.
type Captions struct {
	Mode string   `json:"mode"` // none | auto | list
	Axes []string `json:"axes,omitempty"`
}

func (c *Captions) UnmarshalYAML(n *yaml.Node) error {
	switch n.Kind {
	case yaml.ScalarNode:
		switch n.Value {
		case "none", "auto":
			c.Mode = n.Value
			return nil
		}
		c.Mode, c.Axes = "list", []string{n.Value}
		return nil
	case yaml.SequenceNode:
		c.Mode = "list"
		return n.Decode(&c.Axes)
	}
	return fmt.Errorf("řádek %d: captions je none, auto nebo seznam os", n.Line)
}

func (c Captions) MarshalYAML() (any, error) {
	if c.Mode == "list" {
		return c.Axes, nil
	}
	return c.Mode, nil
}

func (c Captions) IsZero() bool { return c.Mode == "" }

type Time struct {
	Axes  []string `yaml:"axes,omitempty" json:"axes"`
	Loose []string `yaml:"loose,omitempty" json:"loose,omitempty"`
	// Pair: how loose values meet on one frame — exact (only the values every
	// tile has), kind (same style kind, nearest year), order (picker order).
	Pair     string            `yaml:"pair,omitempty" json:"pair,omitempty"`
	Complete *bool             `yaml:"complete,omitempty" json:"complete"`
	Order    map[string]string `yaml:"order,omitempty" json:"order,omitempty"`
	Rate     float64           `yaml:"rate,omitempty" json:"rate"`
	Fade     *float64          `yaml:"fade,omitempty" json:"fade"`
}

type Output struct {
	Size       string   `yaml:"size,omitempty" json:"size"`
	FPS        int      `yaml:"fps,omitempty" json:"fps"`
	Per        []string `yaml:"per,omitempty" json:"per,omitempty"`
	Split      *Split   `yaml:"split,omitempty" json:"split,omitempty"`
	MaxSeconds float64  `yaml:"max_seconds,omitempty" json:"maxSeconds,omitempty"`
	CRF        int      `yaml:"crf,omitempty" json:"crf"`
	Audio      string   `yaml:"audio,omitempty" json:"audio,omitempty"`
	Encoder    string   `yaml:"encoder,omitempty" json:"encoder,omitempty"`
}

type Split struct {
	Seconds float64 `yaml:"seconds" json:"seconds"`
	At      string  `yaml:"at,omitempty" json:"at,omitempty"`
}

// ParseRecipes reads one or more YAML documents (separated by ---). Unknown
// keys are errors with their line, so a typo never silently does nothing.
func ParseRecipes(data []byte) ([]Recipe, error) {
	dec := yaml.NewDecoder(bytes.NewReader(data))
	dec.KnownFields(true)
	var out []Recipe
	for i := 1; ; i++ {
		var r Recipe
		err := dec.Decode(&r)
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("recept %d: %s", i, czechYAML(err))
		}
		r.Defaults()
		if err := r.Validate(); err != nil {
			return nil, fmt.Errorf("recept %d (%s): %w", i, r.Name, err)
		}
		out = append(out, r)
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("prázdný recept")
	}
	return out, nil
}

func czechYAML(err error) string {
	s := err.Error()
	s = strings.ReplaceAll(s, "yaml: unmarshal errors:\n", "")
	s = strings.ReplaceAll(s, "not found in type", "není klíč typu")
	s = strings.ReplaceAll(s, "field ", "klíč ")
	s = strings.ReplaceAll(s, "line ", "řádek ")
	return strings.TrimSpace(s)
}

// Defaults fills what the recipe leaves out.
func (r *Recipe) Defaults() {
	if r.Version == 0 {
		r.Version = 1
	}
	if r.Name == "" {
		r.Name = "video"
	}
	if r.Source.Prefer == "" {
		r.Source.Prefer = "first"
	}
	if r.Frame.Fit == "" {
		r.Frame.Fit = "contain"
	}
	if r.Frame.Title == "" {
		r.Frame.Title = "none"
	}
	if r.Frame.Captions.Mode == "" {
		r.Frame.Captions.Mode = "none"
	}
	if r.Time.Pair == "" {
		r.Time.Pair = "order"
	}
	if r.Time.Complete == nil {
		t := true
		r.Time.Complete = &t
	}
	if r.Time.Rate == 0 {
		r.Time.Rate = 4
	}
	if r.Time.Fade == nil {
		f := 0.4
		r.Time.Fade = &f
	}
	if r.Output.Size == "" {
		r.Output.Size = "1080x1920"
	}
	if r.Output.FPS == 0 {
		r.Output.FPS = 30
	}
	if r.Output.CRF == 0 {
		r.Output.CRF = 18
	}
}

// Validate checks what can be checked without the pictures. The role rule
// (every axis with several values has exactly one role) needs the collection
// and lives in Plan.
func (r *Recipe) Validate() error {
	var errs []string
	add := func(f string, a ...any) { errs = append(errs, fmt.Sprintf(f, a...)) }
	if r.Version != 1 {
		add("version %d — umím jen 1", r.Version)
	}
	if !safeName(r.Name) {
		add("name %q: jen písmena, číslice, - a _", r.Name)
	}
	if len(r.Source.Runs) == 0 && r.Source.Family == "" {
		add("source: chybí runs nebo family")
	}
	if len(r.Source.Runs) > 0 && r.Source.Family != "" {
		add("source: buď runs, nebo family")
	}
	switch r.Source.PromptIdentity {
	case "", IdentityScene, IdentityColumn:
	default:
		add("source.prompt_identity: %q, čekám scene nebo column", r.Source.PromptIdentity)
	}
	switch r.Source.Prefer {
	case "first", "newest", "error":
	default:
		add("source.prefer: %q, čekám first, newest nebo error", r.Source.Prefer)
	}
	for axis, f := range r.Select {
		if axis == MinReaction {
			if v, err := f.MinValue(); err != nil || v < 0 || v > 1 {
				add("select.min_reaction: číslo 0–1 (vzdálenost barev od obrázku bez stylu)")
			}
			continue
		}
		if !IsAxis(axis) {
			add("select.%s: neznámá osa (osy: %s)", axis, strings.Join(AllAxes, ", "))
		}
		if len(f.Kind) > 0 && axis != AxStyle {
			add("select.%s.kind: druh mají jen styly", axis)
		}
	}
	if r.Frame.Tiles != "" && !IsAxis(r.Frame.Tiles) {
		add("frame.tiles: neznámá osa %q", r.Frame.Tiles)
	}
	switch r.Frame.Fit {
	case "contain", "cover":
	default:
		add("frame.fit: %q, čekám contain nebo cover", r.Frame.Fit)
	}
	if r.Frame.Reference && r.Frame.Tiles == "" {
		add("frame.reference: předloha jako dlaždice jde jen s frame.tiles")
	}
	if r.Frame.Fit == "cover" && r.Frame.Tiles != "" {
		add("frame.fit: cover jde jen bez dlaždic (s dlaždicemi se obrázky vejdou celé)")
	}
	if r.Frame.Title != "none" && r.Frame.Title != "auto" && !IsAxis(r.Frame.Title) {
		add("frame.title: none, auto nebo osa, ne %q", r.Frame.Title)
	}
	for _, a := range r.Frame.Captions.Axes {
		if !IsAxis(a) {
			add("frame.captions: neznámá osa %q", a)
		}
	}
	seen := map[string]string{}
	role := func(axis, where string) {
		if !IsAxis(axis) {
			add("%s: neznámá osa %q", where, axis)
			return
		}
		if prev, ok := seen[axis]; ok {
			add("osa %s je v %s i v %s — každá osa má jednu roli", AxisName(axis), prev, where)
			return
		}
		seen[axis] = where
	}
	if r.Frame.Tiles != "" {
		role(r.Frame.Tiles, "frame.tiles")
	}
	for _, a := range r.Time.Axes {
		role(a, "time.axes")
	}
	for _, a := range r.Output.Per {
		role(a, "output.per")
	}
	if len(r.Time.Loose) > 0 {
		if r.Frame.Tiles == "" {
			add("time.loose dává smysl jen s frame.tiles (volné osy se liší mezi dlaždicemi)")
		}
		// Loose axes are the inner end of time.axes.
		n := len(r.Time.Axes)
		for i, a := range r.Time.Loose {
			j := n - len(r.Time.Loose) + i
			if j < 0 || r.Time.Axes[j] != a {
				add("time.loose %v musí být vnitřní konec time.axes %v", r.Time.Loose, r.Time.Axes)
				break
			}
		}
	}
	switch r.Time.Pair {
	case "exact", "kind", "order":
	default:
		add("time.pair: %q, čekám exact, kind nebo order", r.Time.Pair)
	}
	for axis, o := range r.Time.Order {
		switch {
		case axis == AxStyle && (o == "picker" || o == "year" || o == "label"):
		case axis != AxStyle && (o == "run" || o == "label"):
		default:
			add("time.order.%s: %q (styl: picker | year | label, ostatní: run | label)", axis, o)
		}
	}
	if r.Time.Rate <= 0 || r.Time.Rate > float64(r.Output.FPS) {
		add("time.rate %g: musí být v (0, %d] (nejvýš snímků videa za vteřinu)", r.Time.Rate, r.Output.FPS)
	}
	if f := *r.Time.Fade; f < 0 || f >= 1 {
		add("time.fade %g: podíl snímku, 0 až 0.99", f)
	}
	if w, h, err := ParseSize(r.Output.Size); err != nil || w < 64 || h < 64 {
		add("output.size %q: čekám ŠxV, např. 1080x1920", r.Output.Size)
	}
	if r.Output.FPS < 1 || r.Output.FPS > 120 {
		add("output.fps %d", r.Output.FPS)
	}
	if r.Output.CRF < 0 || r.Output.CRF > 51 {
		add("output.crf %d: 0–51", r.Output.CRF)
	}
	if s := r.Output.Split; s != nil {
		if s.Seconds <= 0 {
			add("output.split.seconds musí být kladné")
		}
		if s.At != "" {
			in := false
			for _, a := range r.Time.Axes {
				in = in || a == s.At
			}
			loose := false
			for _, a := range r.Time.Loose {
				loose = loose || a == s.At
			}
			if !in || loose {
				add("output.split.at: %s musí být striktní osa z time.axes", s.At)
			}
		}
	}
	if len(errs) > 0 {
		return errors.New(strings.Join(errs, "\n  "))
	}
	return nil
}

func safeName(s string) bool {
	if s == "" || len(s) > 80 {
		return false
	}
	for _, c := range s {
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '-' || c == '_' || c == '.') {
			return false
		}
	}
	return !strings.HasPrefix(s, ".")
}

// ParseSize reads "1080x1920".
func ParseSize(s string) (int, int, error) {
	a, b, ok := strings.Cut(strings.ToLower(s), "x")
	if !ok {
		return 0, 0, fmt.Errorf("size %q", s)
	}
	w, err1 := strconv.Atoi(a)
	h, err2 := strconv.Atoi(b)
	if err1 != nil || err2 != nil {
		return 0, 0, fmt.Errorf("size %q", s)
	}
	return w, h, nil
}

// MarshalRecipe writes a recipe back as YAML (the studio saves this).
func MarshalRecipe(r Recipe) ([]byte, error) {
	var buf bytes.Buffer
	enc := yaml.NewEncoder(&buf)
	enc.SetIndent(2)
	if err := enc.Encode(r); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}
