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
            exit 1
            ;;
    esac

    case "$(uname -m)" in
        x86_64)
            ARCH="amd64"
            ;;
        arm64)
            ARCH="arm64"
            ;;
        aarch64)
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
    local expected_filename="${binary_name}-${OS}-${ARCH}"

    echo -e "${YELLOW}Downloading ${binary_name}...${NC}"

    # Get latest release info
    if ! curl -s "$REPO_URL" -o "${TEMP_DIR}/release.json"; then
        echo -e "${RED}Error: Failed to fetch release information${NC}"
        echo -e "${YELLOW}Note: No releases available yet.${NC}"
        exit 1
    fi

    # Parse release JSON to find download URL
    local download_url
    download_url=$(grep "browser_download_url" "${TEMP_DIR}/release.json" | grep "${expected_filename}.tar.gz" | cut -d'"' -f4 | head -1)

    if [ -z "$download_url" ]; then
        echo -e "${RED}Error: No binary found for ${OS}-${ARCH}${NC}"
        echo -e "${YELLOW}Available binaries:${NC}"
        grep -o "\"name\":\"[^\"]*\"" "${TEMP_DIR}/release.json" | cut -d'"' -f4 | grep -E "(linux|macos)" || echo "  None found"
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

    sudo tee /etc/systemd/system/the-grid.service > /dev/null << EOF
[Unit]
Description=The Grid - Proof of Network Launcher
After=network.target
StartLimitBurst=5
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=5
User=grid
Group=grid
ExecStart=${INSTALL_DIR}/grid-launcher
WorkingDirectory=/var/lib/the-grid
StandardOutput=journal
StandardError=journal
SyslogIdentifier=the-grid

[Install]
WantedBy=multi-user.target
EOF

    # Create user and directories
    if ! id grid &>/dev/null; then
        sudo useradd -r -s /bin/false grid
    fi

    sudo mkdir -p /var/lib/the-grid
    sudo chown grid:grid /var/lib/the-grid

    # Enable service
    sudo systemctl daemon-reload
    sudo systemctl enable the-grid

    echo -e "${GREEN}✓ Systemd service created${NC}"
    echo -e "${YELLOW}  Start with: sudo systemctl start the-grid${NC}"
    echo -e "${YELLOW}  Status: sudo systemctl status the-grid${NC}"
}

# Create launchd service (macOS)
create_launchd_service() {
    echo -e "${YELLOW}Creating launchd service...${NC}"

    sudo tee /Library/LaunchDaemons/grid.launcher.plist > /dev/null << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>grid.launcher</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/grid-launcher</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/usr/local/var/the-grid</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/usr/local/var/log/the-grid.log</string>
    <key>StandardErrorPath</key>
    <string>/usr/local/var/log/the-grid.error.log</string>
</dict>
</plist>
EOF

    # Create directories
    sudo mkdir -p /usr/local/var/the-grid
    sudo mkdir -p /usr/local/var/log

    # Load service
    sudo launchctl load /Library/LaunchDaemons/grid.launcher.plist

    echo -e "${GREEN}✓ Launchd service created${NC}"
    echo -e "${YELLOW}  Start with: sudo launchctl start grid.launcher${NC}"
    echo -e "${YELLOW}  Stop with: sudo launchctl stop grid.launcher${NC}"
}

# Main installation function
main() {
    echo -e "${YELLOW}This script will install The Grid blockchain launcher on your system.${NC}"
    echo ""

    # Check for required tools
    if ! command -v curl &> /dev/null; then
        echo -e "${RED}Error: curl is required but not installed${NC}"
        exit 1
    fi

    # Detect OS and architecture
    detect_os_arch

    # Install launcher (which will manage node updates)
    install_binary "grid-launcher"

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
    echo "Quick start:"
    echo "  grid-launcher --help"
    echo "  grid-launcher --install-only  # Download and install node without starting"
    echo ""
    echo "Documentation: https://github.com/X-Big-Tech/the-grid-releases"
    echo "Support: bryan@xbigtech.com"
}

# Run main function
main "$@"