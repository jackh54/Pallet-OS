package main

import (
	"encoding/json"
	"os"
	"os/exec"
)

type DisplayOutput struct {
	Name        string   `json:"name"`
	Connected   bool     `json:"connected"`
	Primary     bool     `json:"primary"`
	CurrentMode string   `json:"current_mode,omitempty"`
	Modes       []string `json:"modes"`
}

type DisplayCurrent struct {
	Output string  `json:"output,omitempty"`
	Mode   string  `json:"mode,omitempty"`
	Scale  float64 `json:"scale,omitempty"`
}

type DisplayInfo struct {
	Outputs []DisplayOutput `json:"outputs"`
	Current DisplayCurrent  `json:"current"`
}

type DeviceSettingsFile struct {
	AutoUpdates   bool    `json:"auto_updates"`
	DisplayAuto   bool    `json:"display_auto"`
	DisplayOutput string  `json:"display_output,omitempty"`
	DisplayMode   string  `json:"display_mode,omitempty"`
	DisplayScale  float64 `json:"display_scale,omitempty"`
}

func loadDeviceSettingsFile() DeviceSettingsFile {
	out := DeviceSettingsFile{
		AutoUpdates: true,
		DisplayAuto: true,
		DisplayScale: 1.0,
	}
	data, err := os.ReadFile("/var/lib/pallet/settings.json")
	if err != nil {
		return out
	}
	_ = json.Unmarshal(data, &out)
	if out.DisplayScale == 0 {
		out.DisplayScale = 1.0
	}
	return out
}

func saveDeviceSettingsFile(s DeviceSettingsFile) error {
	_ = os.MkdirAll("/var/lib/pallet", 0o755)
	raw, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile("/var/lib/pallet/settings.json", raw, 0o644)
}

func loadDisplayInfo() DisplayInfo {
	out := DisplayInfo{}
	cmd := exec.Command("/usr/local/bin/pallet-x11-display", "list")
	data, err := cmd.Output()
	if err != nil {
		return out
	}
	_ = json.Unmarshal(data, &out)
	return out
}

func applyDisplaySettings() error {
	cmd := exec.Command("/usr/local/bin/pallet-x11-display", "apply")
	cmd.Env = os.Environ()
	if display := os.Getenv("DISPLAY"); display == "" {
		cmd.Env = append(cmd.Env, "DISPLAY=:0")
	}
	return cmd.Run()
}
