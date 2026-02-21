#!/bin/bash
# steam-session.sh — Minimal gamescope + Steam launcher for NVIDIA discrete GPU mode
#
# Deploy:
#   sudo install -Dm755 scripts/steam-session.sh /usr/local/bin/steam-session.sh
#
# ANTI-FLICKER TUNING:
#   If flickering occurs, comment out --adaptive-sync and/or --immediate-flips
#   in the gamescope invocation at the bottom of this file.
# ---------------------------------------------------------------------------

set -uo pipefail

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

# Gamemode: auto-preload for both 64-bit and 32-bit processes.
# $LIB is expanded by the dynamic linker (not the shell), resolving to
# 'lib' for 64-bit and 'lib32' for 32-bit executables.
export LD_PRELOAD="${LD_PRELOAD:-}:/usr/\$LIB/libgamemodeauto.so.0"

# ---------------------------------------------------------------------------
# Phase 3: Audio — start Pipewire if not already running
# ---------------------------------------------------------------------------

if ! pgrep -u "$USER" pipewire &>/dev/null; then
    pipewire &
    wireplumber &
    pipewire-pulse &
    sleep 0.5
fi

# ---------------------------------------------------------------------------
# Phase 4: Launch gamescope → Steam Big Picture
# ---------------------------------------------------------------------------
# Flags:
#   --backend drm        : DRM/KMS client — no parent compositor needed
#   --drm-device         : explicit DRM device (detected above)
#   --prefer-output      : target output name (e.g., eDP-1)
#   -W / -H              : output resolution
#   -r                   : target refresh rate
#   --adaptive-sync      : VRR / FreeSync (remove if flickering)
#   --immediate-flips    : low-latency presentation (remove if flickering)
#   --rt                 : realtime priority for compositor thread
#   --steam              : enable Steam overlay and IPC integration
#   --xwayland-count 2   : two Xwayland instances for better game compatibility
#
# Steam flags:
#   -tenfoot             : Big Picture / TV mode UI
#   -steamos3            : gamescope integration (overlay, suspend/resume hooks)

exec dbus-run-session -- gamescope \
    --backend drm \
    --drm-device "$DRM_DEVICE" \
    --prefer-output "$OUTPUT_NAME" \
    -W "$WIDTH" -H "$HEIGHT" \
    -r "$REFRESH" \
    --adaptive-sync \
    --immediate-flips \
    --rt \
    --steam \
    --xwayland-count 2 \
    -- steam -tenfoot -steamos3
