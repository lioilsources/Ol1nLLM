package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"image"
	"image/png"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// videoLab writes one fake run: two models × two styles × two prompts.
func videoLab(t *testing.T) string {
	t.Helper()
	lab := t.TempDir()
	dir := filepath.Join(lab, "20990101-000001")
	for _, d := range []string{"wf", "img", "thumb"} {
		if err := os.MkdirAll(filepath.Join(dir, d), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	var buf bytes.Buffer
	_ = png.Encode(&buf, image.NewRGBA(image.Rect(0, 0, 4, 6)))
	var cells []map[string]any
	for _, m := range []string{"a", "b"} {
		for p := 0; p < 2; p++ {
			for _, s := range []string{"", "cave"} {
				id := fmt.Sprintf("txt2img__%s__%s__p%d", m, s, p)
				cells = append(cells, map[string]any{"id": id, "flow": "txt2img", "model": m, "style": s,
					"promptIndex": p, "promptBody": fmt.Sprintf("s%d", p), "params": map[string]any{}})
				_ = os.WriteFile(filepath.Join(dir, "img", id+".png"), buf.Bytes(), 0o644)
			}
		}
	}
	man, _ := json.Marshal(map[string]any{"cells": cells, "prompts": []string{"s0", "s1"},
		"models": []map[string]string{{"id": "a", "label": "A"}, {"id": "b", "label": "B"}}})
	_ = os.WriteFile(filepath.Join(dir, "wf", "manifest.json"), man, 0o644)
	_ = os.WriteFile(filepath.Join(dir, "state.json"), []byte(`{"status":"done"}`), 0o644)
	return lab
}

func videoServer(t *testing.T) (*httptest.Server, string) {
	t.Helper()
	lab := videoLab(t)
	s := &Server{env: &Env{RepoRoot: t.TempDir()}, runs: map[string]*Run{}, token: "tok"}
	mux := http.NewServeMux()
	mux.HandleFunc("/video/", s.guard(s.handleStudio))
	newVideoAPI(lab).routes(mux, s.guard)
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv, lab
}

func call(t *testing.T, srv *httptest.Server, method, path string, body any) (int, map[string]any) {
	t.Helper()
	var rd *bytes.Reader
	if body != nil {
		data, _ := json.Marshal(body)
		rd = bytes.NewReader(data)
	} else {
		rd = bytes.NewReader(nil)
	}
	req, _ := http.NewRequest(method, srv.URL+path, rd)
	req.Header.Set("X-Lab-Token", "tok")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(res.Body).Decode(&out)
	return res.StatusCode, out
}

func TestVideoAPIIndexPlanAndMissingRoles(t *testing.T) {
	srv, _ := videoServer(t)
	code, idx := call(t, srv, "GET", "/api/video/index", nil)
	if code != 200 || len(idx["runs"].([]any)) != 1 || len(idx["templates"].([]any)) != 4 {
		t.Fatalf("index %d %v", code, idx)
	}
	src := map[string]any{"runs": []string{"20990101-000001"}}
	// Time on style only: prompt (2 values) has no role → 422 with the axis.
	code, out := call(t, srv, "POST", "/api/video/plan", map[string]any{"recipe": map[string]any{
		"source": src, "frame": map[string]any{"tiles": "model"}, "time": map[string]any{"axes": []string{"style"}}}})
	if code != 422 || out["missing"] == nil || !strings.Contains(fmt.Sprint(out["missing"]), "prompt") {
		t.Fatalf("chybějící role: %d %v", code, out)
	}
	code, out = call(t, srv, "POST", "/api/video/plan", map[string]any{"recipe": map[string]any{
		"source": src, "frame": map[string]any{"tiles": "model"}}})
	if code != 200 || out["slides"].(float64) != 4 {
		t.Fatalf("plán: %d %v", code, out)
	}
	id := out["id"].(string)
	code, sl := call(t, srv, "GET", "/api/video/plans/"+id+"/slides?from=1&to=3", nil)
	if code != 200 || len(sl["slides"].([]any)) != 2 {
		t.Fatalf("stránka snímků: %d %v", code, sl)
	}
	code, cov := call(t, srv, "POST", "/api/video/coverage", map[string]any{"source": src})
	if code != 200 || cov["coverage"] == nil {
		t.Fatalf("pokrytí: %d %v", code, cov)
	}
	code, tm := call(t, srv, "POST", "/api/video/template", map[string]any{"source": src, "template": "mix"})
	if code != 200 || !strings.Contains(fmt.Sprint(tm["recipe"]), "loose") {
		t.Fatalf("šablona: %d %v", code, tm)
	}
}

func TestVideoAPIRecipesAndYAML(t *testing.T) {
	srv, lab := videoServer(t)
	rec := map[string]any{"source": map[string]any{"runs": []string{"20990101-000001"}}, "time": map[string]any{"rate": 3}}
	if code, out := call(t, srv, "PUT", "/api/video/recipes/muj", map[string]any{"recipe": rec}); code != 200 {
		t.Fatalf("uložit: %d %v", code, out)
	}
	if _, err := os.Stat(filepath.Join(lab, "_video", "muj", "recipe.yaml")); err != nil {
		t.Fatal("recept má být v build/lab/_video/<jméno>/recipe.yaml")
	}
	code, out := call(t, srv, "GET", "/api/video/recipes/muj", nil)
	if code != 200 || !strings.Contains(out["yaml"].(string), "rate: 3") {
		t.Fatalf("načíst: %d %v", code, out)
	}
	for _, bad := range []string{"..", ".skryty", "a%2Fb"} {
		if code, _ := call(t, srv, "PUT", "/api/video/recipes/"+bad, map[string]any{"recipe": rec}); code == 200 {
			t.Fatalf("jméno %q se nemá přijmout", bad)
		}
	}
	code, out = call(t, srv, "POST", "/api/video/parse", map[string]any{"yaml": "source: {runs: [x]}\ntime: {tempo: 3}\n"})
	if code != 422 || !strings.Contains(fmt.Sprint(out["error"]), "tempo") {
		t.Fatalf("YAML s neznámým klíčem: %d %v", code, out)
	}
	if code, _ := call(t, srv, "POST", "/api/video/reveal", map[string]any{"path": "../../etc/hosts"}); code == 200 {
		t.Fatal("reveal mimo _video")
	}
}

func TestVideoAPINeedsTokenForWrites(t *testing.T) {
	srv, _ := videoServer(t)
	res, err := http.Post(srv.URL+"/api/video/plan", "application/json", strings.NewReader("{}"))
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusForbidden {
		t.Fatalf("POST bez tokenu: %d", res.StatusCode)
	}
}

func TestStudioPageServesTokenOrHowToBuild(t *testing.T) {
	srv, _ := videoServer(t)
	res, err := http.Get(srv.URL + "/video/")
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	var b bytes.Buffer
	_, _ = b.ReadFrom(res.Body)
	body := b.String()
	if _, err := webdistFS.Open("webdist/app/index.html"); err == nil {
		if res.StatusCode != 200 || !strings.Contains(body, `content="tok"`) {
			t.Fatalf("studio má dostat token: %d", res.StatusCode)
		}
	} else if res.StatusCode != 503 || !strings.Contains(body, "make lab-web") {
		t.Fatalf("nesestavené studio má říct jak sestavit: %d %s", res.StatusCode, body)
	}
}
