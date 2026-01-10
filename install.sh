#!/bin/bash
set -e

# spritedrop installer
# Installs Tailscale (if needed) and spritedrop for persistent file receiving

REPO="kylemclaren/spritedrop"
INSTALL_DIR="/usr/local/bin"
RECV_DIR="${SPRITEDROP_DIR:-$HOME/incoming}"
TS_HOSTNAME="${SPRITEDROP_HOSTNAME:-}"

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Status indicators
CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
ARROW="${BLUE}→${NC}"

info()    { echo -e "  ${CHECK} $1"; }
warn()    { echo -e "  ${YELLOW}!${NC} $1"; }
error()   { echo -e "  ${CROSS} $1"; exit 1; }
step()    { echo -e "\n${BOLD}$1${NC}"; }
substep() { echo -e "  ${ARROW} $1"; }

# Spinner for long operations
spin() {
    local pid=$1
    local msg=$2
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while kill -0 "$pid" 2>/dev/null; do
        for (( i=0; i<${#spinstr}; i++ )); do
            printf "\r  ${BLUE}%s${NC} %s" "${spinstr:$i:1}" "$msg"
            sleep 0.1
        done
    done
    printf "\r"
}

# Run command silently with spinner
run_silent() {
    local msg="$1"
    shift
    "$@" > /dev/null 2>&1 &
    local pid=$!
    spin $pid "$msg"
    wait $pid
    return $?
}

# Detect OS and architecture
detect_platform() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) error "Unsupported architecture: $ARCH" ;;
    esac

    case "$OS" in
        linux|darwin) ;;
        *) error "Unsupported OS: $OS" ;;
    esac

    PLATFORM="${OS}-${ARCH}"
}

# Check if running in Sprite environment
is_sprite() {
    [ -S "/.sprite/api.sock" ]
}

# Install dependencies
install_deps() {
    if ! command -v jq &> /dev/null; then
        substep "Installing jq..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update -qq > /dev/null 2>&1
            sudo apt-get install -y -qq jq > /dev/null 2>&1
        elif command -v yum &> /dev/null; then
            sudo yum install -y -q jq > /dev/null 2>&1
        elif command -v brew &> /dev/null; then
            brew install jq > /dev/null 2>&1
        fi
    fi
}

# Install Tailscale if not present
install_tailscale() {
    if command -v tailscale &> /dev/null; then
        info "Tailscale $(tailscale version | head -1) installed"
        return 0
    fi

    substep "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh 2>/dev/null | sh > /dev/null 2>&1
    info "Tailscale installed"
}

# Start tailscaled daemon
start_tailscaled() {
    if pgrep -x tailscaled > /dev/null; then
        info "tailscaled running"
        return 0
    fi

    if is_sprite; then
        substep "Creating tailscaled service..."
        sprite-env services delete tailscaled > /dev/null 2>&1 || true
        sleep 1
        sprite-env services create tailscaled \
            --cmd /usr/sbin/tailscaled \
            --args "--state=/var/lib/tailscale/tailscaled.state,--socket=/var/run/tailscale/tailscaled.sock" \
            --no-stream > /dev/null 2>&1

        # Wait for tailscaled
        for i in {1..10}; do
            if pgrep -x tailscaled > /dev/null; then break; fi
            sleep 1
        done
        info "tailscaled service created"
    elif command -v systemctl &> /dev/null; then
        substep "Starting tailscaled..."
        sudo systemctl enable --now tailscaled > /dev/null 2>&1
        info "tailscaled started"
    else
        substep "Starting tailscaled..."
        sudo tailscaled --state=/var/lib/tailscale/tailscaled.state > /dev/null 2>&1 &
        sleep 2
        info "tailscaled started"
    fi
}

# Prompt for hostname
prompt_hostname() {
    # Skip if already set via env var
    [ -n "$TS_HOSTNAME" ] && return 0

    # Skip if already authenticated
    tailscale status > /dev/null 2>&1 && return 0

    echo ""
    echo -e "  ${DIM}Enter a hostname for this device in your tailnet${NC}"
    echo -e "  ${DIM}(e.g., sprite-myproject, sprite-api)${NC}"
    echo ""
    read -p "  Hostname [Enter to auto-generate]: " input_hostname

    if [ -n "$input_hostname" ]; then
        TS_HOSTNAME="$input_hostname"
    fi
}

# Authenticate Tailscale
auth_tailscale() {
    if tailscale status > /dev/null 2>&1; then
        local current_name=$(tailscale status --json 2>/dev/null | jq -r '.Self.HostName // empty' 2>/dev/null)
        if [ -n "$TS_HOSTNAME" ] && [ "$current_name" != "$TS_HOSTNAME" ]; then
            substep "Updating hostname to $TS_HOSTNAME..."
            sudo tailscale set --hostname="$TS_HOSTNAME" > /dev/null 2>&1
        fi
        info "Tailscale authenticated as ${BOLD}${current_name:-$(hostname)}${NC}"
        return 0
    fi

    echo ""
    echo -e "  ${YELLOW}▶${NC} ${BOLD}Authenticate in your browser${NC}"
    echo ""

    if [ -n "$TS_HOSTNAME" ]; then
        sudo tailscale up --hostname="$TS_HOSTNAME" 2>&1 | grep -E "https://|Success" || true
    else
        sudo tailscale up 2>&1 | grep -E "https://|Success" || true
    fi

    local final_name=$(tailscale status --json 2>/dev/null | jq -r '.Self.HostName // empty' 2>/dev/null)
    echo ""
    info "Authenticated as ${BOLD}${final_name:-$(hostname)}${NC}"
}

# Set Tailscale operator
set_operator() {
    sudo tailscale set --operator="$USER" > /dev/null 2>&1 || true
}

# Get latest release version
get_latest_version() {
    curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | \
        grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

# Download and install spritedrop
install_spritedrop() {
    VERSION=$(get_latest_version)
    [ -z "$VERSION" ] && error "Failed to get latest version"

    substep "Downloading spritedrop ${VERSION}..."
    curl -fsSL "https://github.com/${REPO}/releases/download/${VERSION}/spritedrop-${PLATFORM}" \
        -o /tmp/spritedrop 2>/dev/null || error "Failed to download"

    chmod +x /tmp/spritedrop
    sudo mv /tmp/spritedrop "$INSTALL_DIR/spritedrop"
    info "Installed spritedrop ${VERSION}"
}

# Create receiving directory
create_recv_dir() {
    mkdir -p "$RECV_DIR"
}

# Set up as a service
setup_service() {
    if is_sprite; then
        substep "Creating spritedrop service..."
        sprite-env services delete spritedrop > /dev/null 2>&1 || true
        sleep 1
        sprite-env services create spritedrop \
            --cmd "$INSTALL_DIR/spritedrop" \
            --args "--dir=$RECV_DIR" \
            --needs tailscaled \
            --no-stream > /dev/null 2>&1
        info "spritedrop service running"
    elif command -v systemctl &> /dev/null; then
        substep "Creating systemd service..."
        sudo tee /etc/systemd/system/spritedrop.service > /dev/null <<EOF
[Unit]
Description=Spritedrop file receiver
After=tailscaled.service
Requires=tailscaled.service

[Service]
Type=simple
User=$USER
ExecStart=$INSTALL_DIR/spritedrop --dir=$RECV_DIR
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload > /dev/null 2>&1
        sudo systemctl enable --now spritedrop > /dev/null 2>&1
        info "systemd service running"
    else
        warn "No service manager - run manually:"
        echo "    $INSTALL_DIR/spritedrop --dir=$RECV_DIR"
    fi
}

# Main
main() {
    echo ""
    echo -e "${BOLD}  spritedrop${NC} ${DIM}installer${NC}"
    echo ""

    step "Setting up environment"
    detect_platform
    info "Platform: ${PLATFORM}"
    install_deps

    step "Installing Tailscale"
    install_tailscale
    start_tailscaled

    step "Configuring Tailscale"
    prompt_hostname
    auth_tailscale
    set_operator

    step "Installing spritedrop"
    install_spritedrop
    create_recv_dir
    setup_service

    # Get final hostname for display
    local device_name=$(tailscale status --json 2>/dev/null | jq -r '.Self.HostName // empty' 2>/dev/null)
    device_name="${device_name:-$(hostname)}"

    echo ""
    echo -e "${BOLD}  Done!${NC} Send files with:"
    echo ""
    echo -e "    ${DIM}tailscale file cp${NC} ${BOLD}<file>${NC} ${DIM}${device_name}:${NC}"
    echo ""
    echo -e "  ${DIM}Files saved to:${NC} ${RECV_DIR}"
    echo ""
}

main "$@"
