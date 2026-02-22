# v2txt

Voice to Text for Claude via VoiceMode MCP Server.

Setup scripts configure voice mode across **all Claude clients** — Desktop,
Code CLI, and web sessions — so you can say "start a voice conversation"
anywhere.

## Quick Start

### Linux / macOS

```bash
./setup.sh
```

### Windows (Native)

Open PowerShell and run:

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1
```

### Windows (WSL2)

```bash
wsl --install           # if WSL not installed yet
# Open WSL terminal, then:
./setup.sh
```

## What gets configured

Each setup script registers the VoiceMode MCP server with every Claude client
it can find:

| Client | Windows (`setup.ps1`) | Linux / macOS (`setup.sh`) |
|---|---|---|
| **Claude Desktop** | `claude_desktop_config.json` (standard + MSIX) | `claude_desktop_config.json` (macOS) |
| **Claude Code CLI** | `claude mcp add --scope user` | `claude mcp add --scope user` |
| **Claude Code Web** | Same as CLI (user-scoped) | Same as CLI (user-scoped) |

On Windows, a virtual environment is created at `~\.voicemode` with
`voice-mode` and `simpleaudio-patched` (prebuilt Windows wheels — **no C++
Build Tools needed**). The Claude Desktop config is written to both standard
and MSIX config paths to work around the known dual-config bug.

After setup, restart Claude Desktop and ask Claude to "start a voice
conversation" in any session.

## Troubleshooting

### Claude Desktop config keeps resetting

Claude Desktop (MSIX install) has a known bug where two config files exist
and the app reads the wrong one. The `setup.ps1` script writes to **both**
locations. If the config resets after an update, re-run `setup.ps1`.

### MCP server shows as disconnected

Check the logs at `%APPDATA%\Claude\logs\` for error details. Common causes:

- Missing OpenAI API key: re-run `setup.ps1 -OpenAIApiKey "sk-your-key"`
- Stale install: re-run `setup.ps1 -Force` to reinstall from scratch
- Network issues preventing package download

### Voice mode not available in Claude Code

If you installed Claude Code after running setup, register manually:

```bash
claude mcp add --scope user voicemode -- uvx --refresh voice-mode
```

## Requirements

- Python 3.10+ (installed automatically by uv if needed)
- OpenAI API key (for speech-to-text and text-to-speech)
- Microphone access
