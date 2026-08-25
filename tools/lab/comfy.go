package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"strings"
	"time"
)

// Comfy is a minimal ComfyUI client.
//
// Auth is Cloudflare Access service-token headers. Their letter case does not
// matter: the tunnel negotiates HTTP/2, where every header name goes over the
// wire lowercase — verified against the live server, where both Header.Set and
// a direct map write return 200 while the same request without them gets 403.
type Comfy struct {
	Base   string
	id     string
	secret string
	http   *http.Client
}

func NewComfy(base, id, secret string) *Comfy {
	return &Comfy{
		Base: strings.TrimRight(base, "/"), id: id, secret: secret,
		http: &http.Client{Timeout: 10 * time.Minute},
	}
}

func (c *Comfy) HasCreds() bool { return c.id != "" && c.secret != "" }

func (c *Comfy) do(req *http.Request) (*http.Response, error) {
	if !c.HasCreds() {
		return nil, fmt.Errorf("chybí CF_ACCESS_CLIENT_ID / CF_ACCESS_CLIENT_SECRET (viz .env.local)")
	}
	req.Header.Set("CF-Access-Client-Id", c.id)
	req.Header.Set("CF-Access-Client-Secret", c.secret)
	return c.http.Do(req)
}

// getJSON decodes a GET into out. A Cloudflare block returns HTML, so a decode
// failure is reported with the status and a snippet — that is the difference
// between "auth is broken" and "ComfyUI said something unexpected".
func (c *Comfy) getJSON(path string, out any) error {
	req, err := http.NewRequest("GET", c.Base+path, nil)
	if err != nil {
		return err
	}
	resp, err := c.do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	if resp.StatusCode != 200 {
		return &HTTPError{Status: resp.StatusCode, Body: snippet(body), Path: path}
	}
	if len(body) == 0 {
		return nil
	}
	return json.Unmarshal(body, out)
}

type HTTPError struct {
	Status int
	Body   string
	Path   string
}

func (e *HTTPError) Error() string {
	return fmt.Sprintf("ComfyUI %s → HTTP %d: %s", e.Path, e.Status, e.Body)
}

// IsAuth reports a Cloudflare Access rejection, which is worth aborting a whole
// run over instead of failing hundreds of cells one at a time.
func (e *HTTPError) IsAuth() bool { return e.Status == 401 || e.Status == 403 }

func snippet(b []byte) string {
	s := strings.TrimSpace(string(b))
	if len(s) > 160 {
		s = s[:160] + "…"
	}
	return strings.Join(strings.Fields(s), " ")
}

// ObjectInfo returns the combo options of one node's input, e.g. the installed
// checkpoints (CheckpointLoaderSimple.ckpt_name) or samplers (KSampler).
func (c *Comfy) ObjectInfo(node string) (map[string]any, error) {
	var out map[string]any
	if err := c.getJSON("/object_info/"+node, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// comboOptions digs the first element out of ComfyUI's ["required"][name] pair,
// which is how it ships the list of legal values for a combo widget.
func comboOptions(info map[string]any, node, input string) []string {
	n, _ := info[node].(map[string]any)
	in, _ := n["input"].(map[string]any)
	req, _ := in["required"].(map[string]any)
	pair, _ := req[input].([]any)
	if len(pair) == 0 {
		return nil
	}
	list, _ := pair[0].([]any)
	out := make([]string, 0, len(list))
	for _, v := range list {
		if s, ok := v.(string); ok {
			out = append(out, s)
		}
	}
	return out
}

func (c *Comfy) Checkpoints() ([]string, error) {
	info, err := c.ObjectInfo("CheckpointLoaderSimple")
	if err != nil {
		return nil, err
	}
	return comboOptions(info, "CheckpointLoaderSimple", "ckpt_name"), nil
}

func (c *Comfy) Loras() ([]string, error) {
	info, err := c.ObjectInfo("LoraLoader")
	if err != nil {
		return nil, err
	}
	return comboOptions(info, "LoraLoader", "lora_name"), nil
}

func (c *Comfy) Samplers() (samplers, schedulers []string, err error) {
	info, err := c.ObjectInfo("KSampler")
	if err != nil {
		return nil, nil, err
	}
	return comboOptions(info, "KSampler", "sampler_name"),
		comboOptions(info, "KSampler", "scheduler"), nil
}

// Submit enqueues a workflow and returns its prompt_id.
func (c *Comfy) Submit(wf map[string]any, clientID string) (string, error) {
	body, err := json.Marshal(map[string]any{"prompt": wf, "client_id": clientID})
	if err != nil {
		return "", err
	}
	req, err := http.NewRequest("POST", c.Base+"/prompt", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return "", &HTTPError{Status: resp.StatusCode, Body: snippet(raw), Path: "/prompt"}
	}
	var out struct {
		PromptID   string          `json:"prompt_id"`
		NodeErrors json.RawMessage `json:"node_errors"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return "", fmt.Errorf("/prompt: nečekaná odpověď: %s", snippet(raw))
	}
	if len(out.NodeErrors) > 2 { // "{}" means none
		return "", fmt.Errorf("workflow odmítnut: %s", snippet(out.NodeErrors))
	}
	if out.PromptID == "" {
		return "", fmt.Errorf("/prompt nevrátil prompt_id")
	}
	return out.PromptID, nil
}

type HistoryEntry struct {
	Status struct {
		StatusStr string `json:"status_str"`
		Completed bool   `json:"completed"`
	} `json:"status"`
	Outputs map[string]struct {
		Images []Image `json:"images"`
	} `json:"outputs"`
}

type Image struct {
	Filename  string `json:"filename"`
	Subfolder string `json:"subfolder"`
	Type      string `json:"type"`
}

// History returns the entry for one prompt, or nil while it is still queued.
func (c *Comfy) History(promptID string) (*HistoryEntry, error) {
	var all map[string]HistoryEntry
	if err := c.getJSON("/history/"+promptID, &all); err != nil {
		return nil, err
	}
	e, ok := all[promptID]
	if !ok {
		return nil, nil
	}
	return &e, nil
}

type QueueState struct {
	Running int `json:"running"`
	Pending int `json:"pending"`
}

func (c *Comfy) Queue() (QueueState, error) {
	var raw struct {
		Running []any `json:"queue_running"`
		Pending []any `json:"queue_pending"`
	}
	if err := c.getJSON("/queue", &raw); err != nil {
		return QueueState{}, err
	}
	return QueueState{Running: len(raw.Running), Pending: len(raw.Pending)}, nil
}

// SavedImages lists the saved (non-temp) images of a finished prompt.
func (e *HistoryEntry) SavedImages() []Image {
	var out []Image
	for _, node := range e.Outputs {
		for _, im := range node.Images {
			if im.Type != "temp" {
				out = append(out, im)
			}
		}
	}
	return out
}

func (c *Comfy) Download(im Image) ([]byte, error) {
	q := fmt.Sprintf("/view?filename=%s&subfolder=%s&type=%s",
		urlQ(im.Filename), urlQ(im.Subfolder), urlQ(defaultStr(im.Type, "output")))
	req, err := http.NewRequest("GET", c.Base+q, nil)
	if err != nil {
		return nil, err
	}
	resp, err := c.do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != 200 {
		return nil, &HTTPError{Status: resp.StatusCode, Body: snippet(body), Path: "/view"}
	}
	return body, nil
}

// Upload pushes an input image and returns the name ComfyUI knows it by
// (prefixed with its subfolder when it lands in one).
func (c *Comfy) Upload(path, name string) (string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)
	part, err := w.CreateFormFile("image", name)
	if err != nil {
		return "", err
	}
	if _, err := part.Write(data); err != nil {
		return "", err
	}
	if err := w.WriteField("overwrite", "true"); err != nil {
		return "", err
	}
	if err := w.Close(); err != nil {
		return "", err
	}
	req, err := http.NewRequest("POST", c.Base+"/upload/image", &buf)
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", w.FormDataContentType())
	resp, err := c.do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return "", &HTTPError{Status: resp.StatusCode, Body: snippet(raw), Path: "/upload/image"}
	}
	var out struct {
		Name      string `json:"name"`
		Subfolder string `json:"subfolder"`
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return "", fmt.Errorf("/upload/image: nečekaná odpověď: %s", snippet(raw))
	}
	if out.Subfolder != "" {
		return out.Subfolder + "/" + out.Name, nil
	}
	return out.Name, nil
}

func urlQ(s string) string { return strings.ReplaceAll(strings.ReplaceAll(s, " ", "%20"), "&", "%26") }

func defaultStr(s, def string) string {
	if s == "" {
		return def
	}
	return s
}
