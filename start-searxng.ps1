# SPDX-License-Identifier: AGPL-3.0-or-later
<#
.SYNOPSIS
    Install (if needed) and start SearXNG natively on Windows.

.DESCRIPTION
    On first run this script

    - creates a Python virtual environment in .venv and installs the
      requirements (again whenever a requirements file changes),
    - creates a settings file with a random, permanent secret key in
      %APPDATA%\searxng\settings.yml (only if it does not exist yet).

    Then it starts SearXNG with the Granian web server, the same server the
    official SearXNG container uses.

.PARAMETER Port
    TCP port to listen on (default 8888).

.PARAMETER BindAddress
    Address to listen on (default 127.0.0.1, only this computer).  Use 0.0.0.0
    to make SearXNG reachable from other devices in your network.

.PARAMETER ConfigDir
    Folder holding settings.yml (default %APPDATA%\searxng).

.PARAMETER Update
    Reinstall the requirements even if they did not change.

.EXAMPLE
    .\start-searxng.ps1

.EXAMPLE
    .\start-searxng.ps1 -Port 9000 -BindAddress 0.0.0.0
#>

[CmdletBinding()]
param(
    [int]$Port = 8888,
    [string]$BindAddress = '127.0.0.1',
    [string]$ConfigDir = (Join-Path $env:APPDATA 'searxng'),
    [switch]$Update
)

# Not 'Stop': Windows PowerShell 5.1 would turn harmless stderr output of pip
# and granian into terminating errors.  Native calls check $LASTEXITCODE.
$ErrorActionPreference = 'Continue'
$RepoRoot = $PSScriptRoot
$VenvDir = Join-Path $RepoRoot '.venv'
$VenvPython = Join-Path $VenvDir 'Scripts\python.exe'
$Requirements = @('requirements.txt', 'requirements-server.txt') | ForEach-Object { Join-Path $RepoRoot $_ }
$RequirementsStamp = Join-Path $VenvDir '.sxng-requirements.sha256'

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

$hash = Get-RequirementsHash
$installed = if (Test-Path $RequirementsStamp) { (Get-Content -Raw $RequirementsStamp).Trim() } else { '' }
if ($Update -or $hash -ne $installed) {
    Write-Host 'Installing requirements (this takes a minute the first time) ...'
    & $VenvPython -m pip install --disable-pip-version-check -q --upgrade pip
    if ($LASTEXITCODE -ne 0) { throw 'Upgrading pip failed.' }
    $pipArgs = @('-m', 'pip', 'install', '--disable-pip-version-check', '-q')
    foreach ($req in $Requirements) { $pipArgs += @('-r', $req) }
    & $VenvPython @pipArgs
    if ($LASTEXITCODE -ne 0) { throw 'Installing the requirements failed.' }
    Set-Content -Path $RequirementsStamp -Value $hash -Encoding ascii
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
