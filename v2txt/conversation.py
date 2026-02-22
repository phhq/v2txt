"""Core voice conversation module - captures microphone audio and transcribes to text."""

import speech_recognition as sr
import sys


class VoiceConversation:
    """Manages a voice conversation session with live speech-to-text transcription."""

    def __init__(self, energy_threshold=300, pause_threshold=0.8, language="en-US"):
        self.recognizer = sr.Recognizer()
        self.recognizer.energy_threshold = energy_threshold
        self.recognizer.pause_threshold = pause_threshold
        self.language = language
        self.transcript = []

    def list_microphones(self):
        """Return available microphone device names."""
        return sr.Microphone.list_microphone_names()

    def transcribe_once(self, mic_index=None, timeout=None, phrase_time_limit=None):
        """Listen for a single phrase and return the transcribed text.

        Args:
            mic_index: Microphone device index (None for default).
            timeout: Max seconds to wait for speech to start.
            phrase_time_limit: Max seconds for a single phrase.

        Returns:
            Transcribed text string, or None if nothing was recognized.
        """
        mic_kwargs = {"device_index": mic_index} if mic_index is not None else {}
        with sr.Microphone(**mic_kwargs) as source:
            self.recognizer.adjust_for_ambient_noise(source, duration=0.5)
            try:
                audio = self.recognizer.listen(
                    source, timeout=timeout, phrase_time_limit=phrase_time_limit
                )
            except sr.WaitTimeoutError:
                return None

        try:
            text = self.recognizer.recognize_google(audio, language=self.language)
            self.transcript.append(text)
            return text
        except sr.UnknownValueError:
            return None
        except sr.RequestError as e:
            raise ConnectionError(f"Speech recognition service error: {e}") from e

    def start(self, mic_index=None, timeout=None, phrase_time_limit=None):
        """Run a continuous voice conversation loop, printing transcriptions to stdout.

        Press Ctrl+C to stop.

        Args:
            mic_index: Microphone device index (None for default).
            timeout: Max seconds to wait for speech to start per phrase.
            phrase_time_limit: Max seconds for a single phrase.
        """
        print("Starting voice conversation... (press Ctrl+C to stop)")
        print("Adjusting for ambient noise...\n")

        mic_kwargs = {"device_index": mic_index} if mic_index is not None else {}
        with sr.Microphone(**mic_kwargs) as source:
            self.recognizer.adjust_for_ambient_noise(source, duration=1)
            print("Listening.\n")

            while True:
                try:
                    audio = self.recognizer.listen(
                        source,
                        timeout=timeout,
                        phrase_time_limit=phrase_time_limit,
                    )
                except sr.WaitTimeoutError:
                    continue

                try:
                    text = self.recognizer.recognize_google(
                        audio, language=self.language
                    )
                    self.transcript.append(text)
                    print(f">> {text}")
                    sys.stdout.flush()
                except sr.UnknownValueError:
                    pass
                except sr.RequestError as e:
                    print(f"[error] Recognition service unavailable: {e}")

    def get_transcript(self):
        """Return the full transcript as a single string."""
        return "\n".join(self.transcript)

    def save_transcript(self, path):
        """Write the transcript to a file."""
        with open(path, "w") as f:
            f.write(self.get_transcript())
            f.write("\n")
