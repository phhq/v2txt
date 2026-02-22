#Requires -Version 5.1
<#
.SYNOPSIS
    VoiceMode MCP Setup Script for Windows
.DESCRIPTION
    Installs all dependencies needed for voice-to-text interaction
    with Claude Desktop via the VoiceMode MCP server on Windows.

    This script handles:
    - Installing Microsoft Visual C++ Build Tools (required to compile simpleaudio)
    - Installing the uv package manager
    - Configuring Claude Desktop's MCP server settings
    - Working around the MSIX dual-config file bug
#>

param(
    [string]$OpenAIApiKey,
    [switch]$SkipBuildTools,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== VoiceMode MCP Setup for Windows ===" -ForegroundColor Cyan
Write-Host ""

# --- 1. Check for Visual C++ Build Tools ---
Write-Host "[1/4] Checking for Visual C++ Build Tools..." -ForegroundColor Yellow

$vsWherePath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasBuildTools = $false

if (Test-Path $vsWherePath) {
    $installations = & $vsWherePath -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($installations) {
        $hasBuildTools = $true
        Write-Host "  Visual C++ Build Tools found." -ForegroundColor Green
    }
}

if (-not $hasBuildTools -and -not $SkipBuildTools) {
    Write-Host "  Visual C++ Build Tools not found. Installing..." -ForegroundColor Yellow
    Write-Host "  This is required to compile the 'simpleaudio' audio library." -ForegroundColor Gray
    Write-Host ""

    # Check if winget is available
    $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetAvailable) {
        Write-Host "  Installing via winget (this may take several minutes)..." -ForegroundColor Gray
        try {
            winget install Microsoft.VisualStudio.2022.BuildTools `
                --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" `
                --accept-package-agreements --accept-source-agreements
            Write-Host "  Visual C++ Build Tools installed successfully." -ForegroundColor Green
            Write-Host ""
            Write-Host "  IMPORTANT: You should restart your computer before continuing." -ForegroundColor Red
            Write-Host "  After restarting, run this script again with -SkipBuildTools" -ForegroundColor Red
            Write-Host ""
            $restart = Read-Host "Restart now? (y/n)"
            if ($restart -eq 'y') {
                Restart-Computer -Force
            }
            exit 0
        } catch {
            Write-Host "  Failed to install via winget: $_" -ForegroundColor Red
            Write-Host "  Please install manually:" -ForegroundColor Yellow
            Write-Host "    1. Download from: https://visualstudio.microsoft.com/visual-cpp-build-tools/" -ForegroundColor White
            Write-Host "    2. Select 'Desktop development with C++'" -ForegroundColor White
            Write-Host "    3. Install, restart PC, then re-run this script with -SkipBuildTools" -ForegroundColor White
            exit 1
        }
    } else {
        Write-Host "  winget not available. Please install Visual C++ Build Tools manually:" -ForegroundColor Yellow
        Write-Host "    1. Download from: https://visualstudio.microsoft.com/visual-cpp-build-tools/" -ForegroundColor White
        Write-Host "    2. Select 'Desktop development with C++'" -ForegroundColor White
        Write-Host "    3. Install, restart PC, then re-run this script with -SkipBuildTools" -ForegroundColor White
        exit 1
    }
} elseif (-not $hasBuildTools -and $SkipBuildTools) {
    Write-Host "  Skipping build tools check (user requested)." -ForegroundColor Gray
}

# --- 2. Install uv package manager ---
Write-Host "[2/4] Checking for uv package manager..." -ForegroundColor Yellow

$uvPath = Get-Command uvx -ErrorAction SilentlyContinue
if (-not $uvPath) {
    $uvPath = Get-Command uv -ErrorAction SilentlyContinue
}

if (-not $uvPath) {
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

# Show version
try {
    $uvVersion = uv --version 2>&1
    Write-Host "  $uvVersion" -ForegroundColor Gray
} catch {}

# --- 3. Clear uv cache (to force fresh builds) ---
Write-Host "[3/4] Clearing uv cache..." -ForegroundColor Yellow
try {
    uv cache clean 2>$null
    Write-Host "  Cache cleared." -ForegroundColor Green
} catch {
    Write-Host "  Could not clear cache (non-fatal)." -ForegroundColor Gray
}

# --- 4. Configure Claude Desktop MCP ---
Write-Host "[4/4] Configuring Claude Desktop..." -ForegroundColor Yellow

# Build the MCP server config
$mcpConfig = @{
    mcpServers = @{
        voicemode = @{
            command = "uvx"
            args    = @("--refresh", "voice-mode")
        }
    }
}

# Add OpenAI API key if provided
if ($OpenAIApiKey) {
    $mcpConfig.mcpServers.voicemode.env = @{
        OPENAI_API_KEY = $OpenAIApiKey
    }
}

# Find all possible Claude Desktop config locations
$configPaths = @()

# Standard install location
$standardPath = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
$configPaths += $standardPath

# MSIX install location (handles the known dual-config bug)
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

    # Create directory if it doesn't exist
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Read existing config or create new one
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

    # Merge MCP servers config (preserve existing servers and other settings)
    if (-not $existingConfig.ContainsKey("mcpServers")) {
        $existingConfig["mcpServers"] = @{}
    }
    $existingConfig["mcpServers"]["voicemode"] = $mcpConfig.mcpServers.voicemode

    # Write config
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
    $json = $mcpConfig | ConvertTo-Json -Depth 10
    Set-Content -Path $standardPath -Value $json -Encoding UTF8
    Write-Host "  Created: $standardPath" -ForegroundColor Green
}

# --- Done ---
Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Restart Claude Desktop" -ForegroundColor White
Write-Host "  2. Open a conversation and ask Claude to 'start a voice conversation'" -ForegroundColor White
Write-Host ""
Write-Host "If the config keeps getting overwritten after reboot:" -ForegroundColor Yellow
Write-Host "  - Run this script again after each Claude Desktop update" -ForegroundColor White
Write-Host "  - Or add a Scheduled Task to run this script at logon" -ForegroundColor White
Write-Host ""
Write-Host "Troubleshooting:" -ForegroundColor Yellow
Write-Host "  - If simpleaudio fails to build, ensure you restarted after installing Build Tools" -ForegroundColor White
Write-Host "  - Check logs at: %APPDATA%\Claude\logs\" -ForegroundColor White
Write-Host "  - Run 'uvx voice-mode --help' to test the server manually" -ForegroundColor White
