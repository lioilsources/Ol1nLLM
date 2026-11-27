package main

import (
	"embed"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"strings"
)

// The video studio's UI: a Svelte app (tools/lab/web) built into webdist/app
// by `make lab-web` and compiled into the binary. In git there is only
// webdist/.keep — without a build the page says how to make one.
//
//go:embed all:webdist
var webdistFS embed.FS

func (s *Server) handleStudio(w http.ResponseWriter, r *http.Request) {
	app, _ := fs.Sub(webdistFS, "webdist/app")
	rel := strings.TrimPrefix(r.URL.Path, "/video/")
	if rel != "" && rel != "index.html" {
		if f, err := app.Open(rel); err == nil {
			f.Close()
			w.Header().Set("Cache-Control", "no-cache")
			http.StripPrefix("/video/", http.FileServer(http.FS(app))).ServeHTTP(w, r)
			return
		}
	}
	data, err := fs.ReadFile(app, "index.html")
	if err != nil {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusServiceUnavailable)
		_, _ = io.WriteString(w, `<!doctype html><meta charset="utf-8"><title>lab · video</title>
<body style="background:#12100e;color:#f3efe8;font:14px/1.6 -apple-system,sans-serif;padding:40px">
<h1 style="font-weight:600">Video studio není sestavené</h1>
<p>Sestav ho z kořene repa: <code>make lab-web</code> (potřebuje <code>node</code>), pak restartuj <code>make lab</code>.</p>
<p>Bez studia funguje terminál: <code>lab video index | plan | render</code> — návod v <code>tools/lab/README.md</code>.</p>`)
		return
	}
	body := strings.ReplaceAll(string(data), "__LAB_TOKEN__", s.token)
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Content-Length", fmt.Sprint(len(body)))
	_, _ = io.WriteString(w, body)
}
