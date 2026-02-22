"""CLI entry point for v2txt."""

import argparse
import sys

from v2txt.conversation import VoiceConversation


def main():
    parser = argparse.ArgumentParser(
        prog="v2txt",
        description="Voice to Text - Start a voice conversation and get live transcriptions.",
    )
    subparsers = parser.add_subparsers(dest="command")

    # --- start command ---
    start_parser = subparsers.add_parser(
        "start", help="Start a voice conversation with live transcription"
    )
    start_parser.add_argument(
        "--mic",
        type=int,
        default=None,
        help="Microphone device index (omit for default mic)",
    )
    start_parser.add_argument(
        "--language",
        type=str,
        default="en-US",
        help="Language code for recognition (default: en-US)",
    )
    start_parser.add_argument(
        "--timeout",
        type=float,
        default=None,
        help="Seconds to wait for speech before giving up (default: wait forever)",
    )
    start_parser.add_argument(
        "--phrase-limit",
        type=float,
        default=None,
        help="Max seconds per phrase (default: no limit)",
    )
    start_parser.add_argument(
        "--save",
        type=str,
        default=None,
        metavar="FILE",
        help="Save transcript to FILE when the session ends",
    )

    # --- devices command ---
    subparsers.add_parser("devices", help="List available microphone devices")

    args = parser.parse_args()

    if args.command is None:
        parser.print_help()
        sys.exit(0)

    if args.command == "devices":
        names = VoiceConversation().list_microphones()
        if not names:
            print("No microphone devices found.")
            sys.exit(1)
        for i, name in enumerate(names):
            print(f"  [{i}] {name}")
        sys.exit(0)

    if args.command == "start":
        conv = VoiceConversation(language=args.language)
        try:
            conv.start(
                mic_index=args.mic,
                timeout=args.timeout,
                phrase_time_limit=args.phrase_limit,
            )
        except KeyboardInterrupt:
            print("\n\nConversation ended.")
            if conv.transcript:
                print(f"\nTranscribed {len(conv.transcript)} phrase(s).")
            if args.save:
                conv.save_transcript(args.save)
                print(f"Transcript saved to {args.save}")
        except OSError as e:
            print(f"Error: {e}", file=sys.stderr)
            print(
                "Make sure a microphone is connected and PyAudio is installed correctly.",
                file=sys.stderr,
            )
            sys.exit(1)


if __name__ == "__main__":
    main()
