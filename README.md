# v2txt

Voice to Text - Start a voice conversation and get live transcriptions.

## Install

```bash
pip install -r requirements.txt
```

On Linux you may also need the PortAudio system library:

```bash
sudo apt-get install portaudio19-dev
```

## Usage

Start a voice conversation (uses your default microphone):

```bash
python -m v2txt.cli start
```

List available microphone devices:

```bash
python -m v2txt.cli devices
```

Pick a specific microphone and save the transcript:

```bash
python -m v2txt.cli start --mic 1 --save transcript.txt
```

### Options

| Flag             | Description                              |
|------------------|------------------------------------------|
| `--mic INDEX`    | Microphone device index                  |
| `--language CODE`| Recognition language (default: `en-US`)  |
| `--timeout SECS` | Seconds to wait for speech to begin      |
| `--phrase-limit SECS` | Max seconds per phrase              |
| `--save FILE`    | Save transcript to file when session ends|

Press **Ctrl+C** to end the conversation.
