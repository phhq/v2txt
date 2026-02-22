#Requires -Version 5.1
<#
.SYNOPSIS
    VoiceMode MCP Setup Script for Windows
.DESCRIPTION
    Installs all dependencies needed for voice-to-text interaction
    with Claude Desktop via the VoiceMode MCP server on Windows.

    This script:
    - Installs the uv package manager
    - Creates a virtual environment with voice-mode + simpleaudio-patched
      (prebuilt Windows wheels, no C++ Build Tools needed)
    - Configures Claude Desktop MCP settings at both standard and MSIX
      config locations (workaround for the known dual-config bug)
.PARAMETER OpenAIApiKey
    Optional OpenAI API key for speech-to-text / text-to-speech services.
.PARAMETER Force
    Force reinstall even if the virtual environment already exists.
#>

param(
    [string]$OpenAIApiKey,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$voicemodeDir = Join-Path $env:USERPROFILE ".voicemode"
$overrideFile = Join-Path $voicemodeDir "override.txt"
$pythonExe = Join-Path $voicemodeDir "Scripts\python.exe"
$voicemodeExe = Join-Path $voicemodeDir "Scripts\voice-mode.exe"

Write-Host "=== VoiceMode MCP Setup for Windows ===" -ForegroundColor Cyan
Write-Host ""

# --- 1. Install uv package manager ---
Write-Host "[1/3] Checking for uv package manager..." -ForegroundColor Yellow

$uvCmd = Get-Command uv -ErrorAction SilentlyContinue

if (-not $uvCmd) {
    Write-Host "  Installing uv..." -ForegroundColor Gray
    try {
        Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        Write-Host "  uv installed successfully." -ForegroundColor Green
    } catch {
        Write-Host "  Failed to install uv: $_" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  uv is already installed." -ForegroundColor Green
}

try {
    $uvVersion = uv --version 2>&1
    Write-Host "  $uvVersion" -ForegroundColor Gray
} catch {}

# --- 2. Create venv and install voice-mode ---
Write-Host "[2/3] Installing voice-mode..." -ForegroundColor Yellow

if ((Test-Path $voicemodeDir) -and $Force) {
    Write-Host "  Removing existing installation (--Force)..." -ForegroundColor Gray
    Remove-Item -Recurse -Force $voicemodeDir
}

if (-not (Test-Path $pythonExe)) {
    Write-Host "  Creating virtual environment at $voicemodeDir..." -ForegroundColor Gray
    uv venv $voicemodeDir --python 3.11
}

# Create override file to skip the original simpleaudio package.
# voice-mode depends on simpleaudio, but that package is unmaintained and has
# no prebuilt wheels for Python 3.10+. We use simpleaudio-patched instead,
# which provides the same simpleaudio module with prebuilt Windows wheels.
# The override makes the simpleaudio requirement evaluate to "never needed"
# so uv won't try to download/build the original.
Set-Content -Path $overrideFile -Value 'simpleaudio ; python_version < "0"'

Write-Host "  Installing voice-mode with simpleaudio-patched (prebuilt wheels)..." -ForegroundColor Gray
Write-Host "  This avoids needing Microsoft Visual C++ Build Tools." -ForegroundColor Gray
uv pip install --python $pythonExe voice-mode simpleaudio-patched --override $overrideFile

if (-not (Test-Path $voicemodeExe)) {
    Write-Host "  ERROR: voice-mode executable not found at $voicemodeExe" -ForegroundColor Red
    Write-Host "  The installation may have failed. Check the output above." -ForegroundColor Red
    exit 1
}

Write-Host "  voice-mode installed successfully." -ForegroundColor Green

# --- 3. Configure Claude Desktop MCP ---
Write-Host "[3/3] Configuring Claude Desktop..." -ForegroundColor Yellow

# Build the MCP server config pointing to the venv executable
$mcpServerEntry = @{
    command = $voicemodeExe
    args    = @()
}

# Add OpenAI API key if provided
if ($OpenAIApiKey) {
    $mcpServerEntry.env = @{
        OPENAI_API_KEY = $OpenAIApiKey
    }
}

# Find all possible Claude Desktop config locations
$configPaths = @()

# Standard install location
$standardPath = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
$configPaths += $standardPath

# MSIX install location (handles the known dual-config bug where Claude Desktop
# reads from a different file than the one "Edit Config" opens)
$localAppData = $env:LOCALAPPDATA
$msixPattern = Join-Path $localAppData "Packages\*Claude*\LocalCache\Roaming\Claude"
$msixDirs = Get-Item $msixPattern -ErrorAction SilentlyContinue
foreach ($dir in $msixDirs) {
    $msixPath = Join-Path $dir.FullName "claude_desktop_config.json"
    if ($msixPath -ne $standardPath) {
        $configPaths += $msixPath
    }
}

$configuredCount = 0
foreach ($configPath in $configPaths) {
    $configDir = Split-Path $configPath -Parent

    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Read existing config or start fresh
    $existingConfig = @{}
    if (Test-Path $configPath) {
        try {
            $content = Get-Content $configPath -Raw -ErrorAction SilentlyContinue
            if ($content) {
                $existingConfig = $content | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if (-not $existingConfig) {
                    $existingConfig = @{}
                }
            }
        } catch {
            $existingConfig = @{}
        }
    }

    # Merge: preserve existing settings and other MCP servers
    if (-not $existingConfig.ContainsKey("mcpServers")) {
        $existingConfig["mcpServers"] = @{}
    }
    $existingConfig["mcpServers"]["voicemode"] = $mcpServerEntry

    try {
        $json = $existingConfig | ConvertTo-Json -Depth 10
        Set-Content -Path $configPath -Value $json -Encoding UTF8
        Write-Host "  Configured: $configPath" -ForegroundColor Green
        $configuredCount++
    } catch {
        Write-Host "  Failed to write: $configPath ($_)" -ForegroundColor Red
    }
}

if ($configuredCount -eq 0) {
    Write-Host "  No Claude Desktop config locations found." -ForegroundColor Red
    Write-Host "  Creating config at default location..." -ForegroundColor Yellow
    $defaultDir = Join-Path $env:APPDATA "Claude"
    if (-not (Test-Path $defaultDir)) {
        New-Item -ItemType Directory -Path $defaultDir -Force | Out-Null
    }
    $json = @{ mcpServers = @{ voicemode = $mcpServerEntry } } | ConvertTo-Json -Depth 10
    Set-Content -Path $standardPath -Value $json -Encoding UTF8
    Write-Host "  Created: $standardPath" -ForegroundColor Green
}

# --- Done ---
Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Installed to: $voicemodeDir" -ForegroundColor Gray
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Restart Claude Desktop" -ForegroundColor White
Write-Host "  2. Ask Claude to 'start a voice conversation'" -ForegroundColor White
Write-Host ""
Write-Host "If the config resets after a Claude Desktop update, re-run:" -ForegroundColor Yellow
Write-Host "  powershell -ExecutionPolicy Bypass -File setup.ps1" -ForegroundColor White
Write-Host ""
Write-Host "To reinstall from scratch:" -ForegroundColor Yellow
Write-Host "  powershell -ExecutionPolicy Bypass -File setup.ps1 -Force" -ForegroundColor White
