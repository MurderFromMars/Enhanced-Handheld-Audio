# Handheld Audio Enhance

A PipeWire spatial audio convolver for Linux handhelds. Creates a virtual audio sink that simulates surround sound through built-in speakers on any device — Steam Deck, ROG Ally, Legion Go, GPD, AYANEO, or anything running PipeWire.

## What It Does

Sets up a PipeWire filter-chain with a 4-way convolver that processes stereo audio through:

- **Direct paths** (L→L, R→R) with early reflections that add a sense of room width
- **Crossfeed paths** (L→R, R→L) with interaural time delay and head-shadow filtering that simulate how sound from one speaker reaches the opposite ear

The virtual sink stacks on top of the hardware sink, giving you a separate volume slider — max out your hardware speakers and control loudness from the "Spatial Audio" slider.

## Requirements

- PipeWire with `pw-cli`, `pw-metadata`, `pactl`
- WirePlumber
- Python 3 (only needed if regenerating IR files — pre-built WAVs are included)

## Quick Install

```
sh -c 'tmp=$(mktemp -d) && curl -fsSL https://github.com/MurderFromMars/Enhanced-Handheld-Audio/archive/main.tar.gz | tar -xz -C "$tmp" --strip-components=1 && chmod +x "$tmp/install.sh" && "$tmp/install.sh" && rm -rf "$tmp"'
```

Or clone and run manually:

```bash
git clone https://github.com/MurderFromMars/Enhanced-Handheld-Audio.git
cd Enhanced-Handheld-Audio
chmod +x install.sh
./install.sh
```

## Intensity Levels

Three spatial intensity options are available:

| Level | Crossfeed | Reflections | Best For |
|---|---|---|---|
| `light` | 15% blend, 3kHz shadow | 3 reflections | Music, minimal coloring |
| `medium` | 25% blend, 2.5kHz shadow | 5 reflections | General gaming and media (default) |
| `heavy` | 35% blend, 2kHz shadow | 7 reflections | Single-player immersion, movies |

```bash
./install.sh --intensity light
./install.sh --intensity medium
./install.sh --intensity heavy
```

## All Options

```bash
./install.sh                            # default (medium intensity, auto-detect sink)
./install.sh --intensity <level>        # light, medium, heavy
./install.sh --sink <node.name>         # target a specific ALSA sink
./install.sh --name "Display Name"      # custom name for the virtual sink
./install.sh --suspend-fix              # install fuzzy-audio-after-suspend fix
./install.sh --uninstall                # remove everything
```

## How It Works

```
L in → [copy] → [convolver LL: direct] → [mixer L] → L out
              └→ [convolver LR: cross]  → [mixer R] ┘
                                                     │
R in → [copy] → [convolver RR: direct] → [mixer R] → R out
              └→ [convolver RL: cross]  → [mixer L] ┘
```

A 4-channel impulse response WAV drives the convolvers — direct L, direct R, crossfeed L→R, crossfeed R→L. The crossfeed channels are delayed (~0.3ms interaural time delay) and low-pass filtered to simulate head shadow, creating natural spatial perception without any device-specific frequency correction.

## Volume Stacking

The hardware speaker volume acts as a gain ceiling for the virtual sink. For maximum range, set your hardware speakers to max and control volume through the "Enhanced Audio" slider in your sound settings.

## Headphones / HDMI

Completely unaffected. The convolver only processes audio explicitly routed through the virtual sink. Headphones, HDMI, USB DACs, and Bluetooth audio all bypass it entirely.

## Suspend Fix

The optional `--suspend-fix` flag installs a systemd service that nudges PipeWire's clock quantum on resume, fixing distorted/fuzzy audio after sleep. This is independent of the convolver and useful on its own.

## Custom IRs

The `generate_ir.py` script synthesizes impulse responses from scratch. Tweak reflection timings, crossfeed levels, or head-shadow cutoffs and regenerate:

```bash
python3 generate_ir.py --intensity medium -o spatial_medium.wav
```

## Uninstall

```bash
./install.sh --uninstall
```

Or via the one-liner:

```
sh -c 'tmp=$(mktemp -d) && curl -fsSL https://github.com/MurderFromMars/Enhanced-Handheld-Audio/archive/main.tar.gz | tar -xz -C "$tmp" --strip-components=1 && "$tmp/install.sh" --uninstall && rm -rf "$tmp"'
```

## Files Installed

```
~/.config/pipewire/
├── pipewire.conf.d/
│   └── handheld-audio-enhance.conf     # filter-chain config
└── handheld-audio-enhance-ir.wav       # active impulse response
```

## Acknowledgments

This project was inspired by the audio work in [legion-go-tricks](https://github.com/aarron-lee/legion-go-tricks) by [@aarron-lee](https://github.com/aarron-lee), which aggregates community fixes for the Lenovo Legion Go. The original speaker correction convolver was developed by [@matte-schwartz](https://github.com/matte-schwartz) in [device-quirks](https://github.com/matte-schwartz/device-quirks), with an improved impulse response contributed by @adolfotregosa and configuration fixes from [@KyleGospo](https://github.com/KyleGospo).

Their work demonstrated the effectiveness of PipeWire's convolver filter-chain for improving handheld audio and directly motivated this project's approach. Enhanced Handheld Audio takes a different direction — synthetic spatial processing rather than device-specific speaker correction — but the idea of using a virtual convolver sink for handheld speakers originated with their efforts.
