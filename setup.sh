#!/usr/bin/env bash
set -euo pipefail

# VoiceMode MCP Setup Script for Claude Code
# This script installs all dependencies needed for voice-to-text
# interaction with Claude Code via the VoiceMode MCP server.

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
  *)
    echo "Unsupported OS: $OS"
    echo "On Windows, use WSL and run this script from there."
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

# Register with Claude Code
echo ""
echo "Registering VoiceMode MCP server with Claude Code..."

if [[ "$OS" == "Darwin"* ]]; then
  # macOS needs webrtcvad with pinned setuptools for voice activity detection
  claude mcp add --scope user voicemode -- \
    uvx --refresh --with webrtcvad --with "setuptools<71" voice-mode
else
  claude mcp add --scope user voicemode -- \
    uvx --refresh voice-mode
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To start a voice conversation, run:"
echo "  claude"
echo ""
echo "Then ask Claude to 'start a voice conversation' or use the converse tool."
echo ""
echo "NOTE: Make sure your terminal app has microphone permissions."
echo "  - macOS: System Settings > Privacy & Security > Microphone > enable your terminal"
echo "  - Linux: Ensure PulseAudio is running (pulseaudio --start)"
