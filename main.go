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

func main() {
	dir := flag.String("dir", ".", "directory to save received files")
	flag.Parse()

	// Resolve to absolute path
	absDir, err := filepath.Abs(*dir)
	if err != nil {
		log.Fatalf("invalid directory: %v", err)
	}

	// Ensure directory exists
	if err := os.MkdirAll(absDir, 0755); err != nil {
		log.Fatalf("failed to create directory: %v", err)
	}

	fmt.Printf("Listening for Taildrop files in %s\n", absDir)
	fmt.Println("Press Ctrl+C to stop")

	// Handle graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigCh
		fmt.Println("\nShutting down...")
		os.Exit(0)
	}()

	// Continuously listen for files
	for {
		cmd := exec.Command("tailscale", "file", "get", "--wait", absDir)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr

		if err := cmd.Run(); err != nil {
			if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 1 {
				// Likely no files, just continue
				continue
			}
			log.Printf("error: %v", err)
		}

		// List what we received
		entries, _ := os.ReadDir(absDir)
		fmt.Printf("Files in %s:\n", absDir)
		for _, e := range entries {
			if !e.IsDir() {
				info, _ := e.Info()
				fmt.Printf("  %s (%d bytes)\n", e.Name(), info.Size())
			}
		}
		fmt.Println("Waiting for more files...")
	}
}
