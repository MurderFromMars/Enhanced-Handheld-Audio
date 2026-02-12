#!/usr/bin/env python3
"""
generate_ir.py — Synthesize spatial audio impulse responses for PipeWire convolver.

Generates a 4-channel WAV containing:
  ch 0: Direct L→L  (main signal + early reflections)
  ch 1: Direct R→R  (mirror of ch 0)
  ch 2: Cross  L→R  (delayed, filtered crossfeed)
  ch 3: Cross  R→L  (mirror of ch 2)

The crossfeed simulates speaker-to-opposite-ear path (interaural time delay +
head shadow filtering), and the early reflections create a sense of room width.

Usage:
  python3 generate_ir.py                    # default "medium" spatial effect
  python3 generate_ir.py --intensity light  # subtle
  python3 generate_ir.py --intensity heavy  # aggressive
  python3 generate_ir.py -o my_ir.wav       # custom output path
"""

import argparse
import struct
import math
import os

SAMPLE_RATE = 48000
IR_DURATION_MS = 80  # 80ms is plenty for early reflections without reverb tail
IR_SAMPLES = int(SAMPLE_RATE * IR_DURATION_MS / 1000)
NUM_CHANNELS = 4

# ── Intensity presets ────────────────────────────────────────────────────────
# Each preset defines:
#   direct_gain    : amplitude of the main impulse (t=0)
#   reflections    : list of (delay_ms, gain) for early reflections on direct path
#   cross_gain     : amplitude of crossfeed signal
#   cross_delay_ms : interaural time delay for crossfeed
#   cross_lpf_freq : low-pass cutoff simulating head shadow (Hz)
#   cross_reflections: early reflections on the crossfeed path

PRESETS = {
    "light": {
        "direct_gain": 1.0,
        "reflections": [
            (1.8, 0.08),
            (5.2, 0.05),
            (11.0, 0.03),
        ],
        "cross_gain": 0.15,
        "cross_delay_ms": 0.25,
        "cross_lpf_freq": 3000,
        "cross_reflections": [
            (3.5, 0.04),
            (8.0, 0.02),
        ],
    },
    "medium": {
        "direct_gain": 1.0,
        "reflections": [
            (1.5, 0.12),
            (3.8, 0.09),
            (6.5, 0.06),
            (10.2, 0.04),
            (15.0, 0.025),
        ],
        "cross_gain": 0.25,
        "cross_delay_ms": 0.30,
        "cross_lpf_freq": 2500,
        "cross_reflections": [
            (2.8, 0.06),
            (6.0, 0.04),
            (12.0, 0.02),
        ],
    },
    "heavy": {
        "direct_gain": 1.0,
        "reflections": [
            (1.2, 0.18),
            (3.0, 0.14),
            (5.5, 0.10),
            (8.0, 0.07),
            (12.0, 0.05),
            (18.0, 0.035),
            (25.0, 0.02),
        ],
        "cross_gain": 0.35,
        "cross_delay_ms": 0.35,
        "cross_lpf_freq": 2000,
        "cross_reflections": [
            (2.2, 0.10),
            (5.0, 0.06),
            (9.0, 0.04),
            (15.0, 0.02),
        ],
    },
}


def ms_to_samples(ms):
    return int(ms * SAMPLE_RATE / 1000)


def apply_lpf_to_impulse(samples, cutoff_hz, sample_rate):
    """
    Apply a simple single-pole IIR low-pass filter in-place.
    Simulates head shadow on crossfeed path.
    """
    rc = 1.0 / (2.0 * math.pi * cutoff_hz)
    dt = 1.0 / sample_rate
    alpha = dt / (rc + dt)
    prev = 0.0
    for i in range(len(samples)):
        prev = prev + alpha * (samples[i] - prev)
        samples[i] = prev
    return samples


def generate_channel(gain, reflections, is_cross=False, cross_delay_ms=0,
                     cross_lpf_freq=None):
    """Generate a single IR channel as a list of float samples."""
    buf = [0.0] * IR_SAMPLES

    # Main impulse
    delay_samples = ms_to_samples(cross_delay_ms) if is_cross else 0
    if delay_samples < IR_SAMPLES:
        buf[delay_samples] = gain

    # Early reflections — alternate polarity for natural sound
    for i, (delay_ms, ref_gain) in enumerate(reflections):
        total_delay = ms_to_samples(delay_ms + (cross_delay_ms if is_cross else 0))
        if total_delay < IR_SAMPLES:
            polarity = 1.0 if i % 2 == 0 else -1.0
            buf[total_delay] += ref_gain * polarity

    # Apply head shadow filter to crossfeed channels
    if is_cross and cross_lpf_freq:
        buf = apply_lpf_to_impulse(buf, cross_lpf_freq, SAMPLE_RATE)

    return buf


def write_wav(filepath, channels, sample_rate):
    """
    Write a multi-channel WAV file (IEEE 754 32-bit float).
    channels: list of lists, each inner list is one channel of float samples.
    """
    num_channels = len(channels)
    num_samples = len(channels[0])
    bits_per_sample = 32
    byte_rate = sample_rate * num_channels * (bits_per_sample // 8)
    block_align = num_channels * (bits_per_sample // 8)
    data_size = num_samples * block_align

    with open(filepath, "wb") as f:
        # RIFF header
        f.write(b"RIFF")
        f.write(struct.pack("<I", 36 + data_size))
        f.write(b"WAVE")

        # fmt chunk — IEEE float (format tag 3)
        f.write(b"fmt ")
        f.write(struct.pack("<I", 16))                # chunk size
        f.write(struct.pack("<H", 3))                  # IEEE float
        f.write(struct.pack("<H", num_channels))
        f.write(struct.pack("<I", sample_rate))
        f.write(struct.pack("<I", byte_rate))
        f.write(struct.pack("<H", block_align))
        f.write(struct.pack("<H", bits_per_sample))

        # data chunk — interleaved samples
        f.write(b"data")
        f.write(struct.pack("<I", data_size))
        for i in range(num_samples):
            for ch in range(num_channels):
                f.write(struct.pack("<f", channels[ch][i]))


def generate_ir(preset_name, output_path):
    if preset_name not in PRESETS:
        raise ValueError(f"Unknown preset: {preset_name}. "
                         f"Choose from: {', '.join(PRESETS.keys())}")

    p = PRESETS[preset_name]

    # Channel 0: Direct L→L
    ch_ll = generate_channel(
        gain=p["direct_gain"],
        reflections=p["reflections"],
    )

    # Channel 1: Direct R→R (mirror — same as L→L for symmetric speakers)
    ch_rr = list(ch_ll)

    # Channel 2: Cross L→R
    ch_lr = generate_channel(
        gain=p["cross_gain"],
        reflections=p["cross_reflections"],
        is_cross=True,
        cross_delay_ms=p["cross_delay_ms"],
        cross_lpf_freq=p["cross_lpf_freq"],
    )

    # Channel 3: Cross R→L (mirror of L→R)
    ch_rl = list(ch_lr)

    write_wav(output_path, [ch_ll, ch_rr, ch_lr, ch_rl], SAMPLE_RATE)

    file_size = os.path.getsize(output_path)
    print(f"Generated: {output_path}")
    print(f"  Preset:     {preset_name}")
    print(f"  Channels:   {NUM_CHANNELS} (LL, RR, LR, RL)")
    print(f"  Sample rate: {SAMPLE_RATE} Hz")
    print(f"  Duration:   {IR_DURATION_MS} ms ({IR_SAMPLES} samples)")
    print(f"  Size:       {file_size / 1024:.1f} KB")


def main():
    parser = argparse.ArgumentParser(
        description="Generate spatial audio impulse response for PipeWire convolver."
    )
    parser.add_argument(
        "--intensity", "-i",
        choices=list(PRESETS.keys()),
        default="medium",
        help="Spatial effect intensity (default: medium)"
    )
    parser.add_argument(
        "--output", "-o",
        default=None,
        help="Output WAV path (default: spatial_<intensity>.wav)"
    )
    args = parser.parse_args()

    output = args.output or f"spatial_{args.intensity}.wav"
    generate_ir(args.intensity, output)


if __name__ == "__main__":
    main()
