# v2txt

Voice to Text for Claude via VoiceMode MCP Server.

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

The script creates a virtual environment at `~\.voicemode` with `voice-mode` and
`simpleaudio-patched` (prebuilt Windows wheels — **no C++ Build Tools needed**).
It then configures Claude Desktop's MCP server settings, writing to both config
file locations to work around the known MSIX dual-config bug.

After setup, restart Claude Desktop and ask Claude to "start a voice conversation".

### Windows (WSL2)

WSL2 is also supported and avoids native Windows audio quirks:

```bash
wsl --install           # if WSL not installed yet
# Open WSL terminal, then:
./setup.sh
```

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

## Requirements

- Python 3.10+ (installed automatically by uv if needed)
- OpenAI API key (for speech-to-text and text-to-speech)
- Microphone access
