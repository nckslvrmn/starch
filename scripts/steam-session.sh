#!/bin/bash
# steam-session.sh — Minimal gamescope + Steam launcher for NVIDIA discrete GPU mode
#
# Deploy:
#   sudo install -Dm755 scripts/steam-session.sh /usr/local/bin/steam-session.sh
#
# TUNING:
#   If you experience flickering or gamescope refuses to start, try removing
#   --adaptive-sync from the gamescope invocation below.
#
# LOG FILE: /tmp/steam-session.log — check this after a failed session.
# ---------------------------------------------------------------------------

set -uo pipefail

# Redirect all output to a log file. greetd also captures it in the journal,
# but the log file is easier to read after the session exits.
exec 1>/tmp/steam-session.log 2>&1

# ---------------------------------------------------------------------------
# Phase 1: Dynamic device and display detection
# ---------------------------------------------------------------------------

# Find the NVIDIA DRM card device (PCI vendor 0x10de)
DRM_DEVICE="/dev/dri/card0"  # fallback
for card in /sys/class/drm/card[0-9]; do
    if [ "$(cat "$card/device/vendor" 2>/dev/null)" = "0x10de" ]; then
        DRM_DEVICE="/dev/dri/$(basename "$card")"
        break
    fi
done

# Find the connected internal eDP display output
OUTPUT_NAME="eDP-1"  # fallback
for conn in /sys/class/drm/card*-eDP-*; do
    if [ "$(cat "$conn/status" 2>/dev/null)" = "connected" ]; then
        OUTPUT_NAME=$(basename "$conn" | sed 's/^card[0-9]*-//')
        break
    fi
done

# Get native resolution and refresh via kmsprint (included in libdrm).
# Example kmsprint Crtc line: "    Crtc 0 2560x1600@165.00"
KMSPRINT=$(kmsprint 2>/dev/null || true)
CRTC_LINE=$(echo "$KMSPRINT" | grep -A3 "$OUTPUT_NAME" | grep "Crtc" || true)
RESOLUTION=$(echo "$CRTC_LINE" | grep -oP '\d+x\d+' | head -1 || true)
REFRESH=$(echo "$CRTC_LINE" | grep -oP '(?<=@)\d+' | head -1 || true)
WIDTH="${RESOLUTION%%x*}"
HEIGHT="${RESOLUTION##*x}"

# Fallbacks if detection failed
WIDTH="${WIDTH:-2560}"
HEIGHT="${HEIGHT:-1600}"
REFRESH="${REFRESH:-165}"

echo "[steam-session] DRM device : $DRM_DEVICE"
echo "[steam-session] Output     : $OUTPUT_NAME"
echo "[steam-session] Resolution : ${WIDTH}x${HEIGHT}@${REFRESH}Hz"
echo "[steam-session] gamescope  : $(gamescope --version 2>&1 | head -1)"

# Verify the DRM device actually exists before handing off to gamescope
if [ ! -e "$DRM_DEVICE" ]; then
    echo "[steam-session] ERROR: DRM device $DRM_DEVICE not found. Aborting."
    exit 1
fi

# ---------------------------------------------------------------------------
# Phase 2: Environment
# ---------------------------------------------------------------------------

# NVIDIA GBM/GLX backend for Wayland compositors
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia

# VA-API hardware video decode via NVIDIA NVDEC
export LIBVA_DRIVER_NAME=nvidia
export NVD_BACKEND=direct

# Prevent hardware cursor rendering issues on NVIDIA/Wayland
export WLR_NO_HARDWARE_CURSORS=1

# Prefer the NVIDIA Vulkan ICD explicitly
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json

# Session type — tell Steam and Proton we are on Wayland
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=gamescope

# Steam / Proton performance
export PROTON_ENABLE_NVAPI=1      # Enable DLSS, Reflex, NVAPI features
export DXVK_ASYNC=1               # Async pipeline compilation (reduces stutter)
export STEAM_RUNTIME_HEAVY=1      # Use Steam Runtime with full compat libs

# NOTE: Do NOT set LD_PRELOAD for libgamemodeauto here.
# Loading it before dbus-run-session causes D-Bus to try to auto-activate
# the gamemode service, which blocks for ~60 seconds if gamemoded is not
# already running. Instead, gamemoded is started inside the D-Bus session
# below, and gamescope is wrapped with gamemoderun.

# ---------------------------------------------------------------------------
# Phase 3: Audio — start each daemon only if not already running
# ---------------------------------------------------------------------------
# Check each process independently. If switching from another session (e.g.
# River), some of these may already be running. Starting a second wireplumber
# instance in particular will cause it to core dump.

if ! pgrep -u "$USER" -x pipewire &>/dev/null; then
    pipewire &
    # Wait for the pipewire socket before starting dependents
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -S "/run/user/$(id -u)/pipewire-0" ] && break
        sleep 0.1
    done
fi

if ! pgrep -u "$USER" -x wireplumber &>/dev/null; then
    wireplumber &
fi

if ! pgrep -u "$USER" -x pipewire-pulse &>/dev/null; then
    pipewire-pulse &
fi

# ---------------------------------------------------------------------------
# Phase 4: Launch gamescope → Steam Big Picture inside a D-Bus session
# ---------------------------------------------------------------------------
# gamemoded must start INSIDE the D-Bus session so it can register on the
# session bus. gamescope is then wrapped with gamemoderun, which connects to
# the already-running gamemoded — no LD_PRELOAD, no activation hang.
#
# Exported variables are inherited by the inner bash process.
#
# Flags:
#   --backend drm      : DRM/KMS direct client — no parent compositor needed
#   --drm-device       : explicit DRM device path (detected above)
#   --prefer-output    : target output by name (e.g., eDP-1)
#   -W / -H            : output resolution
#   -r                 : target refresh rate
#   --adaptive-sync    : enable VRR/FreeSync if panel and driver support it
#   --immediate-flips  : low-latency page flips
#   --rt               : realtime compositor thread priority
#   --steam            : Steam overlay and IPC integration
#
# Steam flags:
#   -tenfoot           : Big Picture / TV mode UI
#   -steamos3          : gamescope overlay and suspend/resume hook integration

export DRM_DEVICE OUTPUT_NAME WIDTH HEIGHT REFRESH

echo "[steam-session] Entering D-Bus session..."
exec dbus-run-session -- bash -c '
    echo "[steam-session] Starting gamemoded..."
    gamemoded &
    sleep 0.3

    echo "[steam-session] Launching gamescope..."
    exec gamemoderun gamescope \
        --backend drm \
        --drm-device "$DRM_DEVICE" \
        --prefer-output "$OUTPUT_NAME" \
        -W "$WIDTH" -H "$HEIGHT" \
        -r "$REFRESH" \
        --adaptive-sync \
        --immediate-flips \
        --rt \
        --steam \
        -- steam -tenfoot -steamos3
'
