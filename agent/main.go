package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

var agentVersion = "1.0.0"

func main() {
	serverURL := flag.String("server", "", "Control server URL (overrides config)")
	configPath := flag.String("config", "/etc/pallet/agent.json", "Agent config path")
	enrollToken := flag.String("enroll", "", "One-time enrollment token")
	enrollOnly := flag.Bool("enroll-only", false, "Enroll device and exit (do not start heartbeat loop)")
	flag.Parse()

	cfg, err := loadConfig(*configPath)
	if err != nil && !os.IsNotExist(err) {
		log.Fatalf("load config: %v", err)
	}
	if cfg == nil {
		cfg = &Config{}
	}
	cfg.ServerURL = resolveServerURL(*serverURL, cfg.ServerURL)

	if cfg.DeviceID == "" || cfg.DeviceToken == "" {
		if *enrollToken == "" {
			*enrollToken = os.Getenv("PALLET_ENROLLMENT_TOKEN")
		}
		if *enrollToken == "" {
			log.Fatal("device not enrolled: pass -enroll TOKEN or set PALLET_ENROLLMENT_TOKEN")
		}
		if err := enroll(cfg, *enrollToken); err != nil {
			log.Fatalf("enrollment failed: %v", err)
		}
		if err := saveConfig(*configPath, cfg); err != nil {
			log.Fatalf("save config: %v", err)
		}
		log.Printf("enrolled device %s", cfg.DeviceID)
		if *enrollOnly {
			return
		}
	}

	if *enrollOnly {
		log.Fatal("device already enrolled")
	}
	agent := &Agent{cfg: cfg, configPath: *configPath, client: &http.Client{Timeout: 45 * time.Second}}
	agent.Run()
}

type Config struct {
	ServerURL   string `json:"server_url"`
	DeviceID    string `json:"device_id"`
	DeviceToken string `json:"device_token"`
	DeviceKey   string `json:"device_key"`
}

type Agent struct {
	cfg        *Config
	configPath string
	client     *http.Client
	locked     bool
}

func (a *Agent) Run() {
	log.Printf("pallet-agent %s starting for device %s @ %s", agentVersion, a.cfg.DeviceID, a.cfg.ServerURL)
	backoff := 5 * time.Second
	for {
		if err := a.tick(); err != nil {
			log.Printf("heartbeat error: %v (retry in %s)", err, backoff)
			time.Sleep(backoff)
			if backoff < 2*time.Minute {
				backoff *= 2
			}
			continue
		}
		backoff = 5 * time.Second
		time.Sleep(30 * time.Second)
	}
}

func (a *Agent) tick() error {
	telemetry, err := collectTelemetry()
	if err != nil {
		return err
	}
	var resp heartbeatResponse
	if err := a.api("POST", "/api/v1/device/heartbeat", telemetry, &resp); err != nil {
		return err
	}
	a.locked = resp.Locked
	if err := applyPolicy(resp.Policy); err != nil {
		log.Printf("policy apply warning: %v", err)
	}
	go maybeApplyUpdates(resp.Policy)
	for _, cmd := range resp.Commands {
		result, success := a.executeCommand(cmd)
		_ = a.api("POST", fmt.Sprintf("/api/v1/device/commands/%s/complete", cmd.ID), map[string]any{
			"success": success,
			"result":  result,
		}, nil)
	}
	if a.locked {
		ensureLocked()
	}
	return nil
}

type heartbeatResponse struct {
	Policy   Policy    `json:"policy"`
	Locked   bool      `json:"locked"`
	Commands []Command `json:"commands"`
}

type Command struct {
	ID      string         `json:"id"`
	Type    string         `json:"type"`
	Payload map[string]any `json:"payload"`
}

func (a *Agent) executeCommand(cmd Command) (map[string]any, bool) {
	log.Printf("executing command %s (%s)", cmd.ID, cmd.Type)
	switch cmd.Type {
	case "lock":
		a.locked = true
		ensureLocked()
		return map[string]any{"locked": true}, true
	case "unlock":
		a.locked = false
		unlockScreen()
		return map[string]any{"locked": false}, true
	case "reboot":
		go runCmd("systemctl", "reboot")
		return map[string]any{"scheduled": true}, true
	case "wipe":
		go wipeDevice()
		return map[string]any{"scheduled": true}, true
	case "logout":
		go runCmd("loginctl", "terminate-user", "pallet")
		return map[string]any{"scheduled": true}, true
	case "restart_shell":
		go runCmd("systemctl", "restart", "pallet-shell")
		return map[string]any{"scheduled": true}, true
	case "install_app":
		pkg, _ := cmd.Payload["package"].(string)
		if err := installAndroidApp(pkg); err != nil {
			return map[string]any{"error": err.Error()}, false
		}
		return map[string]any{"package": pkg}, true
	case "remove_app":
		pkg, _ := cmd.Payload["package"].(string)
		if err := removeAndroidApp(pkg); err != nil {
			return map[string]any{"error": err.Error()}, false
		}
		return map[string]any{"package": pkg}, true
	case "apply_policy":
		if p, ok := cmd.Payload["policy"]; ok {
			raw, _ := json.Marshal(p)
			var policy Policy
			_ = json.Unmarshal(raw, &policy)
			if err := applyPolicy(policy); err != nil {
				return map[string]any{"error": err.Error()}, false
			}
		}
		return map[string]any{"applied": true}, true
	case "check_updates":
		go maybeApplyUpdates(Policy{Updates: UpdatesPolicy{Enabled: true, Auto: true}})
		return map[string]any{"scheduled": true}, true
	default:
		return map[string]any{"error": "unknown_command"}, false
	}
}

func (a *Agent) api(method, path string, body any, out any) error {
	var reader io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reader = bytes.NewReader(raw)
	}
	req, err := http.NewRequest(method, a.cfg.ServerURL+path, reader)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+a.cfg.DeviceToken)
	req.Header.Set("X-Device-Key", a.cfg.DeviceKey)
	resp, err := a.client.Do(req)
	if err != nil {
		return wrapNetworkError(err)
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return fmt.Errorf("api %s %s: %s", method, path, string(data))
	}
	if out != nil && len(data) > 0 {
		return json.Unmarshal(data, out)
	}
	return nil
}

func enroll(cfg *Config, token string) error {
	if cfg.DeviceKey == "" {
		cfg.DeviceKey = uuidNew()
	}
	hostname, _ := os.Hostname()
	payload := map[string]string{
		"enrollment_token": token,
		"hostname":         hostname,
		"device_key":       cfg.DeviceKey,
	}
	raw, _ := json.Marshal(payload)
	resp, err := http.Post(cfg.ServerURL+"/api/v1/device/enroll", "application/json", bytes.NewReader(raw))
	if err != nil {
		return wrapNetworkError(err)
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return fmt.Errorf("enroll failed: %s", string(data))
	}
	var out struct {
		DeviceID    string `json:"device_id"`
		DeviceToken string `json:"device_token"`
	}
	if err := json.Unmarshal(data, &out); err != nil {
		return err
	}
	cfg.DeviceID = out.DeviceID
	cfg.DeviceToken = out.DeviceToken
	return nil
}

func loadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

func saveConfig(path string, cfg *Config) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	raw, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, raw, 0o600)
}

func wrapNetworkError(err error) error {
	if err == nil {
		return nil
	}
	msg := strings.ToLower(err.Error())
	switch {
	case strings.Contains(msg, "server misbehaving"),
		strings.Contains(msg, "no such host"),
		strings.Contains(msg, "name or service not known"),
		strings.Contains(msg, "network is unreachable"),
		strings.Contains(msg, "i/o timeout"),
		dnsIsDown(err):
		return fmt.Errorf("%w (no internet — connect WiFi: sudo pallet-connect-wifi \"SSID\" \"password\")", err)
	default:
		return err
	}
}

func dnsIsDown(err error) bool {
	var dnsErr *net.DNSError
	return errors.As(err, &dnsErr)
}

func resolveServerURL(flagURL, configURL string) string {
	if flagURL != "" {
		return strings.TrimRight(flagURL, "/")
	}
	if configURL != "" {
		return strings.TrimRight(configURL, "/")
	}
	if v := os.Getenv("PALLET_SERVER_URL"); v != "" {
		return strings.TrimRight(v, "/")
	}
	return "http://127.0.0.1:8787"
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func uuidNew() string {
	out, err := exec.Command("uuidgen").Output()
	if err != nil {
		return fmt.Sprintf("key-%d", time.Now().UnixNano())
	}
	return strings.TrimSpace(string(out))
}

func runCmd(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	return cmd.Run()
}
