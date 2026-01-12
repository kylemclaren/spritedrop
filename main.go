package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"syscall"
)

var version = "dev"

func main() {
	dir := flag.String("dir", ".", "directory to save received files")
	conflict := flag.String("conflict", "rename", "conflict resolution: skip, overwrite, rename")
	verbose := flag.Bool("verbose", false, "verbose output")
	showVersion := flag.Bool("version", false, "show version")
	flag.Parse()

	if *showVersion {
		fmt.Printf("spritedrop %s\n", version)
		os.Exit(0)
	}

	// Resolve to absolute path
	absDir, err := filepath.Abs(*dir)
	if err != nil {
		log.Fatalf("invalid directory: %v", err)
	}

	// Ensure directory exists
	if err := os.MkdirAll(absDir, 0755); err != nil {
		log.Fatalf("failed to create directory: %v", err)
	}

	fmt.Printf("spritedrop %s\n", version)
	fmt.Printf("Receiving files to: %s\n", absDir)

	// Handle graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigCh
		fmt.Println("\nShutting down...")
		os.Exit(0)
	}()

	// Build command args
	args := []string{"file", "get", "--loop", "--conflict=" + *conflict}
	if *verbose {
		args = append(args, "--verbose")
	}
	args = append(args, absDir)

	// Run tailscale file get --loop
	cmd := exec.Command("tailscale", args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		log.Fatalf("tailscale file get failed: %v", err)
	}
}
