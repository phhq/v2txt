#Requires -Version 5.1
<#
.SYNOPSIS
    VoiceMode MCP Setup Script for Windows
.DESCRIPTION
    Installs all dependencies needed for voice-to-text interaction
    with Claude via the VoiceMode MCP server on Windows.

    This script:
    - Installs the uv package manager
    - Creates a virtual environment with voice-mode + simpleaudio-patched
      (prebuilt Windows wheels, no C++ Build Tools needed)
    - Configures Claude Desktop MCP settings at both standard and MSIX
      config locations (workaround for the known dual-config bug)
    - Registers with Claude Code for CLI and web session support
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
Write-Host "[1/4] Checking for uv package manager..." -ForegroundColor Yellow

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
Write-Host "[2/4] Installing voice-mode..." -ForegroundColor Yellow

if (-not (Test-Path $pythonExe) -or $Force) {
    Write-Host "  Creating virtual environment at $voicemodeDir..." -ForegroundColor Gray
    uv venv $voicemodeDir --python 3.11 --clear
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
Write-Host "[3/4] Configuring Claude Desktop..." -ForegroundColor Yellow

# Build the voicemode MCP server entry
$voicemodeEntry = [ordered]@{
    command = $voicemodeExe
    args    = @()
}
if ($OpenAIApiKey) {
    $voicemodeEntry["env"] = [ordered]@{
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

# UTF-8 without BOM — critical because Claude Desktop's JSON parser rejects the
# byte-order mark that PowerShell 5.1's "Set-Content -Encoding UTF8" writes.
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

$configuredCount = 0
foreach ($configPath in $configPaths) {
    $configDir = Split-Path $configPath -Parent

    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Read existing config, preserving other settings (e.g. preferences) and MCP servers.
    # We avoid -AsHashtable because it is not available on PowerShell 5.1.
    $existingConfig = $null
    if (Test-Path $configPath) {
        try {
            $raw = [System.IO.File]::ReadAllText($configPath)
            # Strip BOM if present from a prior write
            $raw = $raw.TrimStart([char]0xFEFF)
            if ($raw.Trim()) {
                $existingConfig = $raw | ConvertFrom-Json -ErrorAction Stop
            }
        } catch {
            Write-Host "  Warning: could not parse existing config, creating fresh." -ForegroundColor DarkYellow
        }
    }

    # Build merged config: keep every existing top-level key, update mcpServers
    $merged = [ordered]@{}

    if ($existingConfig) {
        foreach ($prop in $existingConfig.PSObject.Properties) {
            if ($prop.Name -ne "mcpServers") {
                $merged[$prop.Name] = $prop.Value
            }
        }
    }

    # Preserve other MCP servers that aren't voicemode
    $mcpServers = [ordered]@{}
    if ($existingConfig -and
        ($existingConfig | Get-Member -Name mcpServers -MemberType NoteProperty) -and
        $existingConfig.mcpServers) {
        foreach ($prop in $existingConfig.mcpServers.PSObject.Properties) {
            if ($prop.Name -ne "voicemode") {
                $mcpServers[$prop.Name] = $prop.Value
            }
        }
    }
    $mcpServers["voicemode"] = $voicemodeEntry
    $merged["mcpServers"] = $mcpServers

    try {
        $json = [PSCustomObject]$merged | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($configPath, $json, $utf8NoBom)
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
    $json = [PSCustomObject][ordered]@{
        mcpServers = [ordered]@{ voicemode = $voicemodeEntry }
    } | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($standardPath, $json, $utf8NoBom)
    Write-Host "  Created: $standardPath" -ForegroundColor Green
}

# --- 4. Register with Claude Code (CLI & Web) ---
Write-Host "[4/4] Configuring Claude Code..." -ForegroundColor Yellow

$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCmd) {
    try {
        claude mcp add --scope user voicemode -- $voicemodeExe 2>&1 | Out-Null
        Write-Host "  Registered voicemode with Claude Code (CLI & web sessions)." -ForegroundColor Green
    } catch {
        Write-Host "  Warning: could not register with Claude Code: $_" -ForegroundColor DarkYellow
        Write-Host "  You can manually run:" -ForegroundColor Gray
        Write-Host "    claude mcp add --scope user voicemode -- $voicemodeExe" -ForegroundColor Gray
    }
} else {
    Write-Host "  Claude Code CLI not found (optional)." -ForegroundColor Gray
    Write-Host "  To enable voice in CLI & web sessions, install Claude Code and run:" -ForegroundColor Gray
    Write-Host "    claude mcp add --scope user voicemode -- $voicemodeExe" -ForegroundColor Gray
}

# --- Done ---
Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Installed to: $voicemodeDir" -ForegroundColor Gray
Write-Host ""
Write-Host "Voice mode is now available in:" -ForegroundColor Yellow
Write-Host "  - Claude Desktop (restart required)" -ForegroundColor White
if ($claudeCmd) {
    Write-Host "  - Claude Code CLI (claude command)" -ForegroundColor White
    Write-Host "  - Claude Code Web (claude.ai/code)" -ForegroundColor White
} else {
    Write-Host "  - Claude Code CLI/Web (requires 'claude' CLI — see above)" -ForegroundColor DarkGray
}
Write-Host ""
Write-Host "Ask Claude to 'start a voice conversation' in any session." -ForegroundColor White
Write-Host ""
Write-Host "If the config resets after a Claude Desktop update, re-run:" -ForegroundColor Yellow
Write-Host "  powershell -ExecutionPolicy Bypass -File setup.ps1" -ForegroundColor White
Write-Host ""
Write-Host "To reinstall from scratch:" -ForegroundColor Yellow
Write-Host "  powershell -ExecutionPolicy Bypass -File setup.ps1 -Force" -ForegroundColor White
