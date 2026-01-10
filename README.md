# spritedrop

A persistent [Taildrop](https://tailscale.com/kb/1106/taildrop) file receiver for Linux servers and [Sprite](https://sprites.dev) environments.

## Features

- Continuously listens for incoming Taildrop files
- Automatically restarts after receiving files
- Works with systemd or Sprite service managers
- Installs Tailscale if not already present

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/kylemclaren/spritedrop/main/install.sh | bash
```

The installer will:
1. Install Tailscale (if not present)
2. Start and authenticate Tailscale
3. Download the latest spritedrop binary
4. Set up spritedrop as a persistent service

## Usage

Once installed, send files from any device on your tailnet:

```bash
# From macOS/Linux CLI
tailscale file cp myfile.txt <hostname>:

# From macOS Finder
Right-click file → Share → Taildrop → select your server
```

Files are saved to `~/incoming` by default. Override with:

```bash
SPRITEDROP_DIR=/path/to/dir curl -fsSL ... | bash
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
