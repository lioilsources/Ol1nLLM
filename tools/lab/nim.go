package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// Nim is a client for gen-queue, the Go job queue that fronts the FLUX NIM
// models (AiStack, routed at llm.ol1n.com/nim/*).
//
// The protocol is the app's, from FluxNimService: POST /v1/infer returns 202
// and a job id immediately — which is how the app stays under Cloudflare's
// 100 s edge timeout — then the status is polled and the image comes from
// /result. Same CF Access service token as ComfyUI: one tunnel, one token.
//
// /result is a JPEG despite the .png name a cell is stored under (the app's
// own convention). Nothing here decodes it, and everything in the lab that
// does goes through image.Decode with both formats registered.
type Nim struct {
	Base   string
	id     string
	secret string
	http   *http.Client
}

func NewNim(base, id, secret string) *Nim {
	return &Nim{
		Base: strings.TrimRight(base, "/"), id: id, secret: secret,
		http: &http.Client{Timeout: 5 * time.Minute},
	}
}

func (n *Nim) HasCreds() bool { return n.id != "" && n.secret != "" }

func (n *Nim) do(req *http.Request) (*http.Response, error) {
	if !n.HasCreds() {
		return nil, fmt.Errorf("chybí CF_ACCESS_CLIENT_ID / CF_ACCESS_CLIENT_SECRET (viz .env.local)")
	}
	req.Header.Set("CF-Access-Client-Id", n.id)
	req.Header.Set("CF-Access-Client-Secret", n.secret)
	return n.http.Do(req)
}

// Submit enqueues one image and returns the job id with its queue position.
func (n *Nim) Submit(model string, body map[string]any) (string, int, error) {
	raw, err := json.Marshal(body)
	if err != nil {
		return "", 0, err
	}
	path := "/nim/" + model + "/v1/infer"
	req, err := http.NewRequest("POST", n.Base+path, bytes.NewReader(raw))
	if err != nil {
		return "", 0, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := n.do(req)
	if err != nil {
		return "", 0, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	// 202, not 200: the queue accepted the job, it did not render it.
	if resp.StatusCode != http.StatusAccepted {
		return "", 0, nimError(resp.StatusCode, data, path)
	}
	var out struct {
		ID            string `json:"id"`
		QueuePosition int    `json:"queue_position"`
	}
	if err := json.Unmarshal(data, &out); err != nil || out.ID == "" {
		return "", 0, fmt.Errorf("%s: nečekaná odpověď: %s", path, snippet(data))
	}
	return out.ID, out.QueuePosition, nil
}

type NimStatus struct {
	Status        string `json:"status"` // queued | running | done | error
	QueuePosition int    `json:"queue_position"`
	Error         string `json:"error"`
}

func (n *Nim) Status(model, job string) (NimStatus, error) {
	var out NimStatus
	path := "/nim/" + model + "/jobs/" + job
	req, err := http.NewRequest("GET", n.Base+path, nil)
	if err != nil {
		return out, err
	}
	resp, err := n.do(req)
	if err != nil {
		return out, err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return out, nimError(resp.StatusCode, data, path)
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return out, fmt.Errorf("%s: nečekaná odpověď: %s", path, snippet(data))
	}
	return out, nil
}

func (n *Nim) Result(model, job string) ([]byte, error) {
	path := "/nim/" + model + "/jobs/" + job + "/result"
	req, err := http.NewRequest("GET", n.Base+path, nil)
	if err != nil {
		return nil, err
	}
	resp, err := n.do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != 200 {
		return nil, nimError(resp.StatusCode, data, path)
	}
	return data, nil
}

// nimError keeps 401/403 as an HTTPError so the run loop's three-strikes auth
// abort covers gen-queue too — it is behind the same Access policy, so a wrong
// token fails every cell, not an unlucky one.
//
// A 404 is the queue's own answer, not a routing mistake: gen-queue evicts the
// job status together with the result an hour after completion, so the id is
// simply gone. Saying that beats "HTTP 404".
func nimError(status int, body []byte, path string) error {
	if status == 404 {
		return fmt.Errorf("gen-queue %s → job neexistuje: buď vypršelo hodinové "+
			"TTL výsledku, nebo byla fronta restartována", path)
	}
	return &HTTPError{Status: status, Body: snippet(body), Path: path, Service: "gen-queue"}
}
