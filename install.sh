#!/bin/sh

# The Grid Installation Script
# Author: Bryan Campbell <bryan@xbigtech.com>
#
# Installs the `grid` CLI and `grid-launcher` from the latest GitHub
# release, verifies every download against the release SHA256SUMS, then
# runs `grid-launcher install` to fetch the matching grid-node binary.
#
# Usage:
#   curl -sSf https://raw.githubusercontent.com/X-Big-Tech/the-grid-releases/main/install.sh | sh
#   sh install.sh [--prefix <dir>]
#
# Options:
#   --prefix <dir>        Install binaries into <dir> (default: /usr/local/bin)
#
# Environment:
#   GRID_INSTALL_PREFIX   Same as --prefix (the flag wins when both are set)
#
# This script is strictly non-interactive: it never prompts, so it behaves
# identically under `curl | sh` (where stdin is the pipe) and in a terminal.
# It does not create system services; the closing summary prints the
# `grid-launcher service install` command for operators who want one.

set -eu

RELEASES_REPO="X-Big-Tech/the-grid-releases"
RELEASE_API_URL="https://api.github.com/repos/${RELEASES_REPO}/releases/latest"
DEFAULT_INSTALL_DIR="/usr/local/bin"
FALLBACK_INSTALL_DIR="${HOME}/.local/bin"

# Clean the staging directory on every exit path; signal traps exit so
# the EXIT trap fires instead of the script continuing without TEMP_DIR.
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Colors only when stdout is a terminal (escape codes would pollute logs)
if [ -t 1 ]; then
    RED=$(printf '\033[0;31m')
    GREEN=$(printf '\033[0;32m')
    YELLOW=$(printf '\033[1;33m')
    NC=$(printf '\033[0m')
else
    RED=""
    GREEN=""
    YELLOW=""
    NC=""
fi

info() { printf '%s\n' "$1"; }
ok()   { printf '%s%s%s\n' "$GREEN" "$1" "$NC"; }
warn() { printf '%s%s%s\n' "$YELLOW" "$1" "$NC"; }
fail() {
    printf '%sError: %s%s\n' "$RED" "$1" "$NC" >&2
    exit 1
}

usage() {
    cat << 'USAGE'
The Grid installer

Usage:
  install.sh [--prefix <dir>]

Options:
  --prefix <dir>   Install binaries into <dir> (default: /usr/local/bin)
  -h, --help       Show this help

Environment:
  GRID_INSTALL_PREFIX   Same as --prefix (the flag wins when both are set)
USAGE
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

INSTALL_DIR="${GRID_INSTALL_PREFIX:-}"
EXPLICIT_PREFIX=""
if [ -n "$INSTALL_DIR" ]; then
    EXPLICIT_PREFIX="1"
fi

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)
            [ $# -ge 2 ] || fail "--prefix requires a directory argument"
            INSTALL_DIR="$2"
            EXPLICIT_PREFIX="1"
            shift 2
            ;;
        --prefix=*)
            INSTALL_DIR="${1#--prefix=}"
            EXPLICIT_PREFIX="1"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            fail "Unknown option: $1"
            ;;
    esac
done

if [ -z "$INSTALL_DIR" ]; then
    INSTALL_DIR="$DEFAULT_INSTALL_DIR"
fi

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------

detect_os_arch() {
    case "$(uname -s)" in
        Darwin) OS="macos" ;;
        Linux)  OS="linux" ;;
        *)
            fail "Unsupported operating system: $(uname -s). Download binaries manually from https://github.com/${RELEASES_REPO}/releases"
            ;;
    esac

    case "$(uname -m)" in
        x86_64)        ARCH="amd64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        *)
            fail "Unsupported architecture: $(uname -m)"
            ;;
    esac

    # An x86_64 shell on Apple Silicon means the shell runs under Rosetta
    # translation; the machine itself is arm64, so install native binaries.
    if [ "$OS" = "macos" ] && [ "$ARCH" = "amd64" ] && \
       [ "$(sysctl -in sysctl.proc_translated 2>/dev/null)" = "1" ]; then
        ARCH="arm64"
        info "Detected Rosetta translation (x86_64 shell on Apple Silicon); installing native arm64 binaries."
    fi

    ok "Detected platform: ${OS}-${ARCH}"
}

# ---------------------------------------------------------------------------
# Release metadata + downloads
# ---------------------------------------------------------------------------

fetch_release_metadata() {
    info "Fetching latest release metadata..."
    if ! curl -fsSL --max-time 60 "$RELEASE_API_URL" -o "${TEMP_DIR}/release.json"; then
        printf '%s\n' "Could not fetch release information from ${RELEASE_API_URL}." >&2
        printf '%s\n' "If no release has been published yet, build from source instead:" >&2
        printf '%s\n' "  git clone https://github.com/X-Big-Tech/the-grid.git" >&2
        printf '%s\n' "  cd the-grid" >&2
        printf '%s\n' "  cargo build --release --bin grid --bin grid-launcher --bin grid-node" >&2
        fail "Failed to fetch release information"
    fi

    VERSION=$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' \
        "${TEMP_DIR}/release.json" | head -1)
    [ -n "$VERSION" ] || fail "Could not parse a release version from ${RELEASE_API_URL}"
    ok "Latest release: v${VERSION}"
}

# Print the download URL for an exact asset filename ($1), or nothing.
asset_url() {
    sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "${TEMP_DIR}/release.json" | grep "/$1\$" | head -1
}

# Download asset $1 into TEMP_DIR.
download_asset() {
    DOWNLOAD_URL=$(asset_url "$1")
    [ -n "$DOWNLOAD_URL" ] || fail "Release v${VERSION} has no asset named $1"
    info "  Downloading $1"
    curl -fSL --progress-bar --max-time 600 "$DOWNLOAD_URL" -o "${TEMP_DIR}/$1" || \
        fail "Failed to download $1"
}

# ---------------------------------------------------------------------------
# Checksum verification
# ---------------------------------------------------------------------------

sha256_of() {
    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum < "$1" | awk '{print $1}'
    elif command -v shasum > /dev/null 2>&1; then
        shasum -a 256 < "$1" | awk '{print $1}'
    else
        fail "Neither sha256sum nor shasum is available; cannot verify downloads"
    fi
}

# Verify TEMP_DIR/$1 against the entry for $1 in TEMP_DIR/SHA256SUMS.
# SHA256SUMS lines are "<hash>  <name>"; tolerate a "./" name prefix.
verify_asset() {
    EXPECTED=$(awk -v f="$1" '$2 == f || $2 == "./" f {print $1; exit}' \
        "${TEMP_DIR}/SHA256SUMS")
    [ -n "$EXPECTED" ] || fail "SHA256SUMS has no entry for $1"
    ACTUAL=$(sha256_of "${TEMP_DIR}/$1")
    if [ "$ACTUAL" != "$EXPECTED" ]; then
        fail "SHA256 mismatch for $1 (expected ${EXPECTED}, got ${ACTUAL})"
    fi
    ok "  Verified $1 (sha256 OK)"
}

# ---------------------------------------------------------------------------
# Installation
# ---------------------------------------------------------------------------

path_contains() {
    case ":${PATH}:" in
        *":$1:"*) return 0 ;;
        *)        return 1 ;;
    esac
}

# Make INSTALL_DIR exist and decide whether copies need sudo. When the
# default prefix is unwritable and sudo is unavailable (or fails, e.g. no
# tty to prompt on), fall back to ~/.local/bin. An explicit prefix never
# silently falls back: the user asked for that exact directory.
prepare_install_dir() {
    SUDO=""
    if mkdir -p "$INSTALL_DIR" 2> /dev/null && [ -w "$INSTALL_DIR" ]; then
        return 0
    fi

    if command -v sudo > /dev/null 2>&1; then
        warn "${INSTALL_DIR} is not writable; using sudo for directory creation and binary copies."
        if sudo mkdir -p "$INSTALL_DIR" 2> /dev/null; then
            SUDO="sudo"
            return 0
        fi
    fi

    if [ -n "$EXPLICIT_PREFIX" ]; then
        fail "Cannot write to ${INSTALL_DIR} and sudo is unavailable. Re-run with a writable --prefix (or GRID_INSTALL_PREFIX)."
    fi

    warn "Cannot write to ${INSTALL_DIR} without sudo; falling back to ${FALLBACK_INSTALL_DIR}"
    INSTALL_DIR="$FALLBACK_INSTALL_DIR"
    mkdir -p "$INSTALL_DIR" || fail "Failed to create ${INSTALL_DIR}"
}

# Extract binary $2 from tarball TEMP_DIR/$1 and copy it into INSTALL_DIR.
install_binary_from_tarball() {
    tar -xzf "${TEMP_DIR}/$1" -C "$TEMP_DIR" "$2" || \
        fail "Failed to extract $2 from $1"
    chmod +x "${TEMP_DIR}/$2"
    info "  Installing $2 -> ${INSTALL_DIR}/$2"
    $SUDO cp "${TEMP_DIR}/$2" "${INSTALL_DIR}/$2" || \
        fail "Failed to install $2 to ${INSTALL_DIR}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    info "The Grid - Proof of Network Installation"
    info "=========================================="
    info ""

    command -v curl > /dev/null 2>&1 || fail "curl is required but not installed"
    command -v tar > /dev/null 2>&1 || fail "tar is required but not installed"

    detect_os_arch
    fetch_release_metadata

    # SHA256SUMS first: without it, nothing else can be verified.
    download_asset "SHA256SUMS"

    CLI_ASSET="grid-cli-${VERSION}-${OS}-${ARCH}.tar.gz"
    LAUNCHER_ASSET="grid-launcher-${VERSION}-${OS}-${ARCH}.tar.gz"

    download_asset "$CLI_ASSET"
    verify_asset "$CLI_ASSET"
    download_asset "$LAUNCHER_ASSET"
    verify_asset "$LAUNCHER_ASSET"

    prepare_install_dir
    install_binary_from_tarball "$CLI_ASSET" "grid"
    install_binary_from_tarball "$LAUNCHER_ASSET" "grid-launcher"

    if ! path_contains "$INSTALL_DIR"; then
        warn "NOTE: ${INSTALL_DIR} is not on your PATH."
        info "  Add it in your shell profile (~/.profile, ~/.bashrc, or ~/.zshrc):"
        info "    export PATH=\"${INSTALL_DIR}:\$PATH\""
    fi

    # grid-launcher install downloads and installs the matching grid-node
    # binary, then exits (no service is created and nothing is started).
    info ""
    info "Installing grid-node via grid-launcher..."
    export GRID_INSTALL_PREFIX="$INSTALL_DIR"
    if ! "${INSTALL_DIR}/grid-launcher" install; then
        printf '%s\n' "${RED}Error: grid-node installation failed.${NC}" >&2
        printf '%s\n' "Fix the issue above, then re-run just this step with:" >&2
        printf '%s\n' "  ${INSTALL_DIR}/grid-launcher install" >&2
        exit 1
    fi

    info ""
    ok "The Grid installation complete: grid, grid-launcher, grid-node"
    info ""
    info "Optional system service (runs grid-node under systemd/launchd):"
    info "  grid-launcher service install"
    info ""
    info "Documentation: https://github.com/X-Big-Tech/the-grid/docs"
    info "Support: bryan@xbigtech.com"
    info ""
    info "Next: grid onboard   (guided operator onboarding)"
}

main
