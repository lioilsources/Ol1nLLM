package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

// One lab run generates at a time on this machine. Every ComfyUI the lab
// talks to is SPARK — through the tunnel or over the LAN, two URLs for one
// GPU — so the lock is not keyed by URL. On 2026-11-23 a run started from the
// UI and a `lab resume` from the terminal interleaved their cells on the same
// queue: each saw the other's job as "someone else's", the pauses between
// cells vanished, and the GPU ran flat out until SPARK went down.
//
// An flock on a file in the user's cache: the kernel drops it when the
// process exits, however it exits, so a killed run never leaves a stale lock.
// The file holds who has it, for the message the next run prints.

// runLockPath is a variable so tests can point it elsewhere.
var runLockPath = func() string {
	dir, err := os.UserCacheDir()
	if err != nil {
		dir = os.TempDir()
	}
	return filepath.Join(dir, "ol1n-lab", "generate.lock")
}

// acquireRunLock takes the lock for runID or says who holds it. release is
// never nil on success.
func acquireRunLock(runID string) (release func(), err error) {
	path := runLockPath()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		holder := make([]byte, 256)
		n, _ := f.ReadAt(holder, 0)
		f.Close()
		who := strings.TrimSpace(string(holder[:n]))
		if who == "" {
			who = "neznámý proces"
		}
		return nil, fmt.Errorf("na ComfyUI už generuje jiný běh labu (%s) — "+
			"dva běhy by se prokládaly bez pauz; počkej, až skončí, nebo ho zruš", who)
	}
	_ = f.Truncate(0)
	_, _ = f.WriteAt([]byte(fmt.Sprintf("běh %s, pid %d", runID, os.Getpid())), 0)
	return func() {
		_ = f.Truncate(0)
		_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		f.Close()
	}, nil
}
