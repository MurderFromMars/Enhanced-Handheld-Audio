#!/usr/bin/env bash
# ============================================================================
# Handheld Audio Enhance — PipeWire Spatial Convolver for Linux Handhelds
# ============================================================================
# Creates a virtual audio sink that simulates surround sound using a
# 4-way convolver with crossfeed and early reflections. The virtual sink
# stacks on top of your hardware speakers for amplification control.
#
# Usage:
#   ./install.sh                          # interactive mode (recommended)
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
INTENSITY=""
DISPLAY_NAME="Enhanced Audio"
INSTALL_SUSPEND_FIX=""
UNINSTALL=false
INTERACTIVE_MODE=true

# ── Colour helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

info()    { echo -e "${CYAN}●${NC} $*"; }
ok()      { echo -e "${GREEN}✓${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠${NC} $*"; }
err()     { echo -e "${RED}✗${NC} $*" >&2; }
header()  { echo -e "\n${BOLD}${BLUE}▌ $*${NC}"; }
step()    { echo -e "${MAGENTA}→${NC} ${DIM}$*${NC}"; }

# ── Banner ──────────────────────────────────────────────────────────────────
show_banner() {
    clear
    echo -e "${BOLD}${CYAN}"
    cat << "BANNER"
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║        🎧  Enhanced Handheld Audio Installer  🎧                 ║
║                                                                   ║
║     Spatial Audio Processing for Linux Gaming Handhelds          ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
BANNER
    echo -e "${NC}"
}

# ── Help menu ───────────────────────────────────────────────────────────────
show_help() {
    show_banner
    cat << EOF
${BOLD}WHAT THIS DOES:${NC}
  Creates a virtual audio output device that applies spatial processing to
  your handheld's built-in speakers, making them sound wider and more
  immersive using advanced convolution and crossfeed techniques.

${BOLD}COMMAND LINE OPTIONS:${NC}
  ${CYAN}--intensity${NC} <light|medium|heavy>
      ${DIM}Adjust the strength of the spatial effect:${NC}
      • ${GREEN}light${NC}  - Subtle enhancement, natural sound (recommended for movies/music)
      • ${YELLOW}medium${NC} - Balanced spatial widening (great all-rounder)
      • ${RED}heavy${NC}  - Maximum spatial effect (best for gaming)

  ${CYAN}--sink${NC} <node.name>
      ${DIM}Manually specify which audio device to enhance${NC}
      Example: --sink alsa_output.pci-0000_00_1f.3.analog-stereo
      ${DIM}(Auto-detected if not specified)${NC}

  ${CYAN}--name${NC} "Custom Name"
      ${DIM}Set a custom display name for the virtual audio device${NC}
      Default: "Enhanced Audio"

  ${CYAN}--suspend-fix${NC}
      ${DIM}Install a systemd service to fix audio distortion after suspend/resume${NC}
      ${DIM}(Some handhelds experience crackling audio after sleep)${NC}

  ${CYAN}--uninstall${NC}
      ${DIM}Remove all configurations and restore original audio setup${NC}

  ${CYAN}-h, --help${NC}
      ${DIM}Show this help message${NC}

${BOLD}EXAMPLES:${NC}
  ${DIM}# Interactive mode (recommended for first-time users):${NC}
  ./install.sh

  ${DIM}# Quick install with light spatial effect:${NC}
  ./install.sh --intensity light

  ${DIM}# Install with suspend fix for devices with post-sleep audio issues:${NC}
  ./install.sh --intensity medium --suspend-fix

  ${DIM}# Completely remove the enhancement:${NC}
  ./install.sh --uninstall

${BOLD}AFTER INSTALLATION:${NC}
  1. A new audio device will appear in your sound settings
  2. Set it as your default output device
  3. Max out your hardware speaker volume slider
  4. Control loudness from the virtual device slider

${BOLD}MORE INFO:${NC}
  GitHub: https://github.com/MurderFromMars/Enhanced-Handheld-Audio
  
EOF
}

# ── Argument parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    INTERACTIVE_MODE=false
    case "$1" in
        --sink)         SINK_NAME="$2"; shift 2 ;;
        --intensity)    INTENSITY="$2"; shift 2 ;;
        --name)         DISPLAY_NAME="$2"; shift 2 ;;
        --suspend-fix)  INSTALL_SUSPEND_FIX=true; shift ;;
        --uninstall)    UNINSTALL=true; shift ;;
        -h|--help)      show_help; exit 0 ;;
        *) err "Unknown option: $1"; echo ""; echo "Use --help for usage information"; exit 1 ;;
    esac
done

# ── Must not be root ────────────────────────────────────────────────────────
if [[ "$EUID" -eq 0 ]]; then
    err "Do not run as root. PipeWire configs belong to your user."
    exit 1
fi

# ── Uninstall path ──────────────────────────────────────────────────────────
if $UNINSTALL; then
    show_banner
    header "Uninstallation"
    echo ""
    
    info "Removing Enhanced Handheld Audio..."
    echo ""

    if [[ -f "$CONF_FILE" ]]; then
        rm -f "$CONF_FILE"
        ok "Removed PipeWire configuration"
    fi

    if [[ -f "$IR_DEST" ]]; then
        rm -f "$IR_DEST"
        ok "Removed impulse response file"
    fi

    if systemctl --user is-enabled pipewire-fix-audio-after-suspend.service &>/dev/null 2>&1 ||
       [[ -f /etc/systemd/system/pipewire-fix-audio-after-suspend.service ]]; then
        echo ""
        info "Removing suspend fix (requires sudo)..."
        sudo systemctl disable --now pipewire-fix-audio-after-suspend.service 2>/dev/null || true
        sudo rm -f /etc/systemd/system/pipewire-fix-audio-after-suspend.service
        rm -f "$HOME/.local/bin/pipewire-fix-audio-after-suspend.sh"
        ok "Removed suspend fix service"
    fi

    echo ""
    info "Restarting PipeWire services..."
    systemctl --user restart wireplumber pipewire pipewire-pulse 2>/dev/null || true
    
    echo ""
    ok "${GREEN}${BOLD}Uninstallation complete!${NC}"
    echo ""
    info "Your audio setup has been restored to default"
    echo ""
    exit 0
fi

# ── Dependency check ────────────────────────────────────────────────────────
show_banner
header "Checking System Requirements"
echo ""

MISSING_DEPS=false
for cmd in pw-cli pw-metadata pactl; do
    if command -v "$cmd" &>/dev/null; then
        ok "Found: $cmd"
    else
        err "Missing: $cmd"
        MISSING_DEPS=true
    fi
done

if $MISSING_DEPS; then
    echo ""
    err "Required PipeWire tools are missing!"
    echo ""
    info "Please install PipeWire and its utilities:"
    echo "  ${DIM}Arch/CachyOS:    ${NC}sudo pacman -S pipewire pipewire-pulse wireplumber"
    echo "  ${DIM}Fedora:          ${NC}sudo dnf install pipewire pipewire-pulseaudio wireplumber"
    echo "  ${DIM}Ubuntu/Debian:   ${NC}sudo apt install pipewire pipewire-pulse wireplumber"
    echo ""
    exit 1
fi

echo ""
ok "${GREEN}All dependencies satisfied${NC}"
sleep 1

# ── Interactive prompts ─────────────────────────────────────────────────────
if $INTERACTIVE_MODE; then
    # Intensity selection
    if [[ -z "$INTENSITY" ]]; then
        header "Select Spatial Enhancement Intensity"
        echo ""
        echo "  Choose how strong you want the spatial effect:"
        echo ""
        echo "  ${GREEN}1)${NC} ${BOLD}Light${NC}    - Subtle enhancement, keeps natural sound"
        echo "               ${DIM}Best for: Movies, music, podcasts${NC}"
        echo "               ${DIM}Effect: Gentle widening, minimal coloration${NC}"
        echo ""
        echo "  ${YELLOW}2)${NC} ${BOLD}Medium${NC}   - Balanced spatial widening (recommended)"
        echo "               ${DIM}Best for: General use, most games${NC}"
        echo "               ${DIM}Effect: Noticeable depth without being unnatural${NC}"
        echo ""
        echo "  ${RED}3)${NC} ${BOLD}Heavy${NC}    - Maximum spatial effect"
        echo "               ${DIM}Best for: Competitive gaming, action games${NC}"
        echo "               ${DIM}Effect: Strong surround-like processing${NC}"
        echo ""
        
        while true; do
            read -rp "$(echo -e ${CYAN}Select option [1-3]:${NC} )" choice
            case "$choice" in
                1) INTENSITY="light"; break ;;
                2) INTENSITY="medium"; break ;;
                3) INTENSITY="heavy"; break ;;
                *) warn "Invalid choice. Please enter 1, 2, or 3." ;;
            esac
        done
        
        ok "Selected: ${BOLD}${INTENSITY}${NC} intensity"
        sleep 1
    fi
    
    # Suspend fix option
    if [[ -z "$INSTALL_SUSPEND_FIX" ]]; then
        echo ""
        header "Suspend/Resume Audio Fix"
        echo ""
        echo "  Some handhelds experience crackling or distorted audio after"
        echo "  waking from sleep/suspend. This installs a systemd service that"
        echo "  automatically fixes PipeWire audio after resume."
        echo ""
        echo "  ${DIM}This requires sudo privileges to install the system service.${NC}"
        echo ""
        
        while true; do
            read -rp "$(echo -e ${CYAN}Install suspend fix? [y/N]:${NC} )" choice
            case "$choice" in
                [Yy]* ) INSTALL_SUSPEND_FIX=true; break ;;
                [Nn]* | "" ) INSTALL_SUSPEND_FIX=false; break ;;
                * ) warn "Please answer y or n." ;;
            esac
        done
        
        if $INSTALL_SUSPEND_FIX; then
            ok "Will install suspend fix"
        else
            info "Skipping suspend fix"
        fi
        sleep 1
    fi
fi

# ── Validate intensity ──────────────────────────────────────────────────────
case "$INTENSITY" in
    light|medium|heavy) ;;
    *)
        err "Invalid intensity: $INTENSITY"
        err "Choose: light, medium, or heavy"
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
    header "Multiple Audio Devices Detected"
    echo ""
    info "Please select which device to enhance:"
    echo ""
    local i=1
    while IFS= read -r sink; do
        echo "  ${CYAN}$i)${NC} $sink"
        i=$((i + 1))
    done <<< "$sinks"
    echo ""

    while true; do
        read -rp "$(echo -e ${CYAN}Select device [1-$count]:${NC} )" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
            echo "$sinks" | sed -n "${choice}p"
            return 0
        fi
        warn "Invalid choice, please try again."
    done
}

if [[ -z "$SINK_NAME" ]]; then
    echo ""
    header "Detecting Audio Output Device"
    echo ""
    step "Scanning for available audio sinks..."
    
    SINK_NAME=$(detect_default_sink) || true

    if [[ -z "$SINK_NAME" ]]; then
        err "Could not detect any ALSA output sinks."
        echo ""
        info "To manually specify a sink, run:"
        echo "  ${DIM}pw-cli list-objects Node | grep 'node.name.*alsa_output'${NC}"
        echo ""
        echo "Then re-run with: ${CYAN}./install.sh --sink <node.name>${NC}"
        exit 1
    fi
    
    echo ""
    ok "Using sink: ${BOLD}$SINK_NAME${NC}"
    sleep 1
fi

# ── Resolve IR file ─────────────────────────────────────────────────────────
echo ""
header "Preparing Impulse Response File"
echo ""

IR_SRC="$SCRIPT_DIR/spatial_${INTENSITY}.wav"

if [[ ! -f "$IR_SRC" ]]; then
    # Try generating it if the generator script is present
    if [[ -f "$SCRIPT_DIR/generate_ir.py" ]] && command -v python3 &>/dev/null; then
        step "IR file not found, generating spatial_${INTENSITY}.wav..."
        python3 "$SCRIPT_DIR/generate_ir.py" --intensity "$INTENSITY" -o "$IR_SRC"
        ok "Generated custom impulse response"
    else
        err "IR file not found: $IR_SRC"
        err "The spatial_${INTENSITY}.wav file is missing from the installation directory."
        echo ""
        info "Either:"
        echo "  1. Run generate_ir.py to create the file"
        echo "  2. Download the pre-built IR files from the repository"
        exit 1
    fi
else
    ok "Found impulse response: spatial_${INTENSITY}.wav"
fi

# ── Create directories & copy IR ────────────────────────────────────────────
echo ""
header "Installing Configuration"
echo ""

step "Creating PipeWire configuration directories..."
mkdir -p "$PIPEWIRE_DIR" "$PIPEWIRE_CONF_DIR"
ok "Directories ready"

step "Copying impulse response to $HOME/.config/pipewire/..."
cp "$IR_SRC" "$IR_DEST"
ok "Impulse response installed"

# ── Generate PipeWire config ────────────────────────────────────────────────
step "Generating PipeWire filter chain configuration..."

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

ok "Configuration written to:"
echo "   ${DIM}$CONF_FILE${NC}"

# ── Optional: Fuzzy audio after suspend fix ─────────────────────────────────
if [[ "$INSTALL_SUSPEND_FIX" == "true" ]]; then
    echo ""
    header "Installing Suspend/Resume Audio Fix"
    echo ""
    
    step "Creating fix script in $HOME/.local/bin/..."

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
    ok "Fix script created"

    CURRENT_USER="$(whoami)"
    CURRENT_UID="$(id -u)"

    step "Installing systemd service (requires sudo)..."
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

    step "Enabling systemd service..."
    sudo systemctl daemon-reload
    sudo systemctl enable --now pipewire-fix-audio-after-suspend.service
    ok "Suspend fix installed and activated"
fi

# ── Restart PipeWire ────────────────────────────────────────────────────────
echo ""
header "Activating Enhanced Audio"
echo ""

step "Restarting PipeWire services..."
if systemctl --user restart wireplumber pipewire pipewire-pulse 2>/dev/null; then
    ok "PipeWire restarted successfully"
else
    warn "Auto-restart failed. Please restart PipeWire manually or reboot."
fi

# ── Success message ─────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔═══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║                                                                   ║${NC}"
echo -e "${GREEN}${BOLD}║              🎉  Installation Complete!  🎉                       ║${NC}"
echo -e "${GREEN}${BOLD}║                                                                   ║${NC}"
echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}📊 Configuration Summary:${NC}"
echo "   • Intensity:      ${BOLD}${INTENSITY}${NC}"
echo "   • Virtual device: ${BOLD}${DISPLAY_NAME}${NC}"
echo "   • Target sink:    ${DIM}${SINK_NAME}${NC}"
if [[ "$INSTALL_SUSPEND_FIX" == "true" ]]; then
    echo "   • Suspend fix:    ${GREEN}Enabled${NC}"
fi
echo ""
echo -e "${BOLD}🎯 Next Steps:${NC}"
echo ""
echo "   ${CYAN}1.${NC} Open your system sound settings"
echo "   ${CYAN}2.${NC} Look for the '${BOLD}${DISPLAY_NAME}${NC}' output device"
echo "   ${CYAN}3.${NC} Set it as your default audio output"
echo "   ${CYAN}4.${NC} ${BOLD}Important:${NC} Max out your hardware speaker volume"
echo "   ${CYAN}5.${NC} Control loudness using the '${DISPLAY_NAME}' slider"
echo ""
echo -e "${YELLOW}⚠${NC}  ${BOLD}Volume Control Tip:${NC}"
echo "   ${DIM}For best results, set your physical speaker volume to 100%,${NC}"
echo "   ${DIM}then use the virtual device's slider for volume control.${NC}"
echo "   ${DIM}This prevents double-attenuation and maintains audio quality.${NC}"
echo ""
echo -e "${BOLD}🔧 Configuration Files:${NC}"
echo "   ${DIM}Config: $CONF_FILE${NC}"
echo "   ${DIM}IR File: $IR_DEST${NC}"
echo ""
echo -e "${BOLD}💡 Useful Commands:${NC}"
echo "   Change intensity:  ${CYAN}./install.sh --intensity <light|medium|heavy>${NC}"
echo "   Uninstall:         ${CYAN}./install.sh --uninstall${NC}"
echo "   View help:         ${CYAN}./install.sh --help${NC}"
echo ""
echo -e "${DIM}Enjoy your enhanced audio! 🎵${NC}"
echo ""
