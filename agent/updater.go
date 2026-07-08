package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const defaultGitHubRepo = "jackh54/Pallet-OS"

type UpdatesPolicy struct {
	Enabled    bool   `json:"enabled"`
	Auto       bool   `json:"auto"`
	GitHubRepo string `json:"github_repo"`
	Channel    string `json:"channel"`
}

type UpdateStatus struct {
	CheckedAt       string `json:"checked_at"`
	CurrentAgent    string `json:"current_agent"`
	CurrentShell    string `json:"current_shell"`
	LatestVersion   string `json:"latest_version"`
	UpdateAvailable bool   `json:"update_available"`
	LastMessage     string `json:"last_message"`
	LastError       string `json:"last_error,omitempty"`
	AutoUpdates     bool   `json:"auto_updates"`
}

type DeviceSettings struct {
	AutoUpdates bool `json:"auto_updates"`
}

type gitHubRelease struct {
	TagName string `json:"tag_name"`
	Assets  []struct {
		Name               string `json:"name"`
		BrowserDownloadURL string `json:"browser_download_url"`
	} `json:"assets"`
}

var lastUpdateCheck time.Time

func maybeApplyUpdates(policy Policy) {
	up := policy.Updates
	if !up.Enabled {
		return
	}
	forced := forceUpdateCheckRequested()
	if !forced && time.Since(lastUpdateCheck) < 6*time.Hour {
		return
	}
	lastUpdateCheck = time.Now()
	if forced {
		_ = os.Remove("/var/lib/pallet/force-update-check")
	}
	status := checkForUpdates(up.GitHubRepo)
	writeUpdateStatus(status)
	settings := loadDeviceSettings()
	auto := up.Auto || settings.AutoUpdates
	if !status.UpdateAvailable || !auto {
		return
	}
	if err := applyGitHubRelease(up.GitHubRepo, status.LatestVersion); err != nil {
		status.LastError = err.Error()
		writeUpdateStatus(status)
		logPrintf("update failed: %v", err)
		return
	}
	status.LastMessage = fmt.Sprintf("Updated to %s", status.LatestVersion)
	status.CurrentAgent = agentVersion
	status.CurrentShell = installedShellVersion()
	status.UpdateAvailable = false
	writeUpdateStatus(status)
	writeInstalledVersions(status.LatestVersion)
}

func installedShellVersion() string {
	if data, err := os.ReadFile("/var/lib/pallet/versions.json"); err == nil {
		var v struct {
			Shell string `json:"shell"`
		}
		if json.Unmarshal(data, &v) == nil && v.Shell != "" {
			return v.Shell
		}
	}
	return "1.0.0"
}

func writeInstalledVersions(version string) {
	_ = os.MkdirAll("/var/lib/pallet", 0o755)
	raw, _ := json.MarshalIndent(map[string]string{
		"agent": agentVersion,
		"shell": version,
	}, "", "  ")
	_ = os.WriteFile("/var/lib/pallet/versions.json", raw, 0o644)
}

func loadDeviceSettings() DeviceSettings {
	var s DeviceSettings
	s.AutoUpdates = true
	data, err := os.ReadFile("/var/lib/pallet/settings.json")
	if err != nil {
		return s
	}
	_ = json.Unmarshal(data, &s)
	return s
}

func forceUpdateCheckRequested() bool {
	_, err := os.Stat("/var/lib/pallet/force-update-check")
	return err == nil
}

func checkForUpdates(repo string) UpdateStatus {
	if repo == "" {
		repo = defaultGitHubRepo
	}
	status := UpdateStatus{
		CheckedAt:    time.Now().UTC().Format(time.RFC3339),
		CurrentAgent: agentVersion,
		CurrentShell: installedShellVersion(),
		AutoUpdates:  loadDeviceSettings().AutoUpdates,
	}
	client := &http.Client{Timeout: 30 * time.Second}
	url := fmt.Sprintf("https://api.github.com/repos/%s/releases/latest", repo)
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "pallet-agent")
	resp, err := client.Do(req)
	if err != nil {
		status.LastError = err.Error()
		return status
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		status.LastError = fmt.Sprintf("github api %d: %s", resp.StatusCode, string(body))
		return status
	}
	var release gitHubRelease
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		status.LastError = err.Error()
		return status
	}
	latest := strings.TrimPrefix(release.TagName, "v")
	status.LatestVersion = latest
	status.UpdateAvailable = versionLess(agentVersion, latest) || versionLess(installedShellVersion(), latest)
	if status.UpdateAvailable {
		status.LastMessage = fmt.Sprintf("Pallet OS %s is available", release.TagName)
	} else {
		status.LastMessage = "You're up to date"
	}
	return status
}

func applyGitHubRelease(repo, version string) error {
	if repo == "" {
		repo = defaultGitHubRepo
	}
	tag := version
	if !strings.HasPrefix(tag, "v") {
		tag = "v" + tag
	}
	client := &http.Client{Timeout: 120 * time.Second}
	url := fmt.Sprintf("https://api.github.com/repos/%s/releases/tags/%s", repo, tag)
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "pallet-agent")
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("release fetch failed: %s", string(body))
	}
	var release gitHubRelease
	if err := json.NewDecoder(resp.Body).Decode(&release); err != nil {
		return err
	}
	assets := map[string]string{}
	for _, a := range release.Assets {
		assets[a.Name] = a.BrowserDownloadURL
	}
	if err := downloadBinary(client, assets["pallet-shell-linux-amd64"], "/usr/local/bin/pallet-shell"); err != nil {
		return fmt.Errorf("shell: %w", err)
	}
	_ = runCmd("systemctl", "restart", "pallet-shell")
	if err := downloadBinary(client, assets["pallet-agent-linux-amd64"], "/usr/local/bin/pallet-agent"); err != nil {
		return fmt.Errorf("agent: %w", err)
	}
	go runCmd("systemctl", "restart", "pallet-agent")
	return nil
}

func downloadBinary(client *http.Client, url, dest string) error {
	if url == "" {
		return fmt.Errorf("binary not found in release assets for %s", filepath.Base(dest))
	}
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("download %s: http %d", dest, resp.StatusCode)
	}
	tmp := dest + ".new"
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o755)
	if err != nil {
		return err
	}
	if _, err := io.Copy(f, resp.Body); err != nil {
		f.Close()
		os.Remove(tmp)
		return err
	}
	f.Close()
	if err := os.Rename(tmp, dest); err != nil {
		return err
	}
	return nil
}

func writeUpdateStatus(status UpdateStatus) {
	_ = os.MkdirAll("/var/lib/pallet", 0o755)
	raw, _ := json.MarshalIndent(status, "", "  ")
	_ = os.WriteFile("/var/lib/pallet/update-status.json", raw, 0o644)
}

func versionLess(current, latest string) bool {
	current = strings.TrimPrefix(strings.TrimSpace(current), "v")
	latest = strings.TrimPrefix(strings.TrimSpace(latest), "v")
	if current == latest {
		return false
	}
	c := strings.Split(current, ".")
	l := strings.Split(latest, ".")
	for i := 0; i < 3; i++ {
		var cv, lv int
		if i < len(c) {
			fmt.Sscanf(c[i], "%d", &cv)
		}
		if i < len(l) {
			fmt.Sscanf(l[i], "%d", &lv)
		}
		if lv > cv {
			return true
		}
		if lv < cv {
			return false
		}
	}
	return latest != current
}
