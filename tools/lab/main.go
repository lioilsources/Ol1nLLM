// Command lab drives batch ComfyUI experiments for the Ol1nLLM Image Studio.
//
// Workflows are not built here — they are dumped by the app's own code
// (tools/lab/dump.dart via `flutter test`), so what the lab measures is what
// the app actually sends. This binary plans the matrix, runs it, scores it and
// serves the web UI.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const (
	defaultComfyURL = "https://comfyui.ol1n.com"
	defaultPort     = 8765
)

type Env struct {
	RepoRoot   string
	ComfyURL   string
	ClientID   string
	Secret     string
	Comfy      *Comfy
	FlutterOK  bool
	FlutterMsg string
}

func loadEnv() (*Env, error) {
	root, err := repoRoot()
	if err != nil {
		return nil, err
	}
	vals := parseDotEnv(filepath.Join(root, ".env.local"))
	get := func(k, def string) string {
		if v := os.Getenv(k); v != "" {
			return v
		}
		if v := vals[k]; v != "" {
			return v
		}
		return def
	}
	e := &Env{
		RepoRoot: root,
		ComfyURL: get("COMFYUI_URL", defaultComfyURL),
		ClientID: get("CF_ACCESS_CLIENT_ID", ""),
		Secret:   get("CF_ACCESS_CLIENT_SECRET", ""),
	}
	e.Comfy = NewComfy(e.ComfyURL, e.ClientID, e.Secret)
	e.FlutterOK, e.FlutterMsg = flutterVersion(root)
	return e, nil
}

// repoRoot walks up from the working directory to the Flutter package root.
// dump.dart reads assets/comfyui/*.json through package-relative paths, so
// every subprocess must run from there regardless of where lab was started.
func repoRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "pubspec.yaml")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("nenašel jsem kořen repa (pubspec.yaml) — spusť lab uvnitř projektu")
		}
		dir = parent
	}
}

// parseDotEnv reads KEY=value lines. Missing file is not an error: the server
// still starts so the UI can explain what is missing, and dry runs need no
// credentials at all.
func parseDotEnv(path string) map[string]string {
	out := map[string]string{}
	f, err := os.Open(path)
	if err != nil {
		return out
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		v = strings.TrimSpace(v)
		v = strings.Trim(v, `"'`)
		out[strings.TrimSpace(k)] = v
	}
	return out
}

func usage() {
	fmt.Fprint(os.Stderr, `lab — batch experimenty nad ComfyUI přes kód appky

  lab serve [--port 8765] [--open] [--force-dry]   webové UI
  lab check                                        ověří flutter, CF Access a ComfyUI
  lab run --out DIR [přepínače]                    dávka z terminálu
  lab score DIR                                    přepočítat metriky

Přepínače pro `+"`lab run`"+` odpovídají ovládacím prvkům v UI:
  --models a,b   --prompts soubor   --styles a,b   --styles-file f.json
  --flows txt2img,img2img,repose    --pose none|depth|template  --pose-id ol3
  --ref obrázek.png | --ref-prompt "…"   --seed 777  --batch 1
  --sweep cíl=v1,v2,v3              --override cíl=hodnota   --dry
`)
}

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	cmd := os.Args[1]
	args := os.Args[2:]
	env, err := loadEnv()
	if err != nil {
		fatal(err)
	}
	switch cmd {
	case "serve":
		fs := flag.NewFlagSet("serve", flag.ExitOnError)
		port := fs.Int("port", defaultPort, "port")
		open := fs.Bool("open", false, "otevřít prohlížeč")
		dry := fs.Bool("force-dry", false, "nikdy neodesílat na ComfyUI")
		_ = fs.Parse(args)
		fatal(serve(env, *port, *open, *dry))
	case "check":
		fatal(check(env))
	case "run":
		fatal(runCLI(env, args))
	case "score":
		fatal(scoreCLI(env, args))
	case "-h", "--help", "help":
		usage()
	default:
		usage()
		os.Exit(2)
	}
}

func fatal(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "chyba:", err)
		os.Exit(1)
	}
}

// check is the pre-flight the UI shows in its header: without these three
// green, every later failure is a red herring.
func check(env *Env) error {
	fmt.Printf("kořen repa   %s\n", env.RepoRoot)
	fmt.Printf("flutter      %s\n", statusLine(env.FlutterOK, env.FlutterMsg))
	fmt.Printf("CF Access    %s\n", statusLine(env.Comfy.HasCreds(),
		"CF_ACCESS_CLIENT_ID / _SECRET (.env.local)"))
	fmt.Printf("ComfyUI      %s\n", env.ComfyURL)
	if !env.Comfy.HasCreds() {
		fmt.Println("             přeskočeno — bez creds; dry-run funguje i tak")
		return nil
	}
	ck, err := env.Comfy.Checkpoints()
	if err != nil {
		fmt.Printf("             ✗ %v\n", err)
		return nil
	}
	q, err := env.Comfy.Queue()
	if err != nil {
		fmt.Printf("             ✗ %v\n", err)
		return nil
	}
	fmt.Printf("             ✓ %d checkpointů, fronta běží=%d čeká=%d\n",
		len(ck), q.Running, q.Pending)
	return nil
}

func statusLine(ok bool, msg string) string {
	if ok {
		return "✓ " + msg
	}
	return "✗ " + msg
}
