package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

type Policy struct {
	Version      int64          `json:"version"`
	WallpaperURL string         `json:"wallpaper_url"`
	Chromium     map[string]any `json:"chromium"`
	Android      AndroidPolicy  `json:"android"`
	Shell        ShellPolicy    `json:"shell"`
	Updates      UpdatesPolicy  `json:"updates"`
}

type AndroidPolicy struct {
	ForceInstall []string `json:"force_install"`
	Allowlist    []string `json:"allowlist"`
	Blocklist    []string `json:"blocklist"`
}

type ShellPolicy struct {
	ShowFileManager bool         `json:"show_file_manager"`
	ShowTerminal    bool         `json:"show_terminal"`
	LauncherApps    []LauncherApp `json:"launcher_apps"`
}

type LauncherApp struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Exec string `json:"exec"`
	Type string `json:"type"`
}

type Telemetry struct {
	Hostname      string        `json:"hostname"`
	UptimeSeconds int64         `json:"uptime_seconds"`
	IPAddresses   []string      `json:"ip_addresses"`
	AgentVersion  string        `json:"agent_version"`
	OSVersion     string        `json:"os_version"`
	InstalledApps []InstalledApp `json:"installed_apps"`
	BatteryPercent *int         `json:"battery_percent,omitempty"`
	WifiSSID      string        `json:"wifi_ssid,omitempty"`
}

type InstalledApp struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Version string `json:"version,omitempty"`
	Type    string `json:"type"`
	Package string `json:"package,omitempty"`
}

func collectTelemetry() (Telemetry, error) {
	hostname, _ := os.Hostname()
	ips := localIPs()
	apps := listInstalledApps()
	battery := batteryPercent()
	ssid := wifiSSID()
	return Telemetry{
		Hostname:       hostname,
		UptimeSeconds:  uptimeSeconds(),
		IPAddresses:    ips,
		AgentVersion:   agentVersion,
		OSVersion:      osVersion(),
		InstalledApps:  apps,
		BatteryPercent: battery,
		WifiSSID:       ssid,
	}, nil
}

func localIPs() []string {
	var ips []string
	ifaces, err := net.Interfaces()
	if err != nil {
		return ips
	}
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			var ip net.IP
			switch v := addr.(type) {
			case *net.IPNet:
				ip = v.IP
			case *net.IPAddr:
				ip = v.IP
			}
			if ip == nil || ip.IsLoopback() {
				continue
			}
			ip = ip.To4()
			if ip != nil {
				ips = append(ips, ip.String())
			}
		}
	}
	return ips
}

func uptimeSeconds() int64 {
	data, err := os.ReadFile("/proc/uptime")
	if err != nil {
		return 0
	}
	fields := strings.Fields(string(data))
	if len(fields) == 0 {
		return 0
	}
	var up float64
	fmt.Sscanf(fields[0], "%f", &up)
	return int64(up)
}

func osVersion() string {
	data, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return runtime.GOOS
	}
	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(line, "PRETTY_NAME=") {
			return strings.Trim(strings.TrimPrefix(line, "PRETTY_NAME="), "\"")
		}
	}
	return "Linux"
}

func listInstalledApps() []InstalledApp {
	apps := []InstalledApp{
		{ID: "chromium", Name: "Chromium", Type: "web"},
	}
	androidApps, _ := listWaydroidApps()
	apps = append(apps, androidApps...)
	return apps
}

func listWaydroidApps() ([]InstalledApp, error) {
	cmd := exec.Command("waydroid", "app", "list")
	out, err := cmd.Output()
	if err != nil {
		return nil, err
	}
	var apps []InstalledApp
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.Fields(line)
		if len(parts) < 2 {
			continue
		}
		apps = append(apps, InstalledApp{
			ID:      parts[0],
			Name:    strings.Join(parts[1:], " "),
			Type:    "android",
			Package: parts[0],
		})
	}
	return apps, nil
}

func batteryPercent() *int {
	entries, err := filepath.Glob("/sys/class/power_supply/BAT*/capacity")
	if err != nil || len(entries) == 0 {
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

func wifiSSID() string {
	cmd := exec.Command("nmcli", "-t", "-f", "active,ssid", "dev", "wifi")
	out, err := cmd.Output()
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

func applyPolicy(policy Policy) error {
	if err := writeChromiumPolicy(policy.Chromium); err != nil {
		return err
	}
	if policy.WallpaperURL != "" {
		if err := downloadWallpaper(policy.WallpaperURL); err != nil {
			logPrintf("wallpaper: %v", err)
		}
	}
	if err := writeShellConfig(policy); err != nil {
		return err
	}
	if err := reconcileAndroidApps(policy.Android); err != nil {
		return err
	}
	return nil
}

func writeChromiumPolicy(chromium map[string]any) error {
	if chromium == nil {
		return nil
	}
	dir := "/etc/chromium/policies/managed"
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	path := filepath.Join(dir, "pallet_policy.json")
	raw, err := json.MarshalIndent(chromium, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, raw, 0o644)
}

func downloadWallpaper(url string) error {
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	path := "/var/lib/pallet/wallpaper.jpg"
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = io.Copy(f, resp.Body)
	if err != nil {
		return err
	}
	meta := map[string]string{"wallpaper": path}
	raw, _ := json.Marshal(meta)
	return os.WriteFile("/var/lib/pallet/shell.json", raw, 0o644)
}

func writeShellConfig(policy Policy) error {
	path := "/var/lib/pallet/shell-policy.json"
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	raw, err := json.MarshalIndent(policy.Shell, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, raw, 0o644)
}

func reconcileAndroidApps(android AndroidPolicy) error {
	if !waydroidAvailable() {
		return nil
	}
	for _, pkg := range android.ForceInstall {
		if pkg == "" {
			continue
		}
		_ = installAndroidApp(pkg)
	}
	installed, err := listWaydroidApps()
	if err != nil {
		return nil
	}
	allow := map[string]bool{}
	for _, p := range android.Allowlist {
		allow[p] = true
	}
	if len(android.Allowlist) == 0 {
		return nil
	}
	for _, app := range installed {
		if !allow[app.Package] {
			_ = removeAndroidApp(app.Package)
		}
	}
	return nil
}

func waydroidAvailable() bool {
	_, err := exec.LookPath("waydroid")
	return err == nil
}

func installAndroidApp(pkg string) error {
	if !waydroidAvailable() {
		return fmt.Errorf("waydroid not available")
	}
	return exec.Command("waydroid", "app", "install", pkg).Run()
}

func removeAndroidApp(pkg string) error {
	if !waydroidAvailable() {
		return fmt.Errorf("waydroid not available")
	}
	return exec.Command("waydroid", "app", "remove", pkg).Run()
}

func ensureLocked() {
	_ = exec.Command("loginctl", "lock-sessions").Run()
	_ = exec.Command("pallet-lock", "--enable").Run()
}

func unlockScreen() {
	_ = exec.Command("loginctl", "unlock-sessions").Run()
	_ = exec.Command("pallet-lock", "--disable").Run()
}

func wipeDevice() {
	time.Sleep(2 * time.Second)
	_ = exec.Command("systemctl", "stop", "pallet-agent").Run()
	_ = exec.Command("rm", "-rf", "/home/pallet/*").Run()
	_ = exec.Command("waydroid", "container", "stop").Run()
	_ = exec.Command("rm", "-rf", "/var/lib/waydroid").Run()
}

func logPrintf(format string, args ...any) {
	fmt.Printf("[pallet-agent] "+format+"\n", args...)
}
