package main

import "fmt"

// Step is one link of the chain the "co je vlastně zapojené" panel shows.
type Step struct {
	NodeID string         `json:"nodeId"`
	Class  string         `json:"class"`
	Label  string         `json:"label"`
	Values map[string]any `json:"values"`
	// Injected marks a node the app splices in at request time rather than one
	// that lives in the workflow asset — the distinction the panel exists for.
	Injected bool   `json:"injected"`
	Note     string `json:"note,omitempty"`
}

// injected maps the app's synthetic node ids to Czech labels. Keep in sync with
// ComfyUIService._inject*/_spliceControlNet; test/dump_spec_test.dart guards
// that these ids still exist in the service.
var injectedLabels = map[string]string{
	"__lora__":       "LoRA (vložena appkou)",
	"__depth_src__":  "předloha pro hloubku",
	"__depth_pre__":  "DepthAnything v2 — hloubková mapa",
	"__depth_cn__":   "ControlNet (union)",
	"__depth_type__": "režim union ControlNetu: depth",
	"__pose_image__": "šablona pózy (kostra)",
	"__pose_cn__":    "ControlNet (OpenPose)",
	"__cn_apply__":   "aplikace ControlNetu na podmínění",

	// Tvář z předlohy — čte se ze stejného __depth_src__ jako hloubková mapa.
	"__face_id__":       "InstantID (model tváře)",
	"__face_cn__":       "ControlNet (InstantID, klíčové body)",
	"__face_analysis__": "rozpoznání tváře (InsightFace)",
	"__face_apply__":    "tvář z předlohy",
	"__faceid_loader__": "IPAdapter FaceID PlusV2 (loader + LoRA)",
	"__faceid_apply__":  "tvář z předlohy (FaceID)",
	"__face_pulid__":    "PuLID (model tváře, FLUX)",
	"__face_eva__":      "EVA-CLIP (kodér tváře)",
	"__detail_bbox__":   "detektor tváří (YOLOv8)",
	"__face_detail__":   "dotažení tváře (druhý průchod výřezem)",
}

var classLabels = map[string]string{
	"CheckpointLoaderSimple":  "checkpoint",
	"UNETLoader":              "UNET",
	"DualCLIPLoader":          "CLIP",
	"LoraLoader":              "LoRA",
	"CLIPTextEncode":          "text → podmínění",
	"EmptyLatentImage":        "prázdný latent",
	"EmptySD3LatentImage":     "prázdný latent",
	"VAEEncode":               "zdroj → latent",
	"RepeatLatentBatch":       "kopie latentu (batch)",
	"KSampler":                "sampler",
	"VAEDecode":               "latent → obrázek",
	"SaveImage":               "uložení",
	"ControlNetApplyAdvanced": "ControlNet",
	"LoadImage":               "vstupní obrázek",
	"ApplyInstantID":          "InstantID",
	"IPAdapterFaceID":         "IPAdapter FaceID",
	"ApplyPulidFlux":          "PuLID",
	"FaceDetailer":            "dotažení tváře",
}

// interesting values per class — everything else is wiring noise.
var shownInputs = map[string][]string{
	"CheckpointLoaderSimple":       {"ckpt_name"},
	"LoraLoader":                   {"lora_name", "strength_model"},
	"CLIPTextEncode":               {"text"},
	"EmptyLatentImage":             {"width", "height", "batch_size"},
	"EmptySD3LatentImage":          {"width", "height", "batch_size"},
	"KSampler":                     {"steps", "cfg", "sampler_name", "scheduler", "denoise", "seed"},
	"ControlNetApplyAdvanced":      {"strength", "start_percent", "end_percent"},
	"ControlNetLoader":             {"control_net_name"},
	"DepthAnythingV2Preprocessor":  {"ckpt_name", "resolution"},
	"SetUnionControlNetType":       {"type"},
	"LoadImage":                    {"image"},
	"RepeatLatentBatch":            {"amount"},
	"InstantIDModelLoader":         {"instantid_file"},
	"InstantIDFaceAnalysis":        {"provider"},
	"PulidFluxInsightFaceLoader":   {"provider"},
	"ApplyInstantID":               {"weight", "start_at", "end_at"},
	"ApplyPulidFlux":               {"weight", "start_at", "end_at"},
	"IPAdapterUnifiedLoaderFaceID": {"preset", "lora_strength", "provider"},
	"IPAdapterFaceID":              {"weight", "weight_faceidv2", "start_at", "end_at"},
	"UltralyticsDetectorProvider":  {"model_name"},
	"FaceDetailer":                 {"denoise", "steps", "cfg", "guide_size", "bbox_threshold"},
}

// Explain walks the graph backwards from SaveImage and returns the chain in
// execution order. Values come from the generated JSON, so the panel cannot
// drift from what was actually sent.
func Explain(wf map[string]any) []Step {
	node := func(id string) (map[string]any, map[string]any, string) {
		n, _ := wf[id].(map[string]any)
		if n == nil {
			return nil, nil, ""
		}
		in, _ := n["inputs"].(map[string]any)
		cls, _ := n["class_type"].(string)
		return n, in, cls
	}

	var start string
	for id, raw := range wf {
		n, _ := raw.(map[string]any)
		if cls, _ := n["class_type"].(string); cls == "SaveImage" {
			start = id
			break
		}
	}
	if start == "" {
		return []Step{}
	}

	seen := map[string]bool{}
	var order []string
	// Depth-first over every edge, deepest first, so loaders come out before
	// the sampler that consumes them.
	var walk func(id string)
	walk = func(id string) {
		if id == "" || seen[id] {
			return
		}
		seen[id] = true
		_, in, _ := node(id)
		// Stable order: sort-free but deterministic enough via the known input
		// names first, then the rest.
		for _, key := range []string{"model", "clip", "vae", "positive", "negative",
			"control_net", "image", "images", "samples", "pixels", "latent_image"} {
			if ref, ok := in[key].([]any); ok && len(ref) == 2 {
				if s, ok := ref[0].(string); ok {
					walk(s)
				}
			}
		}
		for _, v := range in {
			if ref, ok := v.([]any); ok && len(ref) == 2 {
				if s, ok := ref[0].(string); ok {
					walk(s)
				}
			}
		}
		order = append(order, id)
	}
	walk(start)

	steps := make([]Step, 0, len(order))
	for _, id := range order {
		_, in, cls := node(id)
		label, injected := injectedLabels[id]
		if !injected {
			if l, ok := classLabels[cls]; ok {
				label = l
			} else {
				label = cls
			}
		}
		vals := map[string]any{}
		for _, key := range shownInputs[cls] {
			if v, ok := in[key]; ok {
				vals[key] = v
			}
		}
		steps = append(steps, Step{
			NodeID: id, Class: cls, Label: label,
			Values: vals, Injected: injected,
			Note: explainNote(cls, id, in),
		})
	}
	return steps
}

// explainNote adds the one sentence that turns a number into a decision. Each
// claim is traceable: see copy_cs.go for where it comes from.
func explainNote(cls, id string, in map[string]any) string {
	switch {
	case id == "__cn_apply__":
		s, _ := in["strength"].(float64)
		e, _ := in["end_percent"].(float64)
		return fmt.Sprintf("síla %.2f, končí na %.0f %% kroků — %s",
			s, e*100, copyCS["cn_strength"].Text)
	case id == "__depth_pre__":
		return copyCS["depth_vs_pose"].Text
	case id == "__pose_cn__":
		return copyCS["wired_pose"].Text
	case id == "__face_apply__" || id == "__faceid_apply__":
		return copyCS["face_identity"].Text
	case id == "__face_detail__":
		return copyCS["face_detail"].Text
	case id == "__face_analysis__":
		return copyCS["face_provider"].Text
	case cls == "KSampler":
		d, ok := in["denoise"].(float64)
		if !ok {
			return ""
		}
		switch {
		case d >= 0.999:
			return "denoise 1.0 — obraz vzniká od nuly, ze zdroje drží jen ControlNet"
		case d >= 0.85:
			return copyCS["denoise_high"].Text
		default:
			return copyCS["denoise_preset"].Text
		}
	}
	return ""
}
