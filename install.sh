#!/bin/sh

# The Grid Installation Script
# Author: Bryan Campbell <bryan@xbigtech.com>
#
# Installs `grid-launcher` from the latest GitHub release, verified against
# the release's SHA256SUMS, then runs `grid-launcher install`, which downloads
# and verifies grid-node and the `grid` CLI from that same release.
#
# The binaries go into /usr/local/bin, system-wide like the node services the
# launcher manages; when that directory needs root, sudo asks for your password
# once and every step that writes there, the launcher's included, runs under
# it. Without sudo the install falls back to ~/.local/bin.
#
# Usage:
#   curl -sSf https://raw.githubusercontent.com/X-Big-Tech/the-grid-releases/main/install.sh | sh
#   sh install.sh [--prefix <dir>] [--no-modify-path]
#
# Options:
#   --prefix <dir>        Install binaries into <dir> (default: /usr/local/bin)
#   --no-modify-path      Leave shell profiles alone when <dir> is not on PATH
#
# Environment:
#   GRID_INSTALL_PREFIX   Same as --prefix (the flag wins when both are set)
#   GRID_NO_MODIFY_PATH   Set to 1 for --no-modify-path
#
# This script is strictly non-interactive: it never prompts, so it behaves
# identically under `curl | sh` (where stdin is the pipe) and in a terminal.

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
  install.sh [--prefix <dir>] [--no-modify-path]

Options:
  --prefix <dir>     Install binaries into <dir> (default: /usr/local/bin)
  --no-modify-path   Leave shell profiles alone when <dir> is not on PATH
  -h, --help         Show this help

Environment:
  GRID_INSTALL_PREFIX   Same as --prefix (the flag wins when both are set)
  GRID_NO_MODIFY_PATH   Set to 1 for --no-modify-path
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
MODIFY_PATH="1"
if [ "${GRID_NO_MODIFY_PATH:-}" = "1" ]; then
    MODIFY_PATH=""
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
        --no-modify-path)
            MODIFY_PATH=""
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

# True when this user can create files in directory $1.
can_write() {
    PROBE=$(mktemp "$1/.grid-install-probe.XXXXXX" 2> /dev/null) || return 1
    rm -f "$PROBE"
}

# Make INSTALL_DIR exist and decide whether writing it needs sudo. When the
# default prefix is unwritable and sudo is unavailable (or fails, e.g. no
# tty to prompt on), fall back to ~/.local/bin. An explicit prefix never
# silently falls back: the user asked for that exact directory.
prepare_install_dir() {
    SUDO=""
    if mkdir -p "$INSTALL_DIR" 2> /dev/null && can_write "$INSTALL_DIR"; then
        return 0
    fi

    if command -v sudo > /dev/null 2>&1; then
        warn "${INSTALL_DIR} needs root; sudo installs the Grid binaries there."
        if sudo mkdir -p "$INSTALL_DIR"; then
            SUDO="sudo"
            return 0
        fi
    fi

    if [ -n "$EXPLICIT_PREFIX" ]; then
        fail "Cannot write to ${INSTALL_DIR} and sudo is unavailable. Re-run with a writable --prefix (or GRID_INSTALL_PREFIX)."
    fi

    warn "Cannot write to ${INSTALL_DIR} without sudo; installing into ${FALLBACK_INSTALL_DIR} instead."
    INSTALL_DIR="$FALLBACK_INSTALL_DIR"
    mkdir -p "$INSTALL_DIR" || fail "Failed to create ${INSTALL_DIR}"
}

# Extract binary $2 from tarball TEMP_DIR/$1 and move it into INSTALL_DIR.
# The copy lands beside the target first and is renamed over it, so a
# running binary is replaced, never truncated.
install_binary_from_tarball() {
    tar -xzf "${TEMP_DIR}/$1" -C "$TEMP_DIR" "$2" || \
        fail "Failed to extract $2 from $1"
    chmod 755 "${TEMP_DIR}/$2"
    info "  Installing $2 -> ${INSTALL_DIR}/$2"
    $SUDO cp "${TEMP_DIR}/$2" "${INSTALL_DIR}/.$2.new" && \
        $SUDO mv -f "${INSTALL_DIR}/.$2.new" "${INSTALL_DIR}/$2" || \
        fail "Failed to install $2 to ${INSTALL_DIR}"
}

# INSTALL_DIR as a shell profile should name it: under $HOME, relative to it.
profile_dir_expr() {
    case "$INSTALL_DIR" in
        "$HOME"/*) printf '%s' "\$HOME/${INSTALL_DIR#"$HOME"/}" ;;
        *)         printf '%s' "$INSTALL_DIR" ;;
    esac
}

# Append LINE ($2) to profile $1 unless it is already there.
add_line_once() {
    if [ -f "$1" ] && grep -qxF "$2" "$1"; then
        return 0
    fi
    printf '\n%s\n%s\n' "# The Grid: grid, grid-launcher and grid-node (added by the Grid installer)" "$2" >> "$1" || \
        { warn "Could not update $1"; return 0; }
    UPDATED_PROFILES="${UPDATED_PROFILES} ${1#"$HOME"/}"
}

# Put INSTALL_DIR on PATH for new shells, as rustup and uv do: the profiles
# that exist, plus the login shell's own rc file. Only ever needed for a
# directory that is not on PATH already, such as the ~/.local/bin fallback.
modify_path() {
    DIR_EXPR=$(profile_dir_expr)
    POSIX_LINE='case ":${PATH}:" in *":'"$DIR_EXPR"':"*) ;; *) export PATH="'"$DIR_EXPR"':$PATH" ;; esac'
    UPDATED_PROFILES=""
    LOGIN_SHELL=$(basename "${SHELL:-sh}")

    for rc in "${HOME}/.profile" "${HOME}/.bash_profile" "${HOME}/.bashrc" "${HOME}/.zshrc"; do
        [ -f "$rc" ] && add_line_once "$rc" "$POSIX_LINE"
    done
    case "$LOGIN_SHELL" in
        bash) [ -f "${HOME}/.bashrc" ] || add_line_once "${HOME}/.bashrc" "$POSIX_LINE" ;;
        zsh)  [ -f "${HOME}/.zshrc" ] || add_line_once "${HOME}/.zshrc" "$POSIX_LINE" ;;
    esac
    if [ "$LOGIN_SHELL" = "fish" ] || [ -d "${HOME}/.config/fish" ]; then
        mkdir -p "${HOME}/.config/fish/conf.d" && \
            add_line_once "${HOME}/.config/fish/conf.d/grid.fish" \
                "if not contains -- \"${DIR_EXPR}\" \$PATH; set -gx PATH \"${DIR_EXPR}\" \$PATH; end"
    fi
}

# Copies of the binaries elsewhere on PATH (an earlier install into
# /usr/local/bin, say) run instead of these wherever they come first.
report_other_copies() {
    OTHERS=""
    for bin in grid grid-launcher grid-node; do
        FOUND=$(command -v "$bin" 2> /dev/null || true)
        case "$FOUND" in
            "" | "${INSTALL_DIR}/${bin}") ;;
            /*) OTHERS="${OTHERS} ${FOUND}" ;;
        esac
    done
    [ -n "$OTHERS" ] || return 0
    warn "Other copies of the Grid binaries are on your PATH:${OTHERS}"
    info "  They run instead of the ones in ${INSTALL_DIR} wherever they come first. Remove them with:"
    REMOVE="rm -f"
    for other in $OTHERS; do
        [ -w "$(dirname "$other")" ] || REMOVE="sudo rm -f"
    done
    info "    ${REMOVE}${OTHERS}"
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
    prepare_install_dir

    # SHA256SUMS first: without it, nothing else can be verified.
    download_asset "SHA256SUMS"
    LAUNCHER_ASSET="grid-launcher-${VERSION}-${OS}-${ARCH}.tar.gz"
    download_asset "$LAUNCHER_ASSET"
    verify_asset "$LAUNCHER_ASSET"
    install_binary_from_tarball "$LAUNCHER_ASSET" "grid-launcher"

    # The launcher installs grid-node and grid from the same release into
    # the same directory, verifies them against its SHA256SUMS and records
    # what it installed. It writes where the copies above did, so it runs
    # under the same sudo; -H gives it root's home for its own records
    # (macOS sudo keeps the caller's), where its root agent reads them.
    info ""
    info "Installing grid-node and grid with grid-launcher..."
    if ! $SUDO ${SUDO:+-H} "${INSTALL_DIR}/grid-launcher" install --install-dir "$INSTALL_DIR" --version "$VERSION"; then
        printf '%s\n' "${RED}Error: grid-launcher could not install grid-node and grid.${NC}" >&2
        printf '%s\n' "Fix the issue above, then re-run just this step with:" >&2
        printf '%s\n' "  ${SUDO:+sudo -H }${INSTALL_DIR}/grid-launcher install --install-dir ${INSTALL_DIR} --version ${VERSION}" >&2
        exit 1
    fi

    info ""
    ok "The Grid v${VERSION} is installed in ${INSTALL_DIR}: grid, grid-launcher, grid-node"

    if ! path_contains "$INSTALL_DIR"; then
        info ""
        if [ -n "$MODIFY_PATH" ]; then
            modify_path
            if [ -n "$UPDATED_PROFILES" ]; then
                info "Added ${INSTALL_DIR} to your PATH in:${UPDATED_PROFILES}"
            fi
            info "New terminals find the Grid commands. To use them in this one now, run:"
        else
            warn "${INSTALL_DIR} is not on your PATH. Add it in your shell profile, or for this terminal run:"
        fi
        info "  export PATH=\"${INSTALL_DIR}:\$PATH\""
    fi
    report_other_copies

    info ""
    info "Next:"
    info "  grid onboard        set up and start a node, step by step"
    info "  grid-launcher pair  pair this machine with your account from the website"
    info ""
    info "To run a node as a system service:"
    info "  sudo ${INSTALL_DIR}/grid-launcher service install --config <node.json>"
    info ""
    info "Support: bryan@xbigtech.com"
}

main
