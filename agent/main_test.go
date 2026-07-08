package main

import (
	"testing"
)

func TestResolveServerURL(t *testing.T) {
	t.Setenv("PALLET_SERVER_URL", "https://env.example.com")

	tests := []struct {
		name     string
		flagURL  string
		configURL string
		want     string
	}{
		{
			name:     "cli flag wins",
			flagURL:  "https://cli.example.com/",
			configURL: "https://config.example.com",
			want:     "https://cli.example.com",
		},
		{
			name:     "config used when flag empty",
			flagURL:  "",
			configURL: "https://config.example.com/",
			want:     "https://config.example.com",
		},
		{
			name:     "env fallback when config empty",
			flagURL:  "",
			configURL: "",
			want:     "https://env.example.com",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := resolveServerURL(tt.flagURL, tt.configURL); got != tt.want {
				t.Fatalf("resolveServerURL(%q, %q) = %q, want %q", tt.flagURL, tt.configURL, got, tt.want)
			}
		})
	}
}

func TestResolveServerURLDevDefault(t *testing.T) {
	t.Setenv("PALLET_SERVER_URL", "")
	if got := resolveServerURL("", ""); got != "http://127.0.0.1:8787" {
		t.Fatalf("resolveServerURL() = %q, want dev default", got)
	}
}
