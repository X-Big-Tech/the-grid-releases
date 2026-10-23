# The Grid — Releases

[![Latest Release](https://img.shields.io/github/v/release/X-Big-Tech/the-grid-releases)](https://github.com/X-Big-Tech/the-grid-releases/releases/latest)

Builds of **The Grid**: `grid-node` (the node), `grid-launcher` (installs, updates,
pairs and runs the node as a service) and `grid` (the command-line tool). This repository holds
the releases and the install scripts; it is published from the main repository on every release,
so what is here matches the latest release.

## Install

### Linux and macOS

```bash
curl -sSf https://raw.githubusercontent.com/X-Big-Tech/the-grid-releases/main/install.sh | sh
```

The script downloads `grid-launcher` for your system, checks it against the release's
`SHA256SUMS`, and installs it into `/usr/local/bin`; `grid-launcher install` then fetches and
checks `grid-node` and `grid` from the same release. When `/usr/local/bin` needs root, sudo asks
for your password once. Without sudo it installs into `~/.local/bin` and adds that directory to
your shell profile. Options: `--prefix <dir>`, `--no-modify-path`. Read it first:
[install.sh](install.sh).

### Windows

Windows builds (`.zip`) are published with every release. A Windows installer and automatic
Windows service setup arrive in the next release; until then, pairing a Windows machine is not
supported.

## Pair a machine with your account

Open **Add a machine** on the network's website (for the Grid's own network,
[gridian.io/network/nodes/pair](https://gridian.io/network/nodes/pair)). It shows the command for
your system:

| System  | Command | Why |
|---------|---------|-----|
| Linux   | `sudo grid-launcher pair --web-origin https://gridian.io` | The node runs as a systemd service, which needs root to install. The node itself runs as you. |
| macOS   | `grid-launcher pair --web-origin https://gridian.io` | The node runs as your own LaunchAgent. Add `--system` (with `sudo`) for a LaunchDaemon that survives logout. |

The launcher asks the website which chain it pairs onto, downloads that chain's genesis from
`https://gridprotocol.io/network/<chain-id>.json` and refuses it unless its hash is the chain's,
then shows an eight-character code, three check words and a QR code. Enter the code on the
website (or scan the QR code), check the three words match, and grant the machine on one of your
accounts. Back on the machine, confirm the account; the launcher configures the node, installs
its service, starts it and waits until the node sees its grant on chain.

## Downloads

Every release has `grid-launcher`, `grid-node` and `grid` (published as `grid-cli-*`) for each
platform, plus `SHA256SUMS`:

| Platform | Archives |
|----------|----------|
| Linux x86_64 (glibc 2.35+: Ubuntu 22.04+, Debian 12+, RHEL 9+) | `grid-{launcher,node,cli}-<version>-linux-amd64.tar.gz` |
| Linux ARM64 (glibc 2.35+) | `grid-{launcher,node,cli}-<version>-linux-arm64.tar.gz` |
| Linux x86_64, static (musl: any distribution, Alpine, containers) | `grid-{launcher,node,cli}-<version>-linux-amd64-musl.tar.gz` |
| Linux ARM64, static (musl) | `grid-{launcher,node,cli}-<version>-linux-arm64-musl.tar.gz` |
| macOS Apple silicon | `grid-{launcher,node,cli}-<version>-macos-arm64.tar.gz` |
| macOS Intel | `grid-{launcher,node,cli}-<version>-macos-amd64.tar.gz` |
| Windows x86_64 | `grid-{launcher,node,cli}-<version>-windows-amd64.zip` |

Every binary links only the operating system's own libraries.

Check downloads before using them:

```bash
sha256sum -c --ignore-missing SHA256SUMS            # Linux: checks every file you downloaded
shasum -a 256 grid-launcher-<version>-macos-arm64.tar.gz   # macOS: compare with its line in SHA256SUMS
```

## The launcher

| Command | What it does |
|---------|--------------|
| `grid-launcher install [--install-dir DIR] [--version V]` | Download and install `grid-node` and `grid`, checked against `SHA256SUMS`. |
| `grid-launcher update` | Update the installed binaries. Never restarts running services; it prints the restart command for each. |
| `grid-launcher pair --web-origin URL` | Pair this machine with an account through a network's website (above). |
| `grid-launcher service install --config <node.json>` | Run a node configured by `grid onboard` as a service (systemd or launchd). |
| `grid-launcher service uninstall [--name N]` | Stop and remove a node service. |
| `grid-launcher uninstall` | Remove the binaries. Refused while a node service still runs them. Keys and configs under `~/.grid` are kept. |
| `grid-launcher network list` / `network add` / `network use` | The networks this machine pairs through. |
| `grid-launcher agent install` | The background agent that applies configuration the node's owners publish and rolls out signed upgrades. |

On Linux, commands that install a system service run under sudo. Name the launcher by its path
there if it is in `~/.local/bin`, which sudo's `PATH` leaves out:
`sudo "$(command -v grid-launcher)" …`.

## Operators

`grid onboard` sets up a node step by step: keys, operator account, genesis, configuration and
start. See `grid onboard --help`, and `grid-node --help` for the node's own options.

The node uses UDP port 8333 for peer traffic (QUIC); open it in your firewall. Validators also
use TCP port 8335 for consensus.

## Support

- Issues: [GitHub issues](https://github.com/X-Big-Tech/the-grid-releases/issues)
- Email: bryan@xbigtech.com

## License

Apache 2.0. See [LICENSE](LICENSE).
