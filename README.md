![Screen Recording 2026-01-12 at 12 14 51](https://github.com/user-attachments/assets/3436304a-a544-4be9-8435-0df231ede18d)

# spritedrop

A persistent [Taildrop](https://tailscale.com/kb/1106/taildrop) file receiver for [Sprites](https://sprites.dev) environments.

## Features

- Continuously listens for incoming Taildrop files
- Automatically restarts after receiving files
- Works with systemd or Sprite service managers
- Installs Tailscale if not already present
- Send files between Sprites or any device on your tailnet

## Recommended Setup

For multiple Sprites, create a dedicated tailnet using a new GitHub organization. This keeps your Sprites isolated and organized:

1. Create a new GitHub org (e.g., `myproject-sprites`)
2. Sign up for [Tailscale](https://tailscale.com) using that org
3. Install spritedrop on each Sprite - they'll automatically join the same tailnet

## Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kylemclaren/spritedrop/main/install.sh)
```

The installer will:
1. Install Tailscale (if not present)
2. Prompt for a device hostname (or generate a unique one)
3. Authenticate Tailscale
4. Download the latest spritedrop binary
5. Set up spritedrop as a persistent service

## Usage

Once installed, send files from any device on your tailnet:

```bash
# From macOS/Linux CLI
tailscale file cp myfile.txt <hostname>:

# From macOS Finder
Right-click file → Share → Taildrop → select your server
```

Files are saved to `~/incoming` by default.

### Claude Code Skill

On Sprite environments with Claude Code, the installer adds a `/spritedrop` skill:

```
/spritedrop              # Check incoming files and status
/spritedrop send <file> <device>   # Send a file
```

### Configuration

Set environment variables before the install command:

```bash
# Custom Tailscale hostname (skip interactive prompt)
SPRITEDROP_HOSTNAME=sprite-myproject bash <(curl -fsSL ...)

# Custom file directory
SPRITEDROP_DIR=/data/incoming bash <(curl -fsSL ...)

# Both options
SPRITEDROP_HOSTNAME=sprite-api SPRITEDROP_DIR=/data/incoming bash <(curl -fsSL ...)
```

## Manual Installation

Download the binary for your platform from [Releases](https://github.com/kylemclaren/spritedrop/releases):

```bash
# Linux amd64
curl -fsSL https://github.com/kylemclaren/spritedrop/releases/latest/download/spritedrop-linux-amd64 -o spritedrop
chmod +x spritedrop
./spritedrop --dir=/path/to/incoming
```

## Running as a Service

### Sprite Environment

```bash
sprite-env services create spritedrop \
  --cmd /usr/local/bin/spritedrop \
  --args "--dir=$HOME/incoming" \
  --needs tailscaled
```

### systemd

```bash
sudo tee /etc/systemd/system/spritedrop.service <<EOF
[Unit]
Description=Spritedrop file receiver
After=tailscaled.service

[Service]
Type=simple
User=$USER
ExecStart=/usr/local/bin/spritedrop --dir=$HOME/incoming
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable --now spritedrop
```

## Building from Source

```bash
git clone https://github.com/kylemclaren/spritedrop.git
cd spritedrop
go build -o spritedrop .
```

## License

MIT
