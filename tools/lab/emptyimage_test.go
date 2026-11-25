package main

import (
	"os"
	"path/filepath"
	"testing"
)

// An empty download must not land on disk as a "finished" cell: resume
// decides by the file, so a 0-byte PNG was never redone.
func TestSaveImageRefusesEmptyAndHasImageIgnoresIt(t *testing.T) {
	dir := t.TempDir()
	for _, d := range []string{"img", "thumb"} {
		if err := os.MkdirAll(filepath.Join(dir, d), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	r := NewRun(&Env{}, dir, &Spec{})
	if err := r.saveImage("c1", nil); err == nil {
		t.Fatal("prázdná data mají být chyba")
	}
	if _, err := os.Stat(r.imgPath("c1")); err == nil {
		t.Fatal("prázdný obrázek se nemá zapsat")
	}
	if err := os.WriteFile(r.imgPath("c2"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if hasImage(r.imgPath("c2")) {
		t.Fatal("0bajtový soubor se nemá počítat jako hotová buňka")
	}
}
