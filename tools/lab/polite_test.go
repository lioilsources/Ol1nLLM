package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestMain keeps the suite off SPARK and off the machine-wide run lock: the
// thermal guard defaults to ssh, and a lab run on this Mac would otherwise
// make every non-dry Generate in the tests fail on the lock.
func TestMain(m *testing.M) {
	os.Setenv("LAB_THERMAL_CMD", "")
	dir, _ := os.MkdirTemp("", "lab-lock")
	runLockPath = func() string { return filepath.Join(dir, "generate.lock") }
	code := m.Run()
	os.RemoveAll(dir)
	os.Exit(code)
}

// thermalScript writes readings, one per call, to a file the command pops
// from; an empty line is an unreadable temperature.
func thermalScript(t *testing.T, readings ...string) string {
	t.Helper()
	dir := t.TempDir()
	data := filepath.Join(dir, "r")
	if err := os.WriteFile(data, []byte(strings.Join(readings, "\n")+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return "head -1 " + data + "; sed -i '' 1d " + data + " 2>/dev/null || sed -i 1d " + data
}

func guard(cmd string) (polite, *[]time.Duration, *[]string) {
	p := polite{thermalCmd: cmd, thermalMax: 95, thermalResume: 90, thermal: &thermalState{}}
	var said []string
	p.say = func(m string) { said = append(said, m) }
	var slept []time.Duration
	return p, &slept, &said
}

func sleeper(slept *[]time.Duration) func(time.Duration) bool {
	return func(d time.Duration) bool { *slept = append(*slept, d); return true }
}

func TestPoliteDefaultsGuardOn(t *testing.T) {
	t.Setenv("LAB_THERMAL_MAX", "")
	t.Setenv("LAB_THERMAL_RESUME", "")
	os.Unsetenv("LAB_THERMAL_CMD")
	defer os.Setenv("LAB_THERMAL_CMD", "")
	p := politeFromEnv()
	if p.thermalCmd != defaultThermalCmd || p.thermalMax != 95 || p.thermalResume != 90 {
		t.Fatalf("guard should be on by default: %q %v %v", p.thermalCmd, p.thermalMax, p.thermalResume)
	}
	t.Setenv("LAB_THERMAL_CMD", "")
	if p := politeFromEnv(); p.thermalCmd != "" {
		t.Fatalf("an empty LAB_THERMAL_CMD turns the guard off, got %q", p.thermalCmd)
	}
}

func TestCoolHoldsWhileHot(t *testing.T) {
	p, slept, _ := guard(thermalScript(t, "96.5", "92", "89.9"))
	p.cool(sleeper(slept))
	if len(*slept) != 2 {
		t.Fatalf("hot 96.5 → 92 → 89.9 should wait twice, waited %d×", len(*slept))
	}
}

func TestCoolPassesWhenCool(t *testing.T) {
	p, slept, _ := guard(thermalScript(t, "70"))
	p.cool(sleeper(slept))
	if len(*slept) != 0 {
		t.Fatalf("70 °C should not wait, waited %d×", len(*slept))
	}
}

// One or two unreadable temperatures are a blip; the third in a row holds the
// run until a reading comes back.
func TestCoolFailsClosed(t *testing.T) {
	p, slept, said := guard(thermalScript(t, "", "", "", "", "80"))
	for i := 0; i < 2; i++ {
		p.thermal.at = time.Time{}
		p.cool(sleeper(slept))
		if len(*slept) != 0 {
			t.Fatalf("miss %d should not hold yet", i+1)
		}
	}
	p.thermal.at = time.Time{}
	p.cool(sleeper(slept))
	if len(*slept) != 2 {
		t.Fatalf("third miss should hold until a reading (two more minutes), waited %d×", len(*slept))
	}
	if len(*said) == 0 || !strings.Contains((*said)[0], "nejde přečíst") {
		t.Fatalf("the hold should say why: %q", *said)
	}
	if p.thermal.misses != 0 {
		t.Fatalf("a good reading resets the misses, got %d", p.thermal.misses)
	}
}

func TestCoolReadsOncePerMinute(t *testing.T) {
	p, slept, _ := guard(thermalScript(t, "70", "99"))
	p.cool(sleeper(slept))
	p.cool(sleeper(slept)) // within the minute: 99 is never read
	if len(*slept) != 0 {
		t.Fatalf("second call inside a minute should not read, waited %d×", len(*slept))
	}
}

func TestRunLockExcludesSecondRun(t *testing.T) {
	release, err := acquireRunLock("A")
	if err != nil {
		t.Fatal(err)
	}
	// flock is per open file description, so a second open in the same
	// process conflicts exactly like a second process would.
	if _, err := acquireRunLock("B"); err == nil || !strings.Contains(err.Error(), "běh A") {
		t.Fatalf("second run should be refused naming the first, got %v", err)
	}
	release()
	release2, err := acquireRunLock("B")
	if err != nil {
		t.Fatalf("after release the lock should be free: %v", err)
	}
	release2()
}
