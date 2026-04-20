# starch-profile.sh — shared helpers for hardware profile + display selection.
#
# Sourced (not executed) by the start-* session scripts. Two responsibilities:
#
#   1. Read /etc/starch/profile.conf to know whether we're on a "discrete"
#      NVIDIA-only box or an "optimus" hybrid laptop (Precision 5550 etc.)
#
#   2. Resolve which output should be the primary display based on the user's
#      preference file at ~/.config/starch/display.conf:
#
#         PRIMARY=auto       — prefer external if any HDMI/DP is connected,
#                              otherwise the internal eDP panel (default)
#         PRIMARY=internal   — always use the internal eDP laptop display
#         PRIMARY=external   — always use the first connected external output;
#                              fall back to internal if none is plugged in
#
# Exposes, after calling starch_profile_init:
#
#   STARCH_PROFILE           discrete | optimus
#   STARCH_NVIDIA_CARD       /dev/dri/cardN for the NVIDIA GPU (if present)
#   STARCH_INTEL_CARD        /dev/dri/cardN for the Intel iGPU (optimus only)
#   STARCH_DISPLAY_CARD      DRM device gamescope / wlroots should open for
#                            scanout — the iGPU on optimus, nvidia on discrete
#   STARCH_RENDER_CARD       DRM device used for GPU rendering — always the
#                            NVIDIA card when one is present
#   STARCH_PRIMARY_OUTPUT    KMS connector name (e.g. eDP-1, HDMI-A-1) or ""
#                            when no preference could be resolved

STARCH_SYSTEM_CONF="/etc/starch/profile.conf"
STARCH_USER_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/starch/display.conf"

# ---- profile ---------------------------------------------------------------

_starch_load_profile() {
    STARCH_PROFILE="discrete"
    if [ -r "$STARCH_SYSTEM_CONF" ]; then
        # shellcheck disable=SC1090
        . "$STARCH_SYSTEM_CONF"
    fi
    case "$STARCH_PROFILE" in
        discrete|optimus) ;;
        *) STARCH_PROFILE="discrete" ;;
    esac
}

# ---- DRM card discovery ----------------------------------------------------

_starch_find_cards() {
    STARCH_NVIDIA_CARD=""
    STARCH_INTEL_CARD=""
    local card vendor
    for card in /sys/class/drm/card[0-9]*; do
        [ -e "$card/device/vendor" ] || continue
        vendor=$(cat "$card/device/vendor")
        case "$vendor" in
            0x10de) [ -z "$STARCH_NVIDIA_CARD" ] && STARCH_NVIDIA_CARD="/dev/dri/$(basename "$card")" ;;
            0x8086) [ -z "$STARCH_INTEL_CARD"  ] && STARCH_INTEL_CARD="/dev/dri/$(basename "$card")"  ;;
        esac
    done
}

# ---- connector enumeration -------------------------------------------------
#
# Returns lines of "<connector-name> <status>" for every DRM connector on the
# display card. Status is "connected" or "disconnected". Uses only /sys so it
# works without drm_info / modetest installed and without a Wayland session.

_starch_list_connectors() {
    local card_basename="${STARCH_DISPLAY_CARD##*/}"
    local sys
    for sys in /sys/class/drm/"$card_basename"-*; do
        [ -r "$sys/status" ] || continue
        local name="${sys##*/${card_basename}-}"
        printf '%s %s\n' "$name" "$(cat "$sys/status")"
    done
}

_starch_is_internal_connector() {
    case "$1" in
        eDP*|LVDS*|DSI*) return 0 ;;
        *)               return 1 ;;
    esac
}

_starch_first_connected() {
    local filter="$1"  # "internal" | "external" | "any"
    local name status
    while read -r name status; do
        [ "$status" = "connected" ] || continue
        case "$filter" in
            internal) _starch_is_internal_connector "$name" || continue ;;
            external) _starch_is_internal_connector "$name" && continue ;;
        esac
        printf '%s\n' "$name"
        return 0
    done < <(_starch_list_connectors)
    return 1
}

# ---- user preference -------------------------------------------------------

_starch_load_user_pref() {
    STARCH_PRIMARY_PREF="auto"
    if [ -r "$STARCH_USER_CONF" ]; then
        # shellcheck disable=SC1090
        . "$STARCH_USER_CONF"
        case "${PRIMARY:-auto}" in
            internal|external|auto) STARCH_PRIMARY_PREF="$PRIMARY" ;;
        esac
    fi
}

_starch_resolve_primary_output() {
    _starch_load_user_pref
    STARCH_PRIMARY_OUTPUT=""
    case "$STARCH_PRIMARY_PREF" in
        internal)
            STARCH_PRIMARY_OUTPUT="$(_starch_first_connected internal || true)"
            ;;
        external)
            STARCH_PRIMARY_OUTPUT="$(_starch_first_connected external || true)"
            [ -z "$STARCH_PRIMARY_OUTPUT" ] && \
                STARCH_PRIMARY_OUTPUT="$(_starch_first_connected internal || true)"
            ;;
        auto)
            STARCH_PRIMARY_OUTPUT="$(_starch_first_connected external || true)"
            [ -z "$STARCH_PRIMARY_OUTPUT" ] && \
                STARCH_PRIMARY_OUTPUT="$(_starch_first_connected internal || true)"
            ;;
    esac
}

# ---- public entry point ----------------------------------------------------

starch_profile_init() {
    _starch_load_profile
    _starch_find_cards

    if [ "$STARCH_PROFILE" = "optimus" ] && [ -n "$STARCH_INTEL_CARD" ]; then
        STARCH_DISPLAY_CARD="$STARCH_INTEL_CARD"
    else
        STARCH_DISPLAY_CARD="${STARCH_NVIDIA_CARD:-$STARCH_INTEL_CARD}"
    fi
    STARCH_RENDER_CARD="${STARCH_NVIDIA_CARD:-$STARCH_DISPLAY_CARD}"

    _starch_resolve_primary_output

    export STARCH_PROFILE STARCH_NVIDIA_CARD STARCH_INTEL_CARD \
           STARCH_DISPLAY_CARD STARCH_RENDER_CARD \
           STARCH_PRIMARY_PREF STARCH_PRIMARY_OUTPUT
}

# ---- audio sink readiness -------------------------------------------------
#
# SDDM launches the user session the instant it unlocks, but WirePlumber may
# not have bound a sink yet — that's the classic "boot video plays sound,
# nothing after that does" bug. Poll wpctl until a real default sink exists.
#
# Callers pass a short tag used in log lines so each session's log shows the
# same format (e.g. "[steam-session] Default audio sink ready after ...ms").

starch_wait_for_audio() {
    local tag="${1:-starch}"
    local timeout_ds="${2:-100}"   # deciseconds (default 10s)

    systemctl --user start pipewire.service pipewire-pulse.service \
        wireplumber.service 2>/dev/null || true

    local i
    for i in $(seq 1 "$timeout_ds"); do
        if wpctl get-volume @DEFAULT_AUDIO_SINK@ &>/dev/null; then
            echo "[$tag] Default audio sink ready after ~$((i * 100))ms"
            return 0
        fi
        sleep 0.1
    done

    echo "[$tag] WARNING: no default audio sink after $((timeout_ds / 10))s — launching anyway"
    return 1
}

# ---- env helper for NVIDIA / PRIME ----------------------------------------
#
# Apply the GBM/GLX/EGL/VA-API environment variables needed so Wayland
# compositors and gamescope use the NVIDIA stack correctly.
#
# On optimus this also sets PRIME render offload variables so apps launched
# from the session (Steam games, Plex) render on the dGPU while the iGPU
# handles scanout.

starch_apply_gpu_env() {
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
    export LIBVA_DRIVER_NAME=nvidia
    export NVD_BACKEND=direct
    export WLR_NO_HARDWARE_CURSORS=1
    export ENABLE_IMPLICIT_SYNC=1

    if [ "$STARCH_PROFILE" = "optimus" ] && [ -n "$STARCH_INTEL_CARD" ] \
            && [ -n "$STARCH_NVIDIA_CARD" ]; then
        # Compositor: scan out on Intel, render on NVIDIA (wlroots hybrid GPU
        # convention — first device is the primary/display device).
        export WLR_DRM_DEVICES="$STARCH_INTEL_CARD:$STARCH_NVIDIA_CARD"
        export GBM_BACKEND=nvidia-drm

        # PRIME render offload for anything the session spawns.
        export __NV_PRIME_RENDER_OFFLOAD=1
        export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
        export __VK_LAYER_NV_optimus=NVIDIA_only
        export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
    else
        export WLR_DRM_DEVICES="$STARCH_DISPLAY_CARD"
        export GBM_BACKEND=nvidia-drm
    fi
}
