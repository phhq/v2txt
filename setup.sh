#!/usr/bin/env bash
set -euo pipefail

# VoiceMode MCP Setup Script
# This script installs all dependencies needed for voice-to-text
# interaction with Claude via the VoiceMode MCP server.
# Configures both Claude Code (CLI & web) and Claude Desktop.

echo "=== VoiceMode MCP Setup ==="
echo ""

# Detect OS
OS="$(uname -s)"

case "$OS" in
  Linux*)
    echo "Detected Linux"
    if command -v apt-get &> /dev/null; then
      echo "Installing system dependencies via apt..."
      sudo apt update
      sudo apt install -y \
        ffmpeg \
        gcc \
        libasound2-dev \
        libasound2-plugins \
        libportaudio2 \
        portaudio19-dev \
        pulseaudio \
        pulseaudio-utils \
        python3-dev
    elif command -v dnf &> /dev/null; then
      echo "Installing system dependencies via dnf..."
      sudo dnf install -y \
        alsa-lib-devel \
        ffmpeg \
        gcc \
        portaudio \
        portaudio-devel \
        python3-devel
    else
      echo "Unsupported package manager. Please install portaudio, ffmpeg, and pulseaudio manually."
      exit 1
    fi
    ;;
  Darwin*)
    echo "Detected macOS"
    if ! command -v brew &> /dev/null; then
      echo "Homebrew not found. Install it from https://brew.sh"
      exit 1
    fi
    echo "Installing system dependencies via Homebrew..."
    brew install ffmpeg portaudio
    ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "Detected Windows (Git Bash / MSYS2)"
    echo ""
    echo "Native Windows requires a different setup process."
    echo "Please run the PowerShell script instead:"
    echo ""
    echo "  powershell -ExecutionPolicy Bypass -File setup.ps1"
    echo ""
    echo "Or use WSL2 for the best experience:"
    echo "  wsl --install"
    echo "  # Then run this script from within WSL"
    exit 1
    ;;
  *)
    echo "Unsupported OS: $OS"
    echo "On Windows, use WSL and run this script from there,"
    echo "or use setup.ps1 for native Windows support."
    exit 1
    ;;
esac

echo ""

# Install uv if not present
if ! command -v uv &> /dev/null; then
  echo "Installing uv package manager..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi

echo "uv version: $(uv --version)"

# Run the VoiceMode installer
echo ""
echo "Running VoiceMode installer..."
uvx voice-mode-install

# Register with Claude Code (CLI & Web)
echo ""
echo "Registering VoiceMode MCP server with Claude Code..."

if command -v claude &> /dev/null; then
  if [[ "$OS" == "Darwin"* ]]; then
    # macOS needs webrtcvad with pinned setuptools for voice activity detection
    claude mcp add --scope user voicemode -- \
      uvx --refresh --with webrtcvad --with "setuptools<71" voice-mode
  else
    claude mcp add --scope user voicemode -- \
      uvx --refresh voice-mode
  fi
  echo "  Registered voicemode with Claude Code (CLI & web sessions)."
else
  echo "  Claude Code CLI not found (optional)."
  echo "  To enable voice in CLI & web sessions, install Claude Code and run:"
  echo "    claude mcp add --scope user voicemode -- uvx --refresh voice-mode"
fi

# Configure Claude Desktop (if applicable)
echo ""
echo "Configuring Claude Desktop..."

configure_desktop_config() {
  local config_path="$1"
  local config_dir
  config_dir="$(dirname "$config_path")"

  mkdir -p "$config_dir"

  # Build the voicemode MCP entry based on OS
  local vm_command="uvx"
  local vm_args
  if [[ "$OS" == "Darwin"* ]]; then
    vm_args='["--refresh", "--with", "webrtcvad", "--with", "setuptools<71", "voice-mode"]'
  else
    vm_args='["--refresh", "voice-mode"]'
  fi

  if [ -f "$config_path" ]; then
    # Merge into existing config, preserving other settings and MCP servers
    if command -v python3 &> /dev/null; then
      python3 -c "
import json, sys
try:
    with open('$config_path', 'r') as f:
        config = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    config = {}
servers = config.get('mcpServers', {})
servers['voicemode'] = {'command': '$vm_command', 'args': $vm_args}
config['mcpServers'] = servers
with open('$config_path', 'w') as f:
    json.dump(config, f, indent=2)
"
      echo "  Configured: $config_path"
    else
      echo "  Warning: python3 not found, cannot merge config at $config_path"
    fi
  else
    # Create fresh config
    cat > "$config_path" << JSONEOF
{
  "mcpServers": {
    "voicemode": {
      "command": "$vm_command",
      "args": $vm_args
    }
  }
}
JSONEOF
    echo "  Created: $config_path"
  fi
}

desktop_configured=false

if [[ "$OS" == "Darwin"* ]]; then
  config_path="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
  configure_desktop_config "$config_path"
  desktop_configured=true
elif [[ "$OS" == "Linux"* ]]; then
  # Linux: check XDG config and ~/.config paths for Claude Desktop
  xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
  config_path="$xdg_config/Claude/claude_desktop_config.json"
  if [ -d "$xdg_config/Claude" ] || [ -f "$config_path" ]; then
    configure_desktop_config "$config_path"
    desktop_configured=true
  else
    echo "  Claude Desktop config directory not found (not installed or not applicable)."
  fi
fi

echo ""
echo "=== Setup Complete ==="
echo ""

echo "Voice mode is now available in:"
if command -v claude &> /dev/null; then
  echo "  - Claude Code CLI (claude command)"
  echo "  - Claude Code Web (claude.ai/code)"
fi
if [ "$desktop_configured" = true ]; then
  echo "  - Claude Desktop (restart required)"
fi
echo ""
echo "Ask Claude to 'start a voice conversation' in any session."
echo ""
echo "NOTE: Make sure your app has microphone permissions."
echo "  - macOS: System Settings > Privacy & Security > Microphone > enable your terminal"
echo "  - Linux: Ensure PulseAudio is running (pulseaudio --start)"
