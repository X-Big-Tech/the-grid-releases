# The Grid - Public Releases

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/X-Big-Tech/the-grid-releases)](https://github.com/X-Big-Tech/the-grid-releases/releases/latest)

This repository hosts the official releases for The Grid - Proof of Network blockchain.

## Installation

### Quick Install (Linux/macOS)

```bash
curl -sSf https://raw.githubusercontent.com/X-Big-Tech/the-grid-releases/main/install.sh | sh
```

### Manual Download

Download the latest release for your platform from the [releases page](https://github.com/X-Big-Tech/the-grid-releases/releases).

Available binaries:
- `grid-launcher-linux-amd64` - Linux x86_64
- `grid-launcher-linux-arm64` - Linux ARM64
- `grid-launcher-macos-amd64` - macOS Intel
- `grid-launcher-macos-arm64` - macOS Apple Silicon

## About The Grid

The Grid implements a revolutionary Network Position Value (NPV) consensus mechanism that validates nodes based on their unique position within internet topology rather than computational power or wealth.

## Features

- **NPV Consensus**: Geography and topology-aware validation
- **Auto-Updates**: Launcher automatically manages node updates
- **Multi-Platform**: Support for Linux and macOS
- **Easy Deployment**: Single-command installation

## Usage

After installation:

```bash
# Start the launcher (manages node updates automatically)
grid-launcher

# Check launcher options
grid-launcher --help

# Install node without starting service
grid-launcher --install-only
```

## System Requirements

- Linux (Ubuntu 20.04+, Debian 10+, RHEL 8+) or macOS 11+
- 2GB RAM minimum, 4GB recommended
- 10GB available disk space
- Stable internet connection

## Support

For issues or questions:
- Email: bryan@xbigtech.com
- Issues: [GitHub Issues](https://github.com/X-Big-Tech/the-grid-releases/issues)

## License

Apache 2.0 - See [LICENSE](LICENSE) for details.

---
*Copyright 2024 Bryan Campbell / X-Big-Tech*