package main

import (
	"os"
	"path/filepath"
	"testing"
)

// Offloaded runs are symlinks to an external disk; they must still list,
// while a dangling link (disk unplugged) and plain files must not.
func TestIsRunDirFollowsSymlinks(t *testing.T) {
	base := t.TempDir()
	ext := t.TempDir()
	must := func(err error) {
		t.Helper()
		if err != nil {
			t.Fatal(err)
		}
	}
	must(os.Mkdir(filepath.Join(base, "real"), 0o755))
	must(os.Mkdir(filepath.Join(ext, "offloaded"), 0o755))
	must(os.Symlink(filepath.Join(ext, "offloaded"), filepath.Join(base, "linked")))
	must(os.Symlink(filepath.Join(ext, "missing"), filepath.Join(base, "dangling")))
	must(os.WriteFile(filepath.Join(base, "file.json"), []byte("{}"), 0o644))

	entries, err := os.ReadDir(base)
	must(err)
	want := map[string]bool{"real": true, "linked": true, "dangling": false, "file.json": false}
	for _, e := range entries {
		if got := isRunDir(base, e); got != want[e.Name()] {
			t.Errorf("isRunDir(%s) = %v, want %v", e.Name(), got, want[e.Name()])
		}
	}
}
