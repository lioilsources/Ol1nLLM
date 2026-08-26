package main

import (
	"bytes"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"image"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// Upload of a finished run to the FINETUNE gallery (finetune.ol1n.com), the
// same NAS backend the app exports its sessions to. The gallery is where
// outputs get rated and turned into LoRA datasets, and a lab matrix is exactly
// the kind of thing worth rating — a hundred variants of one idea, each with
// its parameters attached.
//
// Protocol mirrors lib/services/finetune_export_service.dart, because it is
// the same server: two-phase, content-addressed, idempotent.
//
//	1. POST /api/ingest/manifest            → {"needed": [sha…]}
//	2. PUT  /api/ingest/images/{sha256}     → raw PNG, only for what is needed
//	3. POST /api/ingest/sessions/{id}/finalize → {"images": N, "newBlobs": M}
//
// Re-exporting a run that has grown sends only the new images, and an upload
// that dies halfway resumes for free — the server already has what it got.

const defaultFinetuneURL = "https://finetune.ol1n.com"

type Finetune struct {
	Base   string
	id     string
	secret string
	http   *http.Client
}

func NewFinetune(base, id, secret string) *Finetune {
	if base == "" {
		base = defaultFinetuneURL
	}
	return &Finetune{
		Base: strings.TrimRight(base, "/"), id: id, secret: secret,
		http: &http.Client{Timeout: 2 * time.Minute},
	}
}

func (f *Finetune) HasCreds() bool { return f.id != "" && f.secret != "" }

func (f *Finetune) do(req *http.Request) (*http.Response, error) {
	if !f.HasCreds() {
		return nil, fmt.Errorf("chybí CF_ACCESS_CLIENT_ID / CF_ACCESS_CLIENT_SECRET (viz .env.local)")
	}
	req.Header.Set("CF-Access-Client-Id", f.id)
	req.Header.Set("CF-Access-Client-Secret", f.secret)
	return f.http.Do(req)
}

// SendManifest posts the session description and returns the blobs the server
// does not have yet.
func (f *Finetune) SendManifest(body []byte) ([]string, error) {
	req, err := http.NewRequest("POST", f.Base+"/api/ingest/manifest", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := f.do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return nil, &HTTPError{Status: resp.StatusCode, Body: snippet(raw),
			Path: "/api/ingest/manifest"}
	}
	var out struct {
		Needed []string `json:"needed"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, fmt.Errorf("/api/ingest/manifest: nečekaná odpověď: %s", snippet(raw))
	}
	return out.Needed, nil
}

// PutBlob uploads one PNG, retrying transient network failures the way the
// app does. A non-2xx is the server refusing the blob, not the network
// flaking, so it fails immediately instead of burning two more attempts.
func (f *Finetune) PutBlob(sha string, data []byte) error {
	const attempts = 3
	var last error
	for i := 1; i <= attempts; i++ {
		req, err := http.NewRequest("PUT", f.Base+"/api/ingest/images/"+sha,
			bytes.NewReader(data))
		if err != nil {
			return err
		}
		req.Header.Set("Content-Type", "image/png")
		resp, err := f.do(req)
		if err != nil {
			last = err
			time.Sleep(time.Duration(i) * time.Second)
			continue
		}
		raw, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode == 200 || resp.StatusCode == 201 {
			return nil
		}
		return &HTTPError{Status: resp.StatusCode, Body: snippet(raw),
			Path: "/api/ingest/images"}
	}
	return fmt.Errorf("nahrání blobu %s… selhalo po %d pokusech: %v",
		sha[:8], attempts, last)
}

type ExportSummary struct {
	Images   int `json:"images"`
	NewBlobs int `json:"newBlobs"`
}

func (f *Finetune) Finalize(sessionID string) (ExportSummary, error) {
	var out ExportSummary
	req, err := http.NewRequest("POST",
		f.Base+"/api/ingest/sessions/"+sessionID+"/finalize",
		strings.NewReader("{}"))
	if err != nil {
		return out, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := f.do(req)
	if err != nil {
		return out, err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return out, &HTTPError{Status: resp.StatusCode, Body: snippet(raw),
			Path: "/api/ingest/finalize"}
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return out, fmt.Errorf("finalize: nečekaná odpověď: %s", snippet(raw))
	}
	return out, nil
}

// KnownModels is the gallery's own model registry. It is maintained there, not
// here, and it lags: a model the app has just learned is unknown to the
// gallery until someone adds it. Images still land, but with nothing to filter
// or label them by — so an export says so instead of letting it pass quietly.
func (f *Finetune) KnownModels() (map[string]bool, error) {
	req, err := http.NewRequest("GET", f.Base+"/api/meta", nil)
	if err != nil {
		return nil, err
	}
	resp, err := f.do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return nil, &HTTPError{Status: resp.StatusCode, Body: snippet(raw), Path: "/api/meta"}
	}
	var out struct {
		Models []struct {
			ID string `json:"id"`
		} `json:"models"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, fmt.Errorf("/api/meta: nečekaná odpověď: %s", snippet(raw))
	}
	known := make(map[string]bool, len(out.Models))
	for _, m := range out.Models {
		known[m.ID] = true
	}
	return known, nil
}

// unknownModels lists the run's models the gallery has never heard of.
func unknownModels(plan *ExportPlan, known map[string]bool) []string {
	var out []string
	for _, m := range plan.Models {
		if !known[m] {
			out = append(out, m)
		}
	}
	sort.Strings(out)
	return out
}

// ── run → session ──────────────────────────────────────────

// labNamespace is a fixed UUID; ids are derived from it and the run/cell name
// (RFC 4122 v5), so a re-export addresses the same session and the same nodes
// instead of piling up duplicates in the gallery.
var labNamespace = [16]byte{
	0x6c, 0x61, 0x62, 0x2d, 0x6f, 0x6c, 0x31, 0x6e,
	0x2d, 0x66, 0x69, 0x6e, 0x65, 0x74, 0x75, 0x6e,
}

func uuid5(name string) string {
	h := sha1.New() //nolint:gosec // identifier, not a security boundary
	h.Write(labNamespace[:])
	h.Write([]byte(name))
	var b [16]byte
	copy(b[:], h.Sum(nil))
	b[6] = (b[6] & 0x0f) | 0x50 // version 5
	b[8] = (b[8] & 0x3f) | 0x80 // RFC 4122 variant
	s := hex.EncodeToString(b[:])
	return s[0:8] + "-" + s[8:12] + "-" + s[12:16] + "-" + s[16:20] + "-" + s[20:32]
}

// ExportPlan is what would be sent — built without touching the network so the
// UI can say "144 obrázků" before anything leaves the machine.
type ExportPlan struct {
	SessionID string
	Body      []byte
	Paths     map[string]string // sha256 → local file
	Images    int
	// Cells counts only the matrix cells, without the reference root — it is
	// what the run's own done-counter can be compared against, so the UI can
	// tell "already sent" from "sent, and then the run grew".
	Cells   int
	Skipped int
	Models  []string
}

// BuildExport turns the run into the gallery's session+nodes shape.
//
// One cell = one node: it has a prompt, a model, a seed and one image, which is
// exactly what a node is. Cells that were generated from a reference hang off
// a root node carrying that reference (origin "upload"), so the gallery shows
// what the matrix started from; txt2img cells are roots of their own.
func (r *Run) BuildExport() (*ExportPlan, error) {
	man := r.Manifest()
	if man == nil {
		return nil, fmt.Errorf("běh nemá manifest — nejdřív dump")
	}
	st := r.State()
	if st.Dry {
		return nil, fmt.Errorf("běh nanečisto obsahuje jen šrafované placeholdery, ne výsledky")
	}

	runID := st.ID
	sessionID := uuid5("session:" + runID)
	plan := &ExportPlan{SessionID: sessionID, Paths: map[string]string{}}

	nodes := make([]map[string]any, 0, len(man.Cells)+1)
	modelCount := map[string]int{}
	preset := map[string]map[string]any{}
	for _, m := range man.Models {
		preset[m.ID] = m.Preset
	}

	// The reference, if this run had one: a root node the cells point back to.
	refNodeID, refImageID := "", ""
	if r.Spec != nil && r.Spec.RefFile != "" {
		if data, err := os.ReadFile(r.Spec.RefFile); err == nil {
			sha := sha256hex(data)
			refNodeID = uuid5("ref:" + runID)
			refImageID = uuid5("refimg:" + runID)
			plan.Paths[sha] = r.Spec.RefFile
			w, h := imageSize(data)
			nodes = append(nodes, map[string]any{
				"id":     refNodeID,
				"prompt": "",
				"origin": "upload",
				"width":  w, "height": h,
				"createdAt": fileTime(r.Spec.RefFile),
				"images": []map[string]any{{
					"id": refImageID, "sha256": sha, "size": len(data), "idx": 0,
				}},
			})
			plan.Images++
		}
	}

	for _, c := range man.Cells {
		cs, ok := st.Cells[c.ID]
		if !ok || cs.Status != CellDone || cs.Placeholder {
			plan.Skipped++
			continue
		}
		path := r.imgPath(c.ID)
		data, err := os.ReadFile(path)
		if err != nil {
			plan.Skipped++
			continue
		}
		sha := sha256hex(data)
		plan.Paths[sha] = path
		w, h := imageSize(data)
		node := map[string]any{
			"id":        uuid5("cell:" + runID + "/" + c.ID),
			"prompt":    strOr(c.Prompt),
			"modelId":   c.Model,
			"createdAt": fileTime(path),
			"images": []map[string]any{{
				"id":     uuid5("img:" + runID + "/" + c.ID),
				"sha256": sha, "size": len(data), "idx": 0,
			}},
		}
		if w > 0 {
			node["width"], node["height"] = w, h
		}
		if c.Negative != nil && *c.Negative != "" {
			node["negativePrompt"] = *c.Negative
		}
		// __baseline is the lab's own marker for "no style block", not a
		// style the app knows — sending it would invent a preset id.
		if c.Style != "" && c.Style != "__baseline" {
			node["styleId"] = c.Style
		}
		if v, ok := c.Params["lora"].(string); ok && v != "" {
			node["loraName"] = v
			if s, ok := c.Params["loraStrength"].(float64); ok {
				node["loraStrength"] = s
			}
		}
		if r.Spec != nil && r.Spec.PoseMode == "template" && r.Spec.PoseID != "" {
			node["poseId"] = r.Spec.PoseID
		}
		if v, ok := c.Params["seed"].(float64); ok {
			node["seed"] = int(v)
		}
		if c.Flow == "repose" {
			node["isRepose"] = true
		}
		if c.Flow != "txt2img" && refNodeID != "" {
			node["parentId"] = refNodeID
			node["sourceImageId"] = refImageID
		}
		// Sampler settings are read back out of the graph that was sent, not
		// from the model preset: a sweep or an override changes them, and the
		// point of exporting is that the numbers match the picture.
		addSamplerFields(node, r.cellGraph(c.ID))
		// The score tags the app prepends are part of what produced the
		// picture, so the gallery gets them too.
		if p, ok := preset[c.Model]["positivePrefix"].(string); ok && p != "" {
			node["positivePrefix"] = p
		}
		nodes = append(nodes, node)
		modelCount[c.Model]++
		plan.Images++
		plan.Cells++
	}

	if plan.Images == 0 {
		return nil, fmt.Errorf("běh nemá žádný hotový obrázek k odeslání")
	}

	for m := range modelCount {
		plan.Models = append(plan.Models, m)
	}
	sort.Strings(plan.Models)

	title := st.Title
	if len(modelCount) > 1 {
		title = fmt.Sprintf("%s [lab %s · %d modelů]", title, runID, len(modelCount))
	} else {
		title = fmt.Sprintf("%s [lab %s]", title, runID)
	}
	body, err := json.Marshal(map[string]any{
		"session": map[string]any{
			"id":        sessionID,
			"title":     title,
			"modelId":   dominant(modelCount),
			"updatedAt": time.Now().UTC().Format(time.RFC3339),
		},
		"nodes": nodes,
	})
	if err != nil {
		return nil, err
	}
	plan.Body = body
	return plan, nil
}

// addSamplerFields copies the settings the sampler actually ran with. Models
// on their own template (flux-manga) have no KSampler; those fields then stay
// absent rather than being guessed from a preset that does not apply.
func addSamplerFields(node map[string]any, wf map[string]any) {
	for _, raw := range wf {
		n, _ := raw.(map[string]any)
		if n["class_type"] != "KSampler" {
			continue
		}
		in, _ := n["inputs"].(map[string]any)
		for src, dst := range map[string]string{
			"steps": "steps", "cfg": "cfg", "denoise": "denoise",
			"sampler_name": "samplerName", "scheduler": "scheduler",
		} {
			if v, ok := in[src]; ok {
				node[dst] = v
			}
		}
		return
	}
}

func (r *Run) cellGraph(id string) map[string]any {
	raw, err := os.ReadFile(filepath.Join(r.Dir, "wf", id+".json"))
	if err != nil {
		return nil
	}
	var wf map[string]any
	if json.Unmarshal(raw, &wf) != nil {
		return nil
	}
	return wf
}

// ExportToFinetune runs the three phases, reporting blob progress.
func (r *Run) ExportToFinetune(ft *Finetune, progress func(done, total int)) (ExportSummary, error) {
	plan, err := r.BuildExport()
	if err != nil {
		return ExportSummary{}, err
	}
	needed, err := ft.SendManifest(plan.Body)
	if err != nil {
		return ExportSummary{}, err
	}
	// Deterministic order so a resumed export repeats the same sequence and
	// the progress number means the same thing twice.
	sort.Strings(needed)
	if progress != nil {
		progress(0, len(needed))
	}
	for i, sha := range needed {
		path, ok := plan.Paths[sha]
		if !ok {
			continue // server asked for a hash we never offered
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return ExportSummary{}, fmt.Errorf("%s: %w", filepath.Base(path), err)
		}
		if err := ft.PutBlob(sha, data); err != nil {
			return ExportSummary{}, err
		}
		if progress != nil {
			progress(i+1, len(needed))
		}
	}
	sum, err := ft.Finalize(plan.SessionID)
	if err != nil {
		return ExportSummary{}, err
	}
	if sum.Images == 0 {
		sum.Images = plan.Images
	}
	return sum, nil
}

func sha256hex(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

func imageSize(data []byte) (int, int) {
	cfg, _, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		return 0, 0
	}
	return cfg.Width, cfg.Height
}

func fileTime(path string) string {
	st, err := os.Stat(path)
	if err != nil {
		return time.Now().UTC().Format(time.RFC3339)
	}
	return st.ModTime().UTC().Format(time.RFC3339)
}

func strOr(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// dominant is the model that produced most of the run's images. A matrix has
// no single model, but the gallery's session header wants one — and the
// per-image modelId, which is what a dataset is actually built from, stays
// exact either way.
func dominant(counts map[string]int) string {
	best, bestN := "", -1
	keys := make([]string, 0, len(counts))
	for k := range counts {
		keys = append(keys, k)
	}
	sort.Strings(keys) // ties resolve the same way on every export
	for _, k := range keys {
		if counts[k] > bestN {
			best, bestN = k, counts[k]
		}
	}
	return best
}
