package main

import (
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

//go:embed dist/*
var staticFS embed.FS

type ShellApp struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Icon   string `json:"icon,omitempty"`
	Exec   string `json:"exec"`
	Type   string `json:"type"`
	Pinned bool   `json:"pinned,omitempty"`
}

type ShellPolicy struct {
	ShowFileManager bool       `json:"show_file_manager"`
	ShowTerminal    bool       `json:"show_terminal"`
	LauncherApps    []ShellApp `json:"launcher_apps"`
}

type ShellConfig struct {
	Wallpaper      string   `json:"wallpaper"`
	Apps           []ShellApp `json:"apps"`
	Pinned         []string `json:"pinned"`
	Running        []string `json:"running"`
	Clock          string   `json:"clock"`
	WifiSSID       string   `json:"wifi_ssid"`
	BatteryPercent *int     `json:"battery_percent"`
	Locked         bool     `json:"locked"`
}

var (
	mu       sync.Mutex
	running  = map[string]bool{}
	pinned   = []string{"chromium", "launcher"}
)

func main() {
	port := envOr("PALLET_SHELL_PORT", "7420")
	mux := http.NewServeMux()

	dist, err := fs.Sub(staticFS, "dist")
	if err != nil {
		log.Fatal(err)
	}
	fileServer := http.FileServer(http.FS(dist))

	mux.HandleFunc("/api/config", handleConfig)
	mux.HandleFunc("/api/launch", handleLaunch)
	mux.HandleFunc("/api/launcher", handleLauncher)
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" && !strings.Contains(r.URL.Path, ".") {
			r.URL.Path = "/"
		}
		fileServer.ServeHTTP(w, r)
	})

	addr := ":" + port
	log.Printf("pallet-shell listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}

func handleConfig(w http.ResponseWriter, r *http.Request) {
	cfg := buildConfig()
	writeJSON(w, cfg)
}

func handleLaunch(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var body struct {
		ID string `json:"id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	apps := allApps()
	var app *ShellApp
	for _, a := range apps {
		if a.ID == body.ID {
			copy := a
			app = &copy
			break
		}
	}
	if app == nil {
		http.Error(w, "unknown app", http.StatusNotFound)
		return
	}
	if err := launchExec(app.Exec); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	mu.Lock()
	running[app.ID] = true
	mu.Unlock()
	writeJSON(w, map[string]any{"ok": true})
}

func handleLauncher(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, map[string]any{"ok": true})
}

func buildConfig() ShellConfig {
	apps := allApps()
	mu.Lock()
	runList := make([]string, 0, len(running))
	for id := range running {
		runList = append(runList, id)
	}
	mu.Unlock()

	wallpaper := "/var/lib/pallet/wallpaper.jpg"
	if _, err := os.Stat(wallpaper); err != nil {
		wallpaper = ""
	}

	return ShellConfig{
		Wallpaper:      wallpaper,
		Apps:           apps,
		Pinned:         pinned,
		Running:        runList,
		Clock:          time.Now().Format("3:04 PM"),
		WifiSSID:       wifiSSID(),
		BatteryPercent: batteryPercent(),
		Locked:         false,
	}
}

func allApps() []ShellApp {
	apps := defaultApps()
	apps = append(apps, loadPolicyApps()...)
	apps = append(apps, listAndroidApps()...)
	return dedupeApps(apps)
}

func defaultApps() []ShellApp {
	return []ShellApp{
		{ID: "chromium", Name: "Browser", Exec: "chromium --new-window", Type: "web", Pinned: true},
		{ID: "launcher", Name: "Launcher", Exec: "true", Type: "native", Pinned: true},
	}
}

func loadPolicyApps() []ShellApp {
	path := "/var/lib/pallet/shell-policy.json"
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var policy ShellPolicy
	if err := json.Unmarshal(data, &policy); err != nil {
		return nil
	}
	return policy.LauncherApps
}

func listAndroidApps() []ShellApp {
	out, err := exec.Command("waydroid", "app", "list").Output()
	if err != nil {
		return nil
	}
	var apps []ShellApp
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.Fields(line)
		if len(parts) < 2 {
			continue
		}
		pkg := parts[0]
		name := strings.Join(parts[1:], " ")
		apps = append(apps, ShellApp{
			ID:   "android-" + pkg,
			Name: name,
			Exec: "waydroid app launch " + pkg,
			Type: "android",
		})
	}
	return apps
}

func dedupeApps(apps []ShellApp) []ShellApp {
	seen := map[string]bool{}
	var out []ShellApp
	for _, a := range apps {
		if seen[a.ID] {
			continue
		}
		seen[a.ID] = true
		out = append(out, a)
	}
	return out
}

func launchExec(command string) error {
	if command == "" || command == "true" {
		return nil
	}
	parts := strings.Fields(command)
	if len(parts) == 0 {
		return nil
	}
	cmd := exec.Command(parts[0], parts[1:]...)
	cmd.Env = os.Environ()
	return cmd.Start()
}

func wifiSSID() string {
	out, err := exec.Command("nmcli", "-t", "-f", "active,ssid", "dev", "wifi").Output()
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(out), "\n") {
		parts := strings.Split(line, ":")
		if len(parts) == 2 && parts[0] == "yes" {
			return parts[1]
		}
	}
	return ""
}

func batteryPercent() *int {
	entries, _ := filepath.Glob("/sys/class/power_supply/BAT*/capacity")
	if len(entries) == 0 {
		return nil
	}
	data, err := os.ReadFile(entries[0])
	if err != nil {
		return nil
	}
	var pct int
	fmt.Sscanf(strings.TrimSpace(string(data)), "%d", &pct)
	return &pct
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(v)
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// placeholder to satisfy embed when dist missing during dev
var _ = io.Discard
