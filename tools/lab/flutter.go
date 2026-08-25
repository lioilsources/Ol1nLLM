package main

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// flutterVersion resolves the toolchain at startup rather than at the first
// run: a GUI-launched shell has a different PATH than the interactive one, and
// discovering that after planning a 300-cell matrix is a waste.
func flutterVersion(root string) (bool, string) {
	path, err := exec.LookPath("flutter")
	if err != nil {
		return false, "flutter není v PATH"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, path, "--version")
	cmd.Dir = root
	out, err := cmd.CombinedOutput()
	if err != nil {
		return false, fmt.Sprintf("%s: %v", path, err)
	}
	first := strings.SplitN(strings.TrimSpace(string(out)), "\n", 2)[0]
	return true, first
}
