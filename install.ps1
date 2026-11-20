# The Grid Installation Script for Windows
# Author: Bryan Campbell <bryan@xbigtech.com>
#
# Installs `grid-launcher` from the latest GitHub release, verified against
# the release's SHA256SUMS, then runs `grid-launcher install`, which downloads
# and verifies grid-node and the `grid` CLI from that same release. It is the
# Windows twin of install.sh.
#
# Run it in an administrator PowerShell (right-click Windows PowerShell or
# Terminal, then Run as administrator):
#
#   irm https://raw.githubusercontent.com/X-Big-Tech/the-grid-releases/main/install.ps1 | iex
#
# The binaries go into %ProgramFiles%\Grid, which only administrators can
# change. It is the one folder grid-launcher runs the node's service from, so
# no other install folder is offered. The folder is added to the machine PATH,
# and to this window's so the next command works here at once.
#
# The node itself is set up later by `grid-launcher pair`. Its config, keys
# and chain data go into the machine's Grid home, %ProgramData%\Grid, which
# only administrators and the node's own service can change, and the node
# runs as a Windows service under its own virtual account,
# NT SERVICE\grid-node-<name>, which is granted its own folder and nothing
# else on the machine.
#
# Environment:
#   GRID_NO_MODIFY_PATH   Set to 1 to leave PATH alone
#
# Strictly non-interactive: it never prompts. It runs inside a script block, so
# under `irm | iex` it leaves no variables or preferences behind in the
# caller's session and never closes the window; only PATH and TLS settings
# outlive it.

& {
    $ErrorActionPreference = 'Stop'
    # Windows PowerShell 5.1 redraws its progress bar for every block it
    # downloads, which makes large downloads many times slower.
    $ProgressPreference = 'SilentlyContinue'

    $ReleasesRepo = 'X-Big-Tech/the-grid-releases'
    $ReleaseApiUrl = "https://api.github.com/repos/$ReleasesRepo/releases/latest"

    function Write-Info([string] $Message) { Write-Host $Message }
    function Write-Ok([string] $Message) { Write-Host $Message -ForegroundColor Green }
    function Write-Warn([string] $Message) { Write-Host $Message -ForegroundColor Yellow }

    # The folder the binaries go into: Grid under the 64-bit Program Files,
    # where grid-launcher runs the node's service from. It is read from the
    # system, as the launcher reads it, never from environment variables,
    # which this account's own settings can override. GetFolderPath shows a
    # 32-bit PowerShell the x86 folder, so there the 64-bit one is read from
    # the 64-bit registry view.
    function Get-InstallDir {
        $programFiles = [Environment]::GetFolderPath('ProgramFiles')
        if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
            $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                [Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
            try {
                $key = $hklm.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion')
                $programFiles = [string] $key.GetValue('ProgramFilesDir')
            } finally {
                $hklm.Dispose()
            }
        }
        if (-not $programFiles) {
            throw 'Could not locate the Program Files folder.'
        }
        return (Join-Path $programFiles 'Grid')
    }

    function Assert-Administrator {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw ("This installer needs an administrator PowerShell: it installs into " +
                "Program Files and the node runs as a Windows service. Right-click " +
                "Windows PowerShell (or Terminal), choose Run as administrator, and run " +
                "the same line there.")
        }
    }

    # The release platform for this machine. Windows 11 on ARM runs the x64
    # build under its x64 emulation; Windows 10 on ARM cannot.
    function Get-Platform {
        $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
        switch ($arch) {
            'AMD64' { }
            'ARM64' {
                Write-Warn ("This is an ARM64 machine: the Grid's x64 build runs under " +
                    "Windows 11's x64 emulation (Windows 10 on ARM cannot run it).")
            }
            default {
                throw ("Unsupported architecture: $arch. The Grid ships Windows builds for x64. " +
                    "Download binaries manually from https://github.com/$ReleasesRepo/releases")
            }
        }
        Write-Ok 'Detected platform: windows-amd64'
        return 'windows-amd64'
    }

    function Get-LatestRelease {
        Write-Info 'Fetching latest release metadata...'
        try {
            # Windows PowerShell 5.1 refuses User-Agent in -Headers; it has
            # its own parameter.
            $release = Invoke-RestMethod -Uri $ReleaseApiUrl -UseBasicParsing -TimeoutSec 60 `
                -UserAgent 'grid-install' -Headers @{ 'Accept' = 'application/vnd.github+json' }
        } catch {
            throw "Could not fetch release information from ${ReleaseApiUrl}: $($_.Exception.Message)"
        }
        $version = ([string] $release.tag_name) -replace '^v', ''
        if (-not $version) {
            throw "Could not parse a release version from $ReleaseApiUrl"
        }
        Write-Ok "Latest release: v$version"
        return $release
    }

    # Download the release asset named exactly $Name into $Dir.
    function Get-Asset($Release, [string] $Name, [string] $Dir) {
        $asset = @($Release.assets | Where-Object { $_.name -ceq $Name }) | Select-Object -First 1
        if (-not $asset) {
            throw "Release $($Release.tag_name) has no asset named $Name"
        }
        $path = Join-Path $Dir $Name
        Write-Info "  Downloading $Name"
        try {
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $path -UseBasicParsing -TimeoutSec 600
        } catch {
            throw "Failed to download ${Name}: $($_.Exception.Message)"
        }
        return $path
    }

    # Verify $Path against the entry for its file name in SHA256SUMS, whose
    # lines are "<hash>  <name>", tolerating a "./" or "*" before the name.
    function Assert-Checksum([string] $Path, [string] $SumsPath) {
        $name = Split-Path $Path -Leaf
        $expected = $null
        foreach ($line in Get-Content -LiteralPath $SumsPath) {
            if ($line -match '^([0-9a-fA-F]{64})\s+\*?(\./)?(.+?)\s*$' -and $Matches[3] -ceq $name) {
                $expected = $Matches[1]
                break
            }
        }
        if (-not $expected) {
            throw "SHA256SUMS has no entry for $name"
        }
        $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
        if ($actual -ne $expected) {
            throw "SHA256 mismatch for $name (expected $expected, got $actual)"
        }
        Write-Ok "  Verified $name (sha256 OK)"
    }

    # What to do when Windows refuses to start a Grid program. Smart App
    # Control on Windows 11 blocks programs that are not signed, with no
    # exception for a single program (Microsoft, "Smart App Control:
    # frequently asked questions"), and the Grid's Windows programs are not
    # signed yet.
    function Write-SmartAppControlSteps {
        Write-Warn ("Windows refused to start a Grid program. On Windows 11 this is usually Smart App " +
            "Control, which blocks programs that are not signed; the Grid's Windows programs are not signed yet.")
        Write-Info ("  1. Open Windows Security > App & browser control > Smart App Control settings. " +
            "If there is no such section (Windows 10), there is nothing to change.")
        Write-Info ("  2. If it says Off, you are ready. If it says On or Evaluation, first install any " +
            "waiting Windows updates (so it can be turned back on later without reinstalling Windows), then " +
            "choose Off. Evaluation counts too, because Windows can turn it on by itself.")
        Write-Info ("  3. Leave it off while this machine runs a node: it checks programs as they start, " +
            "so turning it back on stops the node the next time it starts.")
        Write-Info 'Then run this install again.'
    }

    function Test-PathEntry([string] $PathValue, [string] $Dir) {
        foreach ($entry in ($PathValue -split ';')) {
            if ($entry -and ($entry.TrimEnd('\') -eq $Dir.TrimEnd('\'))) {
                return $true
            }
        }
        return $false
    }

    # Append $Dir to the machine PATH, read and written unexpanded so entries
    # like %SystemRoot% stay references, then tell running programs the
    # environment changed: .NET broadcasts that on any machine- or user-level
    # change, so a throwaway user variable is set and removed.
    function Add-MachinePath([string] $Dir) {
        $key = Get-Item -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
        $current = [string] $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
        if (Test-PathEntry $current $Dir) {
            return $false
        }
        $updated = if ($current.TrimEnd(';')) { $current.TrimEnd(';') + ';' + $Dir } else { $Dir }
        Set-ItemProperty -LiteralPath $key.PSPath -Name 'Path' -Value $updated -Type ExpandString
        $marker = 'GRID_INSTALL_' + [guid]::NewGuid().ToString('N')
        [Environment]::SetEnvironmentVariable($marker, '1', 'User')
        [Environment]::SetEnvironmentVariable($marker, $null, 'User')
        return $true
    }

    function Show-OtherCopies([string] $Dir) {
        $others = @(Get-Command -Name grid, grid-node, grid-launcher -CommandType Application -All -ErrorAction SilentlyContinue |
            Where-Object { (Split-Path $_.Source -Parent).TrimEnd('\') -ne $Dir.TrimEnd('\') } |
            ForEach-Object { $_.Source } | Select-Object -Unique)
        if ($others.Count -gt 0) {
            Write-Warn "Other copies of the Grid binaries are on your PATH: $($others -join ', ')"
            Write-Info "  They run instead of the ones in $Dir wherever they come first. Remove them."
        }
    }

    function Install-Grid([string] $TempDir) {
        Write-Info 'The Grid - Proof of Network Installation'
        Write-Info '=========================================='
        Write-Info ''

        Assert-Administrator
        # GitHub serves TLS 1.2 or later only; Windows PowerShell 5.1 on older
        # .NET defaults may not offer it.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        $platform = Get-Platform
        $release = Get-LatestRelease
        $version = ([string] $release.tag_name) -replace '^v', ''
        $installDir = Get-InstallDir
        New-Item -ItemType Directory -Force -Path $installDir | Out-Null

        # SHA256SUMS first: without it, nothing else can be verified.
        $sums = Get-Asset $release 'SHA256SUMS' $TempDir
        $launcherAsset = "grid-launcher-$version-$platform.zip"
        $launcherZip = Get-Asset $release $launcherAsset $TempDir
        Assert-Checksum $launcherZip $sums

        $staging = Join-Path $TempDir 'launcher'
        Expand-Archive -LiteralPath $launcherZip -DestinationPath $staging -Force
        $extracted = Join-Path $staging 'grid-launcher.exe'
        if (-not (Test-Path -LiteralPath $extracted -PathType Leaf)) {
            throw "$launcherAsset does not contain grid-launcher.exe"
        }
        $launcher = Join-Path $installDir 'grid-launcher.exe'
        Copy-Item -LiteralPath $extracted -Destination $launcher -Force
        Write-Ok "  Installed $launcher"

        # The launcher installs grid-node and grid from the same release into
        # the same folder, verifies them against its SHA256SUMS and records
        # what it installed in the machine's Grid home, %ProgramData%\Grid,
        # which it sets up owned by Administrators.
        Write-Info ''
        Write-Info 'Installing grid-node and grid with grid-launcher...'
        try {
            & $launcher install --install-dir $installDir --version $version
        } catch {
            # The program did not start at all: Windows blocked it.
            Write-Host "Error: Windows did not start ${launcher}: $($_.Exception.Message)" -ForegroundColor Red
            Write-SmartAppControlSteps
            return
        }
        if ($LASTEXITCODE -ne 0) {
            throw ("grid-launcher could not install grid-node and grid. Fix the issue above, " +
                "then re-run just this step with:`n  & '$launcher' install --install-dir '$installDir' --version $version")
        }

        Write-Info ''
        Write-Ok "The Grid v$version is installed in ${installDir}: grid, grid-launcher, grid-node"

        if ($env:GRID_NO_MODIFY_PATH -ne '1') {
            if (Add-MachinePath $installDir) {
                Write-Info "Added $installDir to the machine PATH; new windows find the Grid commands."
            }
            if (-not (Test-PathEntry $env:Path $installDir)) {
                $env:Path = "$installDir;$env:Path"
            }
        } elseif (-not (Test-PathEntry $env:Path $installDir)) {
            Write-Warn "$installDir is not on your PATH. For this window, run:"
            Write-Info "  `$env:Path = `"$installDir;`$env:Path`""
        }
        Show-OtherCopies $installDir

        Write-Info ''
        Write-Info 'Next, in this administrator PowerShell:'
        Write-Info '  grid-launcher pair --web-origin <website>   pair this machine with your account (the Add a machine page shows the line)'
        Write-Info ''
        Write-Info ("The node then runs as a Windows service under its own account, with its config, " +
            "keys and data in the Grid home ($(Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'Grid')), " +
            "which only administrators can change.")
        Write-Info ''
        Write-Info 'Support: bryan@xbigtech.com'
    }

    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('grid-install-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    try {
        Install-Grid $tempDir
    } catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
