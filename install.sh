#!/bin/bash

# The Grid Installation Script
# Author: Bryan Campbell <bryan@xbigtech.com>

set -e

echo "🌐 The Grid - Proof of Network Installation"
echo "=========================================="
echo ""

# Configuration - Using public releases repo
REPO_URL="https://api.github.com/repos/X-Big-Tech/the-grid-releases/releases/latest"
INSTALL_DIR="/usr/local/bin"
TEMP_DIR=$(mktemp -d)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect OS and architecture
detect_os_arch() {
    OS=""
    ARCH=""

    case "$(uname -s)" in
        Darwin)
            OS="macos"
            ;;
        Linux)
            OS="linux"
            ;;
        *)
            echo -e "${RED}Error: Unsupported operating system $(uname -s)${NC}"
            echo -e "${YELLOW}Windows users: Download from https://github.com/X-Big-Tech/the-grid-releases/releases${NC}"
            exit 1
            ;;
    esac

    case "$(uname -m)" in
        x86_64)
            ARCH="amd64"
            ;;
        arm64|aarch64)
            ARCH="arm64"
            ;;
        *)
            echo -e "${RED}Error: Unsupported architecture $(uname -m)${NC}"
            exit 1
            ;;
    esac

    echo -e "${GREEN}Detected: ${OS}-${ARCH}${NC}"
}

# Download and install binary
install_binary() {
    local binary_name="$1"
    local platform_suffix="${OS}-${ARCH}"

    echo -e "${YELLOW}Downloading ${binary_name}...${NC}"

    # Get latest release info
    if ! curl -s "$REPO_URL" -o "${TEMP_DIR}/release.json"; then
        echo -e "${RED}Error: Failed to fetch release information${NC}"
        exit 1
    fi

    # Find download URL matching pattern: grid-launcher-VERSION-linux-amd64.tar.gz
    local download_url
    download_url=$(grep "browser_download_url" "${TEMP_DIR}/release.json" | \
                   grep "${binary_name}-.*-${platform_suffix}.tar.gz" | \
                   cut -d'"' -f4 | head -1)

    if [ -z "$download_url" ]; then
        echo -e "${RED}Error: No binary found for ${platform_suffix}${NC}"
        echo -e "${YELLOW}Available binaries:${NC}"
        grep -o '"name":"[^"]*"' "${TEMP_DIR}/release.json" | cut -d'"' -f4 | grep -E "\.tar\.gz$" || echo "  None found"
        exit 1
    fi

    # Download binary archive
    echo "  Downloading from: ${download_url}"
    if ! curl -L "$download_url" -o "${TEMP_DIR}/${binary_name}.tar.gz"; then
        echo -e "${RED}Error: Failed to download ${binary_name}${NC}"
        exit 1
    fi

    # Extract binary from archive
    echo "  Extracting ${binary_name}..."
    if ! tar -xzf "${TEMP_DIR}/${binary_name}.tar.gz" -C "${TEMP_DIR}/"; then
        echo -e "${RED}Error: Failed to extract ${binary_name}${NC}"
        exit 1
    fi

    # Make executable
    chmod +x "${TEMP_DIR}/${binary_name}"

    echo "  Installing to ${INSTALL_DIR}/${binary_name}"
    if ! sudo cp "${TEMP_DIR}/${binary_name}" "${INSTALL_DIR}/${binary_name}"; then
        echo -e "${RED}Error: Failed to install ${binary_name}${NC}"
        echo "  Try running with sudo or check permissions"
        exit 1
    fi

    echo -e "${GREEN}✓ ${binary_name} installed successfully${NC}"
}

# Create systemd service (Linux)
create_systemd_service() {
    echo -e "${YELLOW}Creating systemd service...${NC}"

    sudo tee /etc/systemd/system/grid-node.service > /dev/null << SVCEOF
[Unit]
Description=The Grid - Proof of Network Node
After=network.target
StartLimitBurst=5
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=5
User=grid
Group=grid
ExecStart=${INSTALL_DIR}/grid-node
WorkingDirectory=/var/lib/the-grid
StandardOutput=journal
StandardError=journal
SyslogIdentifier=grid-node

[Install]
WantedBy=multi-user.target
SVCEOF

    # Create user and directories
    if ! id grid &>/dev/null; then
        sudo useradd -r -s /bin/false grid
    fi

    sudo mkdir -p /var/lib/the-grid
    sudo chown grid:grid /var/lib/the-grid

    # Enable service
    sudo systemctl daemon-reload
    sudo systemctl enable grid-node

    echo -e "${GREEN}✓ Systemd service created${NC}"
    echo -e "${YELLOW}  Start with: sudo systemctl start grid-node${NC}"
    echo -e "${YELLOW}  Status: sudo systemctl status grid-node${NC}"
}

# Create launchd service (macOS)
create_launchd_service() {
    echo -e "${YELLOW}Creating launchd service...${NC}"

    sudo tee /Library/LaunchDaemons/com.xbigtech.grid-node.plist > /dev/null << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.xbigtech.grid-node</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/grid-node</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/usr/local/var/the-grid</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/usr/local/var/log/grid-node.log</string>
    <key>StandardErrorPath</key>
    <string>/usr/local/var/log/grid-node.error.log</string>
</dict>
</plist>
PLISTEOF

    # Create directories
    sudo mkdir -p /usr/local/var/the-grid
    sudo mkdir -p /usr/local/var/log

    echo -e "${GREEN}✓ Launchd service created${NC}"
    echo -e "${YELLOW}  Load with: sudo launchctl load /Library/LaunchDaemons/com.xbigtech.grid-node.plist${NC}"
    echo -e "${YELLOW}  Start with: sudo launchctl start com.xbigtech.grid-node${NC}"
}

# Main installation function
main() {
    echo -e "${YELLOW}This script will install The Grid blockchain on your system.${NC}"
    echo ""

    # Check for required tools
    if ! command -v curl &> /dev/null; then
        echo -e "${RED}Error: curl is required but not installed${NC}"
        exit 1
    fi

    # Detect OS and architecture
    detect_os_arch

    # Install both binaries
    install_binary "grid-launcher"
    install_binary "grid-node"

    # Create system service
    case "$OS" in
        linux)
            read -p "Create systemd service? (y/n) " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                create_systemd_service
            fi
            ;;
        macos)
            read -p "Create launchd service? (y/n) " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                create_launchd_service
            fi
            ;;
    esac

    # Cleanup
    rm -rf "$TEMP_DIR"

    echo ""
    echo -e "${GREEN}🎉 The Grid installation complete!${NC}"
    echo ""
    echo "Installed binaries:"
    echo "  grid-launcher - Manages node updates automatically"
    echo "  grid-node     - The blockchain node"
    echo ""
    echo "Quick start:"
    echo "  grid-node --help"
    echo "  grid-node --version"
    echo ""
    echo "Documentation: https://github.com/X-Big-Tech/the-grid-releases"
}

# Run main function
main "$@"
