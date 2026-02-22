# v2txt

Voice to Text for Claude via VoiceMode MCP Server.

## Quick Start

### Linux / macOS

```bash
./setup.sh
```

### Windows (Native)

Open PowerShell as Administrator and run:

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1
```

**What the script does:**

1. Checks for / installs **Microsoft Visual C++ Build Tools** (required to compile `simpleaudio`)
2. Installs the **uv** package manager
3. Configures **Claude Desktop** MCP server settings

After setup, restart Claude Desktop and ask Claude to "start a voice conversation".

### Windows (WSL2 - Recommended)

WSL2 provides the most reliable experience on Windows:

```bash
wsl --install           # if WSL not installed yet
# Open WSL terminal, then:
./setup.sh
```

## Troubleshooting

### "simpleaudio failed to build" on Windows

The `voice-mode` package depends on `simpleaudio`, which must be compiled from C source on Python 3.10+. This requires Microsoft Visual C++ Build Tools.

**Fix:** Run `setup.ps1` which handles this automatically, or install manually:

1. Run: `winget install Microsoft.VisualStudio.2022.BuildTools --override "--quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"`
2. Restart your PC
3. Run: `uv cache clean`
4. Restart Claude Desktop

### Claude Desktop config keeps resetting

Claude Desktop (MSIX install) has a known bug where two config files exist and the app may read the wrong one. The `setup.ps1` script writes to **both** locations to work around this.

If the config resets after an update, re-run `setup.ps1`.

### MCP server shows as disconnected

Check the logs at `%APPDATA%\Claude\logs\` for error details. Common causes:

- `simpleaudio` build failure (see above)
- Missing OpenAI API key: re-run `setup.ps1 -OpenAIApiKey "sk-your-key"`
- Network issues preventing package download

## Requirements

- Python 3.10+ (installed automatically by uv if needed)
- OpenAI API key (for speech-to-text and text-to-speech)
- Microphone access
- **Windows only:** Microsoft Visual C++ Build Tools
