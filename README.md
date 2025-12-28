# The Grid - Public Releases

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/X-Big-Tech/the-grid-releases)](https://github.com/X-Big-Tech/the-grid-releases/releases/latest)

Official releases for **The Grid** - a Proof of Network (PoN) blockchain that validates nodes based on network topology rather than computational power or wealth.

## Quick Start

### Linux / macOS

```bash
curl -sSf https://raw.githubusercontent.com/X-Big-Tech/the-grid-releases/main/install.sh | sh
```

### Windows

1. Download the latest `.zip` files from [Releases](https://github.com/X-Big-Tech/the-grid-releases/releases)
2. Extract to a folder (e.g., `C:\grid\`)
3. Add to PATH or run directly from the folder

## Available Binaries

| Platform | Launcher | Node |
|----------|----------|------|
| Linux x86_64 | `grid-launcher-*-linux-amd64.tar.gz` | `grid-node-*-linux-amd64.tar.gz` |
| Linux ARM64 | `grid-launcher-*-linux-arm64.tar.gz` | `grid-node-*-linux-arm64.tar.gz` |
| macOS Intel | `grid-launcher-*-macos-amd64.tar.gz` | `grid-node-*-macos-amd64.tar.gz` |
| macOS ARM | `grid-launcher-*-macos-arm64.tar.gz` | `grid-node-*-macos-arm64.tar.gz` |
| Windows x64 | `grid-launcher-*-windows-amd64.zip` | `grid-node-*-windows-amd64.zip` |

---

## Grid Node

The core blockchain node. Run this to participate in the network.

### Basic Usage

```bash
# Start node with defaults
grid-node

# Check version
grid-node --version

# Show help
grid-node --help
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `--data-dir` | `~/.grid-node` | Data directory for blockchain state |
| `--listen-port` | `8333` | UDP port for P2P connections |
| `--api-port` | `8080` | HTTP API port |
| `--node-type` | `validator` | Node type: `genesis` or `validator` |
| `--node-name` | `node` | Human-readable name for logs |
| `--log-level` | `info` | Log verbosity: `error`, `warn`, `info`, `debug`, `trace` |
| `--config-file` | - | Path to JSON configuration file |

### Node Key Management

```bash
# Auto-generate key (stored in ~/.grid-node/node_key.json)
grid-node

# Use specific key file
grid-node --node-key-file /path/to/key.json

# Provide key directly (64 hex chars)
grid-node --node-key <hex-encoded-ed25519-secret>

# Reset and generate new key
grid-node --reset-key
```

### Example: Running a Validator

```bash
grid-node \
  --data-dir /var/lib/grid \
  --listen-port 8333 \
  --api-port 8080 \
  --node-name my-validator \
  --log-level info
```

### Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8333 | UDP | P2P QUIC transport (required) |
| 8080 | TCP | HTTP API (optional) |

Ensure UDP port 8333 is open in your firewall for P2P connectivity.

---

## Grid Launcher

Manages node installation and updates automatically.

### Usage

```bash
# Install and start node
grid-launcher

# Install only (don't start service)
grid-launcher --install-only

# Check for updates
grid-launcher --update

# Run as daemon
grid-launcher --daemon

# Use custom config
grid-launcher --config /path/to/config.json
```

---

## Verification

Each release includes `SHA256SUMS` for integrity verification:

```bash
# Linux/macOS - verify all files
cd ~/Downloads
sha256sum -c SHA256SUMS

# Verify single file
sha256sum grid-node-*-linux-amd64.tar.gz
```

---

## System Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| **OS** | Linux (Ubuntu 20.04+), macOS 11+, Windows 10+ | Ubuntu 22.04 LTS |
| **CPU** | 2 cores | 4+ cores |
| **RAM** | 2 GB | 4+ GB |
| **Disk** | 10 GB | 50+ GB SSD |
| **Network** | 10 Mbps | 100+ Mbps |

---

## Running as a Service

### Linux (systemd)

```bash
# Create service file
sudo tee /etc/systemd/system/grid-node.service << 'SVC'
[Unit]
Description=The Grid Node
After=network.target

[Service]
Type=simple
User=grid
ExecStart=/usr/local/bin/grid-node --data-dir /var/lib/grid
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVC

# Enable and start
sudo useradd -r -s /bin/false grid
sudo mkdir -p /var/lib/grid
sudo chown grid:grid /var/lib/grid
sudo systemctl daemon-reload
sudo systemctl enable grid-node
sudo systemctl start grid-node

# Check status
sudo systemctl status grid-node
journalctl -u grid-node -f
```

### macOS (launchd)

```bash
# Create plist
sudo tee /Library/LaunchDaemons/com.xbigtech.grid-node.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.xbigtech.grid-node</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/grid-node</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLIST

# Load service
sudo launchctl load /Library/LaunchDaemons/com.xbigtech.grid-node.plist
```

### Windows (NSSM)

1. Download [NSSM](https://nssm.cc/download)
2. Install as service:
```powershell
nssm install GridNode C:\grid\grid-node.exe
nssm set GridNode AppDirectory C:\grid
nssm start GridNode
```

---

## Troubleshooting

### Node won't start

```bash
# Check if port is in use
lsof -i :8333
netstat -tuln | grep 8333

# Check logs
grid-node --log-level debug
```

### Connection issues

- Ensure UDP port 8333 is open (firewall, router)
- Check internet connectivity
- Verify you're using the correct network (mainnet/testnet)

### Permission denied

```bash
# Linux/macOS - fix permissions
sudo chown -R $USER ~/.grid-node
chmod 700 ~/.grid-node
```

---

## Support

- **Issues**: [GitHub Issues](https://github.com/X-Big-Tech/the-grid-releases/issues)
- **Email**: bryan@xbigtech.com

## License

Apache 2.0 - See [LICENSE](LICENSE)

---

*Copyright 2024-2025 Bryan Campbell / X-Big-Tech*
