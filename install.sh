#!/bin/bash
set -e

# spritedrop installer
# Installs Tailscale (if needed) and spritedrop for persistent file receiving

REPO="kylemclaren/spritedrop"
INSTALL_DIR="/usr/local/bin"
RECV_DIR="${SPRITEDROP_DIR:-$HOME/incoming}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

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
    info "Detected platform: $PLATFORM"
}

# Check if running in Sprite environment
is_sprite() {
    [ -S "/.sprite/api.sock" ]
}

# Install dependencies
install_deps() {
    if ! command -v jq &> /dev/null; then
        info "Installing jq..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y -qq jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y -q jq
        elif command -v brew &> /dev/null; then
            brew install jq
        else
            warn "Could not install jq automatically"
        fi
    fi
}

# Install Tailscale if not present
install_tailscale() {
    if command -v tailscale &> /dev/null; then
        info "Tailscale already installed: $(tailscale version | head -1)"
        return 0
    fi

    info "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    info "Tailscale installed successfully"
}

# Start tailscaled daemon
start_tailscaled() {
    if pgrep -x tailscaled > /dev/null; then
        info "tailscaled already running"
        return 0
    fi

    if is_sprite; then
        info "Sprite environment detected..."
        # Remove existing service if any (suppress all output)
        sprite-env services delete tailscaled > /dev/null 2>&1 || true
        sleep 1
        info "Creating tailscaled service..."
        sprite-env services create tailscaled \
            --cmd /usr/sbin/tailscaled \
            --args "--state=/var/lib/tailscale/tailscaled.state,--socket=/var/run/tailscale/tailscaled.sock" \
            --no-stream
        # Wait for tailscaled to be ready
        info "Waiting for tailscaled to start..."
        for i in {1..10}; do
            if pgrep -x tailscaled > /dev/null; then
                break
            fi
            sleep 1
        done
    elif command -v systemctl &> /dev/null; then
        info "Starting tailscaled via systemd..."
        sudo systemctl enable --now tailscaled
    else
        info "Starting tailscaled manually..."
        sudo tailscaled --state=/var/lib/tailscale/tailscaled.state &
        sleep 2
    fi
}

# Authenticate Tailscale
auth_tailscale() {
    if tailscale status &> /dev/null 2>&1; then
        info "Tailscale already authenticated"
        return 0
    fi

    info "Authenticating Tailscale..."
    echo ""
    warn "Please authenticate in your browser when prompted"
    echo ""
    sudo tailscale up
    info "Tailscale authenticated successfully"
}

# Set Tailscale operator for non-root file access
set_operator() {
    info "Setting Tailscale operator to current user..."
    sudo tailscale set --operator="$USER" 2>/dev/null || true
}

# Get latest release version
get_latest_version() {
    curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | \
        grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

# Download and install spritedrop
install_taildrop_recv() {
    VERSION=$(get_latest_version)
    if [ -z "$VERSION" ]; then
        error "Failed to get latest version. Check https://github.com/${REPO}/releases"
    fi

    info "Installing spritedrop $VERSION..."

    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/spritedrop-${PLATFORM}"

    curl -fsSL "$DOWNLOAD_URL" -o /tmp/spritedrop || error "Failed to download binary"
    chmod +x /tmp/spritedrop
    sudo mv /tmp/spritedrop "$INSTALL_DIR/spritedrop"

    info "Installed to $INSTALL_DIR/spritedrop"
}

# Create receiving directory
create_recv_dir() {
    mkdir -p "$RECV_DIR"
    info "Files will be saved to: $RECV_DIR"
}

# Set up as a service
setup_service() {
    if is_sprite; then
        info "Setting up spritedrop as Sprite service..."
        # Remove existing service if any (suppress all output)
        sprite-env services delete spritedrop > /dev/null 2>&1 || true
        sleep 1
        sprite-env services create spritedrop \
            --cmd "$INSTALL_DIR/spritedrop" \
            --args "--dir=$RECV_DIR" \
            --needs tailscaled \
            --no-stream
        info "spritedrop service created"
    elif command -v systemctl &> /dev/null; then
        info "Setting up systemd service..."
        sudo tee /etc/systemd/system/spritedrop.service > /dev/null <<EOF
[Unit]
Description=Taildrop file receiver
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
        sudo systemctl daemon-reload
        sudo systemctl enable --now spritedrop
        info "systemd service created and started"
    else
        warn "No service manager detected. Run manually:"
        echo "  $INSTALL_DIR/spritedrop --dir=$RECV_DIR"
    fi
}

# Main installation
main() {
    echo ""
    echo "=================================="
    echo "  spritedrop installer"
    echo "=================================="
    echo ""

    detect_platform
    install_deps
    install_tailscale
    start_tailscaled
    auth_tailscale
    set_operator
    install_taildrop_recv
    create_recv_dir
    setup_service

    echo ""
    echo "=================================="
    info "Installation complete!"
    echo "=================================="
    echo ""
    echo "Send files from another device:"
    echo "  tailscale file cp <file> $(hostname):"
    echo ""
    echo "Files will be saved to: $RECV_DIR"
    echo ""
}

main "$@"
