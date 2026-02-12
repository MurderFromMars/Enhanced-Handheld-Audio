#!/usr/bin/env bash
# ============================================================================
# Handheld Audio Enhance — PipeWire Spatial Convolver for Linux Handhelds
# ============================================================================
# Creates a virtual audio sink that simulates surround sound using a
# 4-way convolver with crossfeed and early reflections. The virtual sink
# stacks on top of your hardware speakers for amplification control.
#
# Usage:
#   ./install.sh                          # auto-detect, medium intensity
#   ./install.sh --intensity light        # subtle spatial effect
#   ./install.sh --intensity heavy        # aggressive spatial effect
#   ./install.sh --sink <node.name>       # target a specific ALSA sink
#   ./install.sh --name "My Audio"        # custom virtual sink display name
#   ./install.sh --suspend-fix            # install fuzzy-audio suspend fix
#   ./install.sh --uninstall              # remove everything
# ============================================================================

set -euo pipefail

# ── Defaults ────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPEWIRE_DIR="$HOME/.config/pipewire"
PIPEWIRE_CONF_DIR="$PIPEWIRE_DIR/pipewire.conf.d"
CONF_FILE="$PIPEWIRE_CONF_DIR/handheld-audio-enhance.conf"
IR_DEST="$PIPEWIRE_DIR/handheld-audio-enhance-ir.wav"
SINK_NAME=""
INTENSITY="medium"
DISPLAY_NAME="Enhanced Audio"
INSTALL_SUSPEND_FIX=false
UNINSTALL=false

# ── Colour helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERR]${NC}   $*" >&2; }

# ── Argument parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sink)         SINK_NAME="$2"; shift 2 ;;
        --intensity)    INTENSITY="$2"; shift 2 ;;
        --name)         DISPLAY_NAME="$2"; shift 2 ;;
        --suspend-fix)  INSTALL_SUSPEND_FIX=true; shift ;;
        --uninstall)    UNINSTALL=true; shift ;;
        -h|--help)
            sed -n '2,/^# ====/{ /^# ====/d; s/^# \?//; p }' "$0"
            exit 0 ;;
        *) err "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Must not be root ────────────────────────────────────────────────────────
if [[ "$EUID" -eq 0 ]]; then
    err "Do not run as root. PipeWire configs belong to your user."
    exit 1
fi

# ── Uninstall path ──────────────────────────────────────────────────────────
if $UNINSTALL; then
    info "Uninstalling Handheld Audio Enhance..."

    rm -f "$CONF_FILE" "$IR_DEST"

    if systemctl --user is-enabled pipewire-fix-audio-after-suspend.service &>/dev/null 2>&1 ||
       [[ -f /etc/systemd/system/pipewire-fix-audio-after-suspend.service ]]; then
        info "Removing suspend fix (may need sudo)..."
        sudo systemctl disable --now pipewire-fix-audio-after-suspend.service 2>/dev/null || true
        sudo rm -f /etc/systemd/system/pipewire-fix-audio-after-suspend.service
        rm -f "$HOME/.local/bin/pipewire-fix-audio-after-suspend.sh"
    fi

    systemctl --user restart wireplumber pipewire pipewire-pulse 2>/dev/null || true
    ok "Uninstalled. Restarted PipeWire."
    exit 0
fi

# ── Dependency check ────────────────────────────────────────────────────────
for cmd in pw-cli pw-metadata pactl; do
    if ! command -v "$cmd" &>/dev/null; then
        err "Missing required command: $cmd"
        err "Install PipeWire and its tools first."
        exit 1
    fi
done

# ── Validate intensity ──────────────────────────────────────────────────────
case "$INTENSITY" in
    light|medium|heavy) ;;
    *)
        err "Unknown intensity: $INTENSITY"
        err "Choose: light, medium, heavy"
        exit 1 ;;
esac

# ── Auto-detect default ALSA output sink ────────────────────────────────────
detect_default_sink() {
    local sinks
    sinks=$(pw-cli list-objects Node 2>/dev/null \
        | grep -oP 'node\.name = "\Kalsa_output[^"]+' \
        | head -20)

    if [[ -z "$sinks" ]]; then
        sinks=$(pactl list sinks short 2>/dev/null \
            | awk '{print $2}' \
            | grep '^alsa_output' \
            | head -20)
    fi

    [[ -z "$sinks" ]] && return 1

    local count
    count=$(echo "$sinks" | wc -l)
    if [[ "$count" -eq 1 ]]; then
        echo "$sinks"
        return 0
    fi

    echo ""
    info "Multiple audio output sinks detected:"
    echo ""
    local i=1
    while IFS= read -r sink; do
        echo "  $i) $sink"
        i=$((i + 1))
    done <<< "$sinks"
    echo ""

    while true; do
        read -rp "Select sink [1-$count]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
            echo "$sinks" | sed -n "${choice}p"
            return 0
        fi
        warn "Invalid choice, try again."
    done
}

if [[ -z "$SINK_NAME" ]]; then
    info "Auto-detecting default audio output sink..."
    SINK_NAME=$(detect_default_sink) || true

    if [[ -z "$SINK_NAME" ]]; then
        err "Could not detect any ALSA output sinks."
        err "Use --sink <node.name> to specify manually."
        err "Run: pw-cli list-objects Node | grep 'node.name.*alsa_output'"
        exit 1
    fi
    ok "Detected sink: $SINK_NAME"
fi

# ── Resolve IR file ─────────────────────────────────────────────────────────
IR_SRC="$SCRIPT_DIR/spatial_${INTENSITY}.wav"

if [[ ! -f "$IR_SRC" ]]; then
    # Try generating it if the generator script is present
    if [[ -f "$SCRIPT_DIR/generate_ir.py" ]] && command -v python3 &>/dev/null; then
        info "IR file not found, generating spatial_${INTENSITY}.wav..."
        python3 "$SCRIPT_DIR/generate_ir.py" --intensity "$INTENSITY" -o "$IR_SRC"
    else
        err "IR file not found: $IR_SRC"
        err "Run generate_ir.py first, or ensure spatial_*.wav files are alongside this script."
        exit 1
    fi
fi

# ── Create directories & copy IR ────────────────────────────────────────────
mkdir -p "$PIPEWIRE_DIR" "$PIPEWIRE_CONF_DIR"
cp "$IR_SRC" "$IR_DEST"
ok "Copied IR (${INTENSITY}) → $IR_DEST"

# ── Generate PipeWire config ────────────────────────────────────────────────
# Filter graph:
#   Input L ──→ convLL (direct) ──→ mixL ──→ Output L
#   Input R ──→ convRL (cross)  ──↗
#
#   Input R ──→ convRR (direct) ──→ mixR ──→ Output R
#   Input L ──→ convLR (cross)  ──↗
#
# 4 convolvers + 2 mixers = proper stereo crossfeed spatial processing

cat > "$CONF_FILE" << CONFEOF
# ============================================================================
# Handheld Audio Enhance — PipeWire Spatial Convolver
# Generated $(date -Iseconds)
# Intensity:   $INTENSITY
# Target sink: $SINK_NAME
# IR file:     $IR_DEST
# ============================================================================
# The 4-channel IR contains:
#   ch 0 = Direct L→L    ch 1 = Direct R→R
#   ch 2 = Cross  L→R    ch 3 = Cross  R→L
#
# Signal flow:
#   L_in → [copy] → convLL (direct) ──→ mixL → L_out
#                  → convLR (cross)  ──→ mixR ─┘
#   R_in → [copy] → convRR (direct) ──→ mixR → R_out
#                  → convRL (cross)  ──→ mixL ─┘
# ============================================================================

context.modules = [
    { name = libpipewire-module-filter-chain
        args = {
            node.description = "$DISPLAY_NAME"
            media.name       = "$DISPLAY_NAME"
            filter.graph = {
                nodes = [
                    # ── Input splitters (fan out each channel) ──────
                    {
                        type  = builtin
                        label = copy
                        name  = copyL
                    }
                    {
                        type  = builtin
                        label = copy
                        name  = copyR
                    }

                    # ── Direct paths ────────────────────────────────
                    {
                        type   = builtin
                        label  = convolver
                        name   = convLL
                        config = {
                            filename = "$IR_DEST"
                            channel  = 0
                        }
                    }
                    {
                        type   = builtin
                        label  = convolver
                        name   = convRR
                        config = {
                            filename = "$IR_DEST"
                            channel  = 1
                        }
                    }

                    # ── Crossfeed paths ─────────────────────────────
                    {
                        type   = builtin
                        label  = convolver
                        name   = convLR
                        config = {
                            filename = "$IR_DEST"
                            channel  = 2
                        }
                    }
                    {
                        type   = builtin
                        label  = convolver
                        name   = convRL
                        config = {
                            filename = "$IR_DEST"
                            channel  = 3
                        }
                    }

                    # ── Output mixers ───────────────────────────────
                    {
                        type  = builtin
                        label = mixer
                        name  = mixL
                    }
                    {
                        type  = builtin
                        label = mixer
                        name  = mixR
                    }
                ]
                links = [
                    # Fan out L input to direct + crossfeed convolvers
                    { output = "copyL:Out"   input = "convLL:In" }
                    { output = "copyL:Out"   input = "convLR:In" }

                    # Fan out R input to direct + crossfeed convolvers
                    { output = "copyR:Out"   input = "convRR:In" }
                    { output = "copyR:Out"   input = "convRL:In" }

                    # Mix into L output: direct L + crossfeed from R
                    { output = "convLL:Out"  input = "mixL:In 1" }
                    { output = "convRL:Out"  input = "mixL:In 2" }

                    # Mix into R output: direct R + crossfeed from L
                    { output = "convRR:Out"  input = "mixR:In 1" }
                    { output = "convLR:Out"  input = "mixR:In 2" }
                ]
                inputs  = [ "copyL:In" "copyR:In" ]
                outputs = [ "mixL:Out" "mixR:Out" ]
            }
            capture.props = {
                node.name      = "handheld_audio_enhance"
                media.class    = "Audio/Sink"
                priority.driver = 1000
                priority.session = 1000
                audio.channels = 2
                audio.position = [ FL FR ]
            }
            playback.props = {
                node.name      = "handheld_audio_enhance.output"
                node.passive   = true
                audio.channels = 2
                audio.position = [ FL FR ]
                audio.rate     = 48000
                node.target    = "$SINK_NAME"
            }
        }
    }
]
CONFEOF

ok "Wrote config → $CONF_FILE"

# ── Optional: Fuzzy audio after suspend fix ─────────────────────────────────
if $INSTALL_SUSPEND_FIX; then
    info "Installing suspend audio fix (requires sudo)..."

    SUSPEND_SCRIPT="$HOME/.local/bin/pipewire-fix-audio-after-suspend.sh"
    mkdir -p "$HOME/.local/bin"

    cat > "$SUSPEND_SCRIPT" << 'FIXSCRIPT'
#!/usr/bin/env bash
set -o errexit
cmd_output="$(pw-metadata -n settings 0 clock.force-quantum)"
regex="^.{1,}value:'([[:digit:]]{1,})'.{1,}$"
[[ $cmd_output =~ $regex ]] && old_quantum="${BASH_REMATCH[1]}" || exit 1
[[ $old_quantum != 0 ]] && temp_quantum=$(( old_quantum - 1 )) || temp_quantum=16
pw-metadata -n settings 0 clock.force-quantum "$temp_quantum"
pw-metadata -n settings 0 clock.force-quantum "$old_quantum"
FIXSCRIPT
    chmod +x "$SUSPEND_SCRIPT"

    CURRENT_USER="$(whoami)"
    CURRENT_UID="$(id -u)"

    sudo tee /etc/systemd/system/pipewire-fix-audio-after-suspend.service > /dev/null << SVCEOF
[Unit]
Description=Fix distorted PipeWire audio after suspend/resume
After=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

[Service]
Type=oneshot
User=$CURRENT_USER
Environment="XDG_RUNTIME_DIR=/run/user/$CURRENT_UID"
ExecStart=/bin/bash $SUSPEND_SCRIPT

[Install]
WantedBy=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
SVCEOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now pipewire-fix-audio-after-suspend.service
    ok "Suspend fix installed and enabled."
fi

# ── Restart PipeWire ────────────────────────────────────────────────────────
info "Restarting PipeWire..."
systemctl --user restart wireplumber pipewire pipewire-pulse 2>/dev/null || {
    warn "Auto-restart failed. Restart PipeWire manually or reboot."
}

echo ""
ok "Installation complete! (intensity: ${INTENSITY})"
echo ""
info "A new output device '${DISPLAY_NAME}' should now appear in sound settings."
echo ""
warn "TIP: Max out your hardware speaker volume first, then control"
warn "     loudness from the '${DISPLAY_NAME}' virtual sink slider."
echo ""
info "To change intensity: $0 --intensity light|medium|heavy"
info "To uninstall:        $0 --uninstall"
