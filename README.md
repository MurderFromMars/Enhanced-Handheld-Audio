# Handheld Audio Enhance

A PipeWire spatial audio convolver for Linux handhelds. Creates a virtual audio sink that simulates surround sound through built-in speakers on any device — Steam Deck, ROG Ally, Legion Go, GPD, AYANEO, or anything running PipeWire.

## What It Does

The installer sets up a PipeWire filter-chain with a 4-way convolver that processes stereo audio through:

- **Direct paths** (L→L, R→R) with early reflections that add a sense of room width
- **Crossfeed paths** (L→R, R→L) with interaural time delay and head-shadow filtering that simulate how sound from one speaker reaches the opposite ear

The result is a wider, more spatial sound from small built-in speakers. The virtual sink stacks on top of the hardware sink, giving you a separate volume slider — max out your hardware speakers and control loudness from the "Enhanced Audio" slider.

## Requirements

- PipeWire with `pw-cli`, `pw-metadata`, `pactl`
- WirePlumber
- Python 3 (only if regenerating IRs — pre-built WAVs are included)

## Install

```bash
chmod +x install.sh

# Default (medium intensity)
./install.sh

# Or choose an intensity
./install.sh --intensity light    # subtle
./install.sh --intensity medium   # balanced (default)
./install.sh --intensity heavy    # aggressive
```

## Intensity Levels

| Level | Crossfeed | Reflections | Best For |
|---|---|---|---|
| `light` | 15% blend, 3kHz shadow | 3 reflections | Music, when you want minimal coloring |
| `medium` | 25% blend, 2.5kHz shadow | 5 reflections | General gaming and media |
| `heavy` | 35% blend, 2kHz shadow | 7 reflections | Single-player immersion, movies |

## Options

```bash
./install.sh --intensity <level>    # light, medium, heavy
./install.sh --sink <node.name>     # target a specific ALSA sink
./install.sh --name "Display Name"  # custom name for the virtual sink
./install.sh --suspend-fix          # install fuzzy-audio-after-suspend fix
./install.sh --uninstall            # remove everything
```

## How It Works

```
L in ──→ [copy] ──→ [convolver LL: direct] ──→ [mixer L] ──→ L out
                 └→ [convolver LR: cross]  ──→ [mixer R] ─┘
                                                           │
R in ──→ [copy] ──→ [convolver RR: direct] ──→ [mixer R] ──→ R out
                 └→ [convolver RL: cross]  ──→ [mixer L] ─┘
```

The impulse response WAV has 4 channels: direct L, direct R, crossfeed L→R, crossfeed R→L. The crossfeed channels are delayed (~0.3ms interaural time delay) and low-pass filtered (simulating head shadow) to create natural spatial perception.

No device-specific tuning — the IR does not correct for any particular speaker's frequency response. It only adds spatial processing that works on any stereo output.

## Custom IRs

The `generate_ir.py` script synthesizes the impulse responses from scratch. You can tweak the presets in the script (reflection timings, crossfeed levels, filter cutoffs) and regenerate:

```bash
python3 generate_ir.py --intensity medium -o spatial_medium.wav
```

## Headphones / HDMI

Completely unaffected. The convolver only processes audio routed through the virtual sink. When you switch to headphones or HDMI, audio goes directly to that device. The `audio.rate = 48000` is scoped to the convolver's playback node only — no global clock restrictions.

## Suspend Fix

The optional `--suspend-fix` installs a systemd service that nudges PipeWire's clock quantum on resume, fixing distorted audio after sleep/wake. Independent of the convolver.

## Uninstall

```bash
./install.sh --uninstall
```

## Files Installed

```
~/.config/pipewire/
├── pipewire.conf.d/
│   └── handheld-audio-enhance.conf     # filter-chain config
└── handheld-audio-enhance-ir.wav       # active impulse response
```
