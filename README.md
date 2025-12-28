# The Grid - Public Releases

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/X-Big-Tech/the-grid-releases)](https://github.com/X-Big-Tech/the-grid-releases/releases/latest)

Official releases for **The Grid** - a Proof of Network (PoN) blockchain.

## Quick Install

### Linux / macOS

```bash
curl -sSf https://raw.githubusercontent.com/X-Big-Tech/the-grid-releases/main/install.sh | sh
```

### Windows

Download from the [releases page](https://github.com/X-Big-Tech/the-grid-releases/releases) and extract.

## Available Binaries

| Platform | Launcher | Node |
|----------|----------|------|
| Linux x86_64 | `grid-launcher-*-linux-amd64.tar.gz` | `grid-node-*-linux-amd64.tar.gz` |
| Linux ARM64 | `grid-launcher-*-linux-arm64.tar.gz` | `grid-node-*-linux-arm64.tar.gz` |
| macOS Intel | `grid-launcher-*-macos-amd64.tar.gz` | `grid-node-*-macos-amd64.tar.gz` |
| macOS ARM | `grid-launcher-*-macos-arm64.tar.gz` | `grid-node-*-macos-arm64.tar.gz` |
| Windows x64 | `grid-launcher-*-windows-amd64.zip` | `grid-node-*-windows-amd64.zip` |

## Usage

### Grid Launcher (Recommended)

The launcher automatically manages node installation and updates:

```bash
# Start the launcher
grid-launcher

# Install without starting
grid-launcher --install-only

# Check options
grid-launcher --help
```

### Grid Node (Direct)

Run the node directly for more control:

```bash
# Start the node
grid-node

# With custom data directory
grid-node --data-dir /path/to/data

# Check version
grid-node --version
```

## Verification

Each release includes `SHA256SUMS` for verification:

```bash
# Linux/macOS
sha256sum -c SHA256SUMS

# Or verify a single file
sha256sum grid-node-*-linux-amd64.tar.gz
```

## System Requirements

- **OS**: Linux (Ubuntu 20.04+, Debian 10+, RHEL 8+), macOS 11+, or Windows 10+
- **RAM**: 2GB minimum, 4GB recommended
- **Disk**: 10GB available space
- **Network**: Stable internet connection, UDP port 8333 for P2P

## About The Grid

The Grid implements **Network Position Value (NPV)** consensus - validating nodes based on their unique position within internet topology rather than computational power (PoW) or wealth (PoS).

## Support

- Issues: [GitHub Issues](https://github.com/X-Big-Tech/the-grid-releases/issues)
- Email: bryan@xbigtech.com

## License

Apache 2.0 - See [LICENSE](LICENSE)

---
*Copyright 2024-2025 Bryan Campbell / X-Big-Tech*
