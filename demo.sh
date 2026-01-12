#!/bin/bash
# Demo script for asciinema recording
# Run with: asciinema rec -c "./demo.sh" demo.cast

set -e

# Typing effect
type_cmd() {
    echo -ne "\033[32m$\033[0m "
    for ((i=0; i<${#1}; i++)); do
        echo -n "${1:$i:1}"
        sleep 0.03
    done
    echo
    sleep 0.3
}

run_cmd() {
    type_cmd "$1"
    eval "$1"
    sleep 1
}

clear
echo -e "\033[1m  spritedrop demo\033[0m"
echo -e "  \033[2mPersistent Taildrop file receiver\033[0m"
echo
sleep 2

# Show install command
echo -e "\033[1m# Install spritedrop\033[0m"
sleep 1
type_cmd 'bash <(curl -fsSL https://raw.githubusercontent.com/kylemclaren/spritedrop/main/install.sh)'
echo
echo -e "  \033[2m(install output would appear here)\033[0m"
sleep 2

# Show status
echo
echo -e "\033[1m# Check service status\033[0m"
sleep 1
run_cmd "sprite-env services list | jq -r '.[].name'"

# Check incoming
echo
echo -e "\033[1m# Check incoming files\033[0m"
sleep 1
run_cmd "ls -la ~/incoming/"

# Show tailscale devices
echo
echo -e "\033[1m# List tailnet devices\033[0m"
sleep 1
run_cmd "tailscale status | head -10"

# Send a file
echo
echo -e "\033[1m# Send a file to another device\033[0m"
sleep 1
type_cmd "echo 'Hello from spritedrop!' > /tmp/hello.txt"
echo 'Hello from spritedrop!' > /tmp/hello.txt
sleep 0.5
run_cmd "tailscale file cp /tmp/hello.txt fly-m2:"
echo -e "  \033[32m✓\033[0m File sent!"

echo
echo -e "\033[1m  Done!\033[0m Learn more: https://github.com/kylemclaren/spritedrop"
echo
sleep 3
