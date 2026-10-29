# SPDX-License-Identifier: AGPL-3.0-or-later
<#
.SYNOPSIS
    Install (if needed) and start SearXNG natively on Windows.

.DESCRIPTION
    On first run this script

    - creates a Python virtual environment in .venv and installs the
      requirements (again whenever a requirements file changes),
    - creates a settings file with a random, permanent secret key in
      %APPDATA%\searxng\settings.yml (only if it does not exist yet),
    - asks which optional components for AI agents to install (see
      -Components) and remembers the answer.

    Then it starts SearXNG with the Granian web server, the same server the
    official SearXNG container uses.

    Nothing is registered with Claude or any other AI tool: the script only
    prints the command to do so yourself.

.PARAMETER Port
    TCP port to listen on (default 8888).

.PARAMETER BindAddress
    Address to listen on (default 127.0.0.1, only this computer).  Use 0.0.0.0
    to make SearXNG reachable from other devices in your network.

.PARAMETER ConfigDir
    Folder holding settings.yml (default %APPDATA%\searxng).

.PARAMETER Update
    Reinstall the requirements even if they did not change.

.PARAMETER Setup
    Ask again which optional components to install.

.PARAMETER Components
    Choose the optional components without being asked (comma-separated):
      mcp      MCP server with a search tool for AI agents
      fetch    + a fetch tool that reads web pages (Trafilatura)
      browser  + a headless browser for pages that need JavaScript
               (Playwright and Chromium, about 280 MB)
      none     no optional components
    Each component needs the one before it; those are added automatically.

.EXAMPLE
    .\start-searxng.ps1

.EXAMPLE
    .\start-searxng.ps1 -Port 9000 -BindAddress 0.0.0.0

.EXAMPLE
    .\start-searxng.ps1 -Components mcp,fetch
#>

[CmdletBinding()]
param(
    [int]$Port = 8888,
    [string]$BindAddress = '127.0.0.1',
    [string]$ConfigDir = (Join-Path $env:APPDATA 'searxng'),
    [switch]$Update,
    [switch]$Setup,
    [string[]]$Components
)

# Not 'Stop': Windows PowerShell 5.1 would turn harmless stderr output of pip
# and granian into terminating errors.  Native calls check $LASTEXITCODE.
$ErrorActionPreference = 'Continue'
$RepoRoot = $PSScriptRoot
$VenvDir = Join-Path $RepoRoot '.venv'
$VenvPython = Join-Path $VenvDir 'Scripts\python.exe'
$Requirements = @('requirements.txt', 'requirements-server.txt') | ForEach-Object { Join-Path $RepoRoot $_ }
$RequirementsStamp = Join-Path $VenvDir '.sxng-requirements.sha256'
$ComponentsFile = Join-Path $VenvDir '.sxng-components'

# Optional components for AI agents, in install order; each needs the one before.
$KnownComponents = [ordered]@{
    mcp     = @{
        Requires     = @()
        Requirements = 'searxng_mcp\requirements.txt'
        Question     = 'Install the MCP server, so AI agents (Claude Code, Claude Desktop, ...) can search with SearXNG?'
    }
    fetch   = @{
        Requires     = @('mcp')
        Requirements = 'searxng_mcp\requirements-fetch.txt'
        Question     = 'Install page reading (Trafilatura), so agents can read the text of web pages?'
    }
    browser = @{
        Requires     = @('fetch')
        Requirements = 'searxng_mcp\requirements-browser.txt'
        Question     = 'Install a headless browser (Playwright + Chromium, about 280 MB) for pages that need JavaScript?'
    }
}

function Find-Python {
    # Prefer the Python launcher (py.exe), fall back to python.exe on PATH.
    $candidates = @(@('py', '-3'), @('python'))
    foreach ($cmd in $candidates) {
        if (-not (Get-Command $cmd[0] -ErrorAction SilentlyContinue)) { continue }
        $exe = $cmd[0]
        $cmdArgs = @($cmd | Select-Object -Skip 1)
        # no quotes in the Python code: Windows PowerShell 5.1 mangles them
        # when passing arguments to native programs
        try {
            $version = & $exe @cmdArgs -c 'import sys; print(*sys.version_info[:2], sep=chr(46))' 2>$null
        }
        catch { continue }
        if ($LASTEXITCODE -ne 0 -or -not $version) { continue }
        if ([version]$version -ge [version]'3.10') {
            return @{ Exe = $exe; Args = $cmdArgs }
        }
        Write-Warning "Python $version found, but SearXNG needs Python 3.10 or newer."
    }
    throw 'Python 3.10 or newer is required. Install it from https://www.python.org/downloads/windows/ and run this script again.'
}

function Read-YesNo([string]$Question) {
    while ($true) {
        $answer = (Read-Host "$Question [y/N]").Trim().ToLower()
        if ($answer -in @('', 'n', 'no')) { return $false }
        if ($answer -in @('y', 'yes')) { return $true }
    }
}

function Get-SelectedComponents {
    if ($Components) {
        $list = @($Components | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
        foreach ($name in $list) {
            if ($name -ne 'none' -and -not $KnownComponents.Contains($name)) {
                throw "Unknown component '$name'. Known components: $(@($KnownComponents.Keys) -join ', '), none"
            }
        }
        $list = @($list | Where-Object { $_ -ne 'none' })
    }
    elseif (-not $Setup -and (Test-Path $ComponentsFile)) {
        $raw = Get-Content -Raw $ComponentsFile
        $list = if ($raw) { @($raw.Trim() -split ',' | Where-Object { $KnownComponents.Contains($_) }) } else { @() }
    }
    elseif ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
        Write-Host ''
        Write-Host 'Optional components for AI agents (change later with: .\start-searxng.ps1 -Setup)'
        $list = @()
        foreach ($name in $KnownComponents.Keys) {
            $missing = @($KnownComponents[$name].Requires | Where-Object { $list -notcontains $_ })
            if ($missing.Count -eq 0 -and (Read-YesNo "  $($KnownComponents[$name].Question)")) {
                $list += $name
            }
        }
        Write-Host ''
    }
    else {
        $list = @()  # not interactive (e.g. CI): no optional components unless -Components is given
    }

    # add the components the selected ones need
    do {
        $added = $false
        foreach ($name in @($list)) {
            foreach ($required in $KnownComponents[$name].Requires) {
                if ($list -notcontains $required) { $list += $required; $added = $true }
            }
        }
    } while ($added)
    return @($KnownComponents.Keys | Where-Object { $list -contains $_ })
}

function Get-RequirementsHash {
    $text = ($Requirements | ForEach-Object { Get-Content -Raw $_ }) -join "`n"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text))
    return ([System.BitConverter]::ToString($bytes) -replace '-', '').ToLower()
}

function New-SecretKey {
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    return ([System.BitConverter]::ToString($bytes) -replace '-', '').ToLower()
}

# --- virtual environment ----------------------------------------------------

if (-not (Test-Path $VenvPython)) {
    $python = Find-Python
    Write-Host "Creating virtual environment in $VenvDir ..."
    $pyArgs = $python.Args
    & $python.Exe @pyArgs -m venv $VenvDir
    if ($LASTEXITCODE -ne 0) { throw 'Creating the virtual environment failed.' }
}

$previous = @()
if (Test-Path $ComponentsFile) {
    $raw = Get-Content -Raw $ComponentsFile
    if ($raw) { $previous = @($raw.Trim() -split ',' | Where-Object { $KnownComponents.Contains($_) }) }
}
$selected = @(Get-SelectedComponents)

# uninstall the packages of components that are no longer selected
foreach ($name in @($previous | Where-Object { $selected -notcontains $_ })) {
    $reqFile = Join-Path $RepoRoot $KnownComponents[$name].Requirements
    $packages = @(Get-Content $reqFile | Where-Object { $_ -match '^[A-Za-z0-9]' } | ForEach-Object { ($_ -split '[=<>~! \[]')[0] })
    Write-Host "Removing component '$name' ($($packages -join ', ')) ..."
    & $VenvPython -m pip uninstall --disable-pip-version-check -q -y @packages
    if ($name -eq 'browser') {
        Write-Host "  The downloaded Chromium stays in $env:LOCALAPPDATA\ms-playwright (shared with other Playwright"
        Write-Host '  programs); delete that folder yourself if nothing else needs it.'
    }
}
Set-Content -Path $ComponentsFile -Value ($selected -join ',') -Encoding ascii
foreach ($name in $selected) { $Requirements += Join-Path $RepoRoot $KnownComponents[$name].Requirements }

$hash = Get-RequirementsHash
$installed = if (Test-Path $RequirementsStamp) { (Get-Content -Raw $RequirementsStamp).Trim() } else { '' }
if ($Update -or $Setup -or $hash -ne $installed) {
    Write-Host 'Installing requirements (this takes a minute the first time) ...'
    & $VenvPython -m pip install --disable-pip-version-check -q --upgrade pip
    if ($LASTEXITCODE -ne 0) { throw 'Upgrading pip failed.' }
    $pipArgs = @('-m', 'pip', 'install', '--disable-pip-version-check', '-q')
    foreach ($req in $Requirements) { $pipArgs += @('-r', $req) }
    & $VenvPython @pipArgs
    if ($LASTEXITCODE -ne 0) { throw 'Installing the requirements failed.' }

    if ($selected -contains 'browser') {
        Write-Host 'Downloading the headless Chromium browser for Playwright ...'
        & $VenvPython -m playwright install --only-shell chromium
        if ($LASTEXITCODE -ne 0) { throw 'Downloading the headless browser failed.' }
    }
    Set-Content -Path $RequirementsStamp -Value $hash -Encoding ascii

    if ($selected -contains 'mcp') {
        $serverPy = Join-Path $RepoRoot 'searxng_mcp\server.py'
        Write-Host ''
        Write-Host "MCP server installed (components: $($selected -join ', ')). It is not registered anywhere;"
        Write-Host 'to use it from Claude Code, run this yourself:'
        Write-Host "  claude mcp add searxng -- `"$VenvPython`" `"$serverPy`""
        Write-Host ''
    }
}

# --- settings ---------------------------------------------------------------

$SettingsFile = Join-Path $ConfigDir 'settings.yml'
if (-not (Test-Path $SettingsFile)) {
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    $settings = @"
# SearXNG settings, see https://docs.searxng.org/admin/settings/index.html
#
# Only the values you want to change from searx/settings.yml are needed here.

use_default_settings: true

general:
  instance_name: "SearXNG"

search:
  # json is needed by the MCP server (searxng_mcp) and other API clients
  formats:
    - html
    - json

server:
  # Random key created by start-searxng.ps1 -- keep it secret.
  secret_key: "$(New-SecretKey)"
  limiter: false
  image_proxy: true

# valkey:
#   # Only needed for the limiter (bot protection) of a public instance.
#   url: valkey://localhost:6379/0
"@
    # UTF-8 without BOM
    [System.IO.File]::WriteAllText($SettingsFile, $settings, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "Created $SettingsFile"
}

# --- start ------------------------------------------------------------------

$env:SEARXNG_SETTINGS_PATH = $SettingsFile
$env:GRANIAN_INTERFACE = 'wsgi'
$env:GRANIAN_HOST = $BindAddress
$env:GRANIAN_PORT = "$Port"
$env:GRANIAN_WEBSOCKETS = 'false'
$env:GRANIAN_BLOCKING_THREADS = '4'
$env:GRANIAN_PROCESS_NAME = 'searxng'

$shownHost = if ($BindAddress -eq '0.0.0.0') { 'localhost' } else { $BindAddress }
Write-Host "Starting SearXNG on http://${shownHost}:$Port  (settings: $SettingsFile, stop with Ctrl+C)"

Push-Location $RepoRoot
try {
    & (Join-Path $VenvDir 'Scripts\granian.exe') 'searx.webapp:app'
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $owner = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($owner) {
            $name = (Get-Process -Id $owner.OwningProcess -ErrorAction SilentlyContinue).Name
            Write-Warning "Port $Port is already used by '$name' (PID $($owner.OwningProcess)). Try another port, e.g.: .\start-searxng.ps1 -Port 9000"
        }
    }
    exit $code
}
finally {
    Pop-Location
}
