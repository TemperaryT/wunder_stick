#!/usr/bin/env python3
"""
Compute audio-based sync offsets between multiple videos vs a master track.

Usage:
    python audio_sync.py \
        --master pixel9.mp4 \
        --targets samsung_a15.mp4,gopro_max.360 \
        --out sync_offsets.json

Output (sync_offsets.json):
    {
        "pixel9": 0.0,          # master is always 0
        "samsung_a15": 3.72,    # samsung starts 3.72s AFTER pixel9 master
        "gopro_max": -1.15      # gopro starts 1.15s BEFORE pixel9 master
    }

    A positive offset means the target started LATER than master.
    To align: trim target with -ss <offset> (positive) or add silence at start (negative).

Notes:
    - Negative offsets (target started before master) mean you trim the target start.
    - Offsets beyond ±60s should be treated with suspicion — check manually.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from scipy import signal


SAMPLE_RATE = 16000  # 16kHz mono is sufficient for correlation


def extract_audio(video_path: str, out_wav: str, duration: float | None = None) -> bool:
    cmd = [
        "ffmpeg", "-y", "-i", video_path,
        "-map", "a:0",       # first audio stream
        "-ac", "1",          # mono
        "-ar", str(SAMPLE_RATE),
        "-vn",
    ]
    if duration:
        cmd += ["-t", str(duration)]
    cmd.append(out_wav)
    result = subprocess.run(cmd, capture_output=True)
    return result.returncode == 0


def load_wav_mono(wav_path: str) -> np.ndarray:
    import wave
    with wave.open(wav_path, "rb") as f:
        raw = f.readframes(f.getnframes())
        arr = np.frombuffer(raw, dtype=np.int16).astype(np.float32)
    return arr


def xcorr_offset(ref: np.ndarray, target: np.ndarray) -> float:
    """Return offset in seconds: positive = target starts later than ref."""
    corr = signal.correlate(ref, target, mode="full")
    lag = np.argmax(np.abs(corr)) - (len(target) - 1)
    return lag / SAMPLE_RATE


def camera_key(path: str) -> str:
    return Path(path).stem.split(".")[0]


def main():
    parser = argparse.ArgumentParser(description="Audio cross-correlation sync for multi-camera videos")
    parser.add_argument("--master", required=True, help="Master video file (reference clock)")
    parser.add_argument("--targets", required=True, help="Comma-separated list of target video files")
    parser.add_argument("--out", default="01_edits/sync_offsets.json", help="Output JSON file")
    parser.add_argument("--duration", type=float, default=120.0,
                        help="Seconds of audio to use for correlation (default 120s — enough to find sync)")
    parser.add_argument("--master-key", default=None, help="Override key name for master in output JSON")
    args = parser.parse_args()

    targets = [t.strip() for t in args.targets.split(",") if t.strip()]
    master_key = args.master_key or camera_key(args.master)

    offsets = {master_key: 0.0}

    with tempfile.TemporaryDirectory() as tmpdir:
        # Extract master audio
        master_wav = os.path.join(tmpdir, "master.wav")
        print(f"Extracting master audio from {args.master}...")
        if not extract_audio(args.master, master_wav, args.duration):
            print("ERROR: Failed to extract audio from master.", file=sys.stderr)
            sys.exit(1)
        ref_audio = load_wav_mono(master_wav)

        for target in targets:
            key = camera_key(target)
            target_wav = os.path.join(tmpdir, f"{key}.wav")
            print(f"Extracting audio from {target}...")
            if not extract_audio(target, target_wav, args.duration):
                print(f"WARNING: Failed to extract audio from {target}. Skipping.", file=sys.stderr)
                offsets[key] = None
                continue

            tgt_audio = load_wav_mono(target_wav)
            offset = xcorr_offset(ref_audio, tgt_audio)
            offsets[key] = round(float(offset), 4)
            print(f"  {key}: offset = {offset:+.4f}s vs {master_key}")
            if abs(offset) > 60:
                print(f"  WARNING: offset >60s — verify manually before trimming.", file=sys.stderr)

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w") as f:
        json.dump(offsets, f, indent=2)
    print(f"\nSync offsets written to {out_path}")
    print(json.dumps(offsets, indent=2))


if __name__ == "__main__":
    main()
