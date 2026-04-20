# starch-profile.sh — shared helpers for hardware profile, session logging,
# display selection, audio readiness, and GPU environment setup.
#
# Sourced (not executed) by the start-* session scripts.
#
# Hardware profiles supported:
#
#   nvidia   — NVIDIA-only system. BIOS set to Discrete GPU Only on laptops.
#              NVIDIA drives scanout and rendering.
#   optimus  — Intel iGPU + NVIDIA dGPU hybrid laptop (e.g. Dell Precision
#              5550). Intel drives scanout, NVIDIA renders via PRIME offload.
#   amd      — AMD GPU (desktop dGPU or APU). amdgpu drives scanout and
#              rendering; no NVIDIA stack involved.
#
# (The legacy profile name "discrete" is accepted as a synonym for "nvidia"
#  so older /etc/starch/profile.conf files from pre-refactor installs keep
#  working until install.sh is re-run.)
#
# User-facing display preference lives at ~/.config/starch/display.conf:
#
#     PRIMARY=auto     — prefer external if an HDMI/DP is connected,
#                        otherwise the internal eDP panel (default)
#     PRIMARY=internal — always the internal eDP laptop display
#     PRIMARY=external — always the first connected external output; fall
#                        back to internal if nothing is plugged in
#
# Exposes, after starch_profile_init:
#
#   STARCH_PROFILE            nvidia | optimus | amd
#   STARCH_NVIDIA_CARD        /dev/dri/cardN for the NVIDIA GPU (if present)
#   STARCH_INTEL_CARD         /dev/dri/cardN for the Intel iGPU (if present)
#   STARCH_AMD_CARD           /dev/dri/cardN for the AMD GPU (if present)
#   STARCH_DISPLAY_CARD       DRM node the compositor should scan out on
#   STARCH_RENDER_CARD        DRM node used for GPU rendering
#   STARCH_PRIMARY_PREF       auto | internal | external
#   STARCH_PRIMARY_OUTPUT     KMS connector name, or empty if unresolved

STARCH_SYSTEM_CONF="/etc/starch/profile.conf"
STARCH_USER_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/starch/display.conf"

# ---- profile ---------------------------------------------------------------

_starch_load_profile() {
    STARCH_PROFILE="nvidia"
    if [ -r "$STARCH_SYSTEM_CONF" ]; then
        # shellcheck disable=SC1090
        . "$STARCH_SYSTEM_CONF"
    fi
    case "$STARCH_PROFILE" in
        discrete)          STARCH_PROFILE="nvidia" ;;   # legacy alias
        nvidia|optimus|amd) ;;
        *)                 STARCH_PROFILE="nvidia" ;;
    esac
}

# ---- DRM card discovery ----------------------------------------------------

_starch_find_cards() {
    STARCH_NVIDIA_CARD=""
    STARCH_INTEL_CARD=""
    STARCH_AMD_CARD=""
    local card vendor
    for card in /sys/class/drm/card[0-9]*; do
        [ -e "$card/device/vendor" ] || continue
        vendor=$(cat "$card/device/vendor")
        case "$vendor" in
            0x10de) [ -z "$STARCH_NVIDIA_CARD" ] && STARCH_NVIDIA_CARD="/dev/dri/$(basename "$card")" ;;
            0x8086) [ -z "$STARCH_INTEL_CARD"  ] && STARCH_INTEL_CARD="/dev/dri/$(basename "$card")"  ;;
            0x1002) [ -z "$STARCH_AMD_CARD"    ] && STARCH_AMD_CARD="/dev/dri/$(basename "$card")"    ;;
        esac
    done
}

# ---- connector enumeration -------------------------------------------------
#
# Returns lines of "<connector-name> <status>" for every DRM connector on the
# display card. Uses only /sys so it works without drm_info/modetest and
# without a running Wayland session.

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

# ---- public init -----------------------------------------------------------

starch_profile_init() {
    _starch_load_profile
    _starch_find_cards

    case "$STARCH_PROFILE" in
        optimus)
            STARCH_DISPLAY_CARD="${STARCH_INTEL_CARD:-$STARCH_NVIDIA_CARD}"
            STARCH_RENDER_CARD="${STARCH_NVIDIA_CARD:-$STARCH_DISPLAY_CARD}"
            ;;
        amd)
            STARCH_DISPLAY_CARD="${STARCH_AMD_CARD:-}"
            STARCH_RENDER_CARD="${STARCH_AMD_CARD:-$STARCH_DISPLAY_CARD}"
            ;;
        nvidia|*)
            STARCH_DISPLAY_CARD="${STARCH_NVIDIA_CARD:-${STARCH_AMD_CARD:-$STARCH_INTEL_CARD}}"
            STARCH_RENDER_CARD="$STARCH_DISPLAY_CARD"
            ;;
    esac

    _starch_resolve_primary_output

    export STARCH_PROFILE \
           STARCH_NVIDIA_CARD STARCH_INTEL_CARD STARCH_AMD_CARD \
           STARCH_DISPLAY_CARD STARCH_RENDER_CARD \
           STARCH_PRIMARY_PREF STARCH_PRIMARY_OUTPUT
}

# ---- kernel-module sanity check -------------------------------------------
#
# Screams loudly when the expected GPU driver stack didn't actually load.
# Previously a missing nvidia_drm would silently produce a blank screen at
# gamescope launch; now the log says exactly what's wrong.
#
# Returns 0 if all expected modules are present, 1 otherwise (but the session
# keeps going — the caller decides whether to proceed).

starch_check_gpu_modules() {
    local tag="${1:-starch}"
    local missing=()
    case "$STARCH_PROFILE" in
        nvidia|optimus)
            for m in nvidia nvidia_modeset nvidia_drm; do
                [ -d "/sys/module/$m" ] || missing+=("$m")
            done
            if [ "$STARCH_PROFILE" = "optimus" ] && [ ! -d /sys/module/i915 ]; then
                missing+=(i915)
            fi
            ;;
        amd)
            [ -d /sys/module/amdgpu ] || missing+=(amdgpu)
            ;;
    esac
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "[$tag] WARNING: expected kernel modules not loaded: ${missing[*]}"
        echo "[$tag] WARNING: session will try to continue but display/render may fail"
        return 1
    fi
    return 0
}

# ---- session logging + crash capture --------------------------------------
#
# One call replaces the tee boilerplate at the top of every start-* script:
#
#   starch_session_begin steam
#
# - Writes to ~/.local/share/<name>-session.log, truncating each launch so
#   logs don't accumulate forever.
# - Prints a consistent START banner with profile/display/output summary.
# - Installs an EXIT trap that prints an END banner with the exit code and,
#   on non-zero exit, copies the log to ~/.local/share/<name>-last-crash.log
#   so the last failure is always recoverable.

starch_session_begin() {
    local name="$1"
    local logfile="$HOME/.local/share/${name}-session.log"
    mkdir -p "$(dirname "$logfile")"

    # Overwrite, don't append — per-session log rotation.
    exec > >(tee "$logfile") 2>&1

    STARCH_SESSION_NAME="$name"
    STARCH_SESSION_LOG="$logfile"
    export STARCH_SESSION_NAME STARCH_SESSION_LOG

    echo "[${name}-session] START $(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${name}-session] profile:        $STARCH_PROFILE"
    echo "[${name}-session] display device: ${STARCH_DISPLAY_CARD:-<none>}"
    echo "[${name}-session] render device:  ${STARCH_RENDER_CARD:-<none>}"
    echo "[${name}-session] primary pref:   ${STARCH_PRIMARY_PREF:-auto}"
    echo "[${name}-session] primary output: ${STARCH_PRIMARY_OUTPUT:-<any>}"

    trap '_starch_session_end $?' EXIT
}

_starch_session_end() {
    local rc="$1"
    echo "[${STARCH_SESSION_NAME}-session] END rc=$rc $(date '+%Y-%m-%d %H:%M:%S')"
    if [ "$rc" -ne 0 ] && [ -r "$STARCH_SESSION_LOG" ]; then
        local crash="${STARCH_SESSION_LOG%-session.log}-last-crash.log"
        cp -f "$STARCH_SESSION_LOG" "$crash" 2>/dev/null \
            && echo "[${STARCH_SESSION_NAME}-session] crash log: $crash"
    fi
}

# ---- audio sink readiness -------------------------------------------------
#
# SDDM launches the user session the instant it unlocks, but WirePlumber may
# still be probing sinks. `wpctl get-volume @DEFAULT_AUDIO_SINK@` flips to
# "ok" the moment *any* default is elected, including two states that look
# fine but break audio for anything launched during them:
#
#   1. An `auto_null` fallback sink that WirePlumber publishes while it's
#      still discovering real hardware. Any stream opened against it goes
#      to /dev/null once the real sink takes over.
#
#   2. A brief window where HDA is the default, then HDMI/Bluetooth replaces
#      it a few hundred ms later after policy runs. Steam's gamepadui opens
#      its audio stream on the first default and never migrates — the Steam
#      boot video has sound, nothing after that does.
#
# This helper waits for the default sink's `node.name` to be non-fallback
# AND identical across ~500 ms of samples before returning.

starch_wait_for_audio() {
    local tag="${1:-starch}"
    local timeout_ds="${2:-150}"
    local stable_ds="${3:-5}"

    systemctl --user start pipewire.service pipewire-pulse.service \
        wireplumber.service 2>/dev/null || true

    local i cur last="" stable=0 t0 now dt
    t0=$(date +%s%3N 2>/dev/null || echo 0)

    for i in $(seq 1 "$timeout_ds"); do
        cur=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null \
            | awk -F '"' '/^[[:space:]]*\*?[[:space:]]*node\.name[[:space:]]*=/ {print $2; exit}')

        case "$cur" in
            auto_null*|dummy*|"") cur="" ;;
        esac

        if [ -n "$cur" ] && [ "$cur" = "$last" ]; then
            stable=$((stable + 1))
            if [ "$stable" -ge "$stable_ds" ]; then
                now=$(date +%s%3N 2>/dev/null || echo 0)
                dt=$(( now - t0 ))
                echo "[$tag] Audio sink ready: $cur (stable after ~${dt}ms)"
                return 0
            fi
        else
            stable=0
            last="$cur"
        fi
        sleep 0.1
    done

    echo "[$tag] WARNING: audio sink did not stabilise after $((timeout_ds / 10))s (last: ${last:-none}) — launching anyway"
    return 1
}

# ---- GPU env for compositor + spawned apps --------------------------------
#
# Sets the GBM/GLX/EGL/Vulkan/VA-API environment so gamescope, wlroots, and
# everything the session spawns picks the right stack for the profile.
#
# Prints the chosen vars so session logs show what the app actually runs
# with (useful when "games are on Intel" is the mystery).

starch_apply_gpu_env() {
    # Cleared unconditionally so re-entering the helper from a different
    # profile does not leak stale NVIDIA vars.
    unset __NV_PRIME_RENDER_OFFLOAD __NV_PRIME_RENDER_OFFLOAD_PROVIDER \
          __VK_LAYER_NV_optimus VK_ICD_FILENAMES GBM_BACKEND \
          __GLX_VENDOR_LIBRARY_NAME __EGL_VENDOR_LIBRARY_FILENAMES \
          LIBVA_DRIVER_NAME NVD_BACKEND

    export WLR_NO_HARDWARE_CURSORS=1
    export ENABLE_IMPLICIT_SYNC=1

    case "$STARCH_PROFILE" in
        nvidia)
            export WLR_DRM_DEVICES="$STARCH_DISPLAY_CARD"
            export GBM_BACKEND=nvidia-drm
            export __GLX_VENDOR_LIBRARY_NAME=nvidia
            export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
            export LIBVA_DRIVER_NAME=nvidia
            export NVD_BACKEND=direct
            ;;
        optimus)
            # Compositor (River / gamescope) MUST scan out on the Intel iGPU
            # and use Mesa's GBM / EGL / Vulkan for its own rendering context.
            # Setting GBM_BACKEND=nvidia-drm or forcing the NVIDIA EGL/VK ICDs
            # here would make the compositor try to create an EGL display on
            # the NVIDIA card — which has NO display outputs on an Optimus
            # laptop — causing:
            #   - "unable to open /dev/dri/cardN as KMS device"
            #   - "failed to create EGL display/context"
            #   - "could not match drm and vulkan device"
            #
            # NVIDIA PRIME offload env vars belong on *child* apps (games,
            # Steam, Plex), not on the compositor.  Use starch_prime_env or
            # starch_flatpak_env_args to pass them to child processes.
            export WLR_DRM_DEVICES="$STARCH_INTEL_CARD"
            # VA-API video decode still goes through NVIDIA.
            export LIBVA_DRIVER_NAME=nvidia
            export NVD_BACKEND=direct
            ;;
        amd)
            export WLR_DRM_DEVICES="$STARCH_DISPLAY_CARD"
            # Mesa's RADV is the Vulkan ICD; VA-API goes through radeonsi.
            export LIBVA_DRIVER_NAME=radeonsi
            export AMD_VULKAN_ICD=RADV
            ;;
    esac
}

# ---- flatpak env passthrough ----------------------------------------------
#
# Flatpak runs apps in a sandbox that does NOT inherit the host environment;
# vars must be forwarded explicitly with --env=K=V. Builds the list of args
# for the currently-active profile.
#
# Usage:
#     read -r -a FP_ENV < <(starch_flatpak_env_args)
#     flatpak run "${FP_ENV[@]}" --device=dri tv.plex.PlexHTPC

# ---- PRIME offload env for child apps (optimus only) ----------------------
#
# Returns the env var assignments that make a child process render on the
# NVIDIA dGPU via PRIME offload.  On non-optimus profiles this is a no-op.
#
# Two output modes controlled by the first argument:
#
#   starch_prime_env export   — prints "export K=V" lines (eval-able)
#   starch_prime_env env      — prints "K=V" tokens for use with /usr/bin/env
#   starch_prime_env flatpak  — prints "--env=K=V" flags for flatpak run
#
# Usage in start-steam (pass to the process *after* gamescope's --):
#
#   read -r -a PRIME < <(starch_prime_env env)
#   exec gamescope … -- env "${PRIME[@]}" steam -gamepadui

starch_prime_env() {
    local mode="${1:-env}"
    [ "$STARCH_PROFILE" = "optimus" ] || return 0

    local -a vars=(
        __NV_PRIME_RENDER_OFFLOAD=1
        __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
        __GLX_VENDOR_LIBRARY_NAME=nvidia
        __VK_LAYER_NV_optimus=NVIDIA_only
        VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
        GBM_BACKEND=nvidia-drm
    )

    local v
    for v in "${vars[@]}"; do
        case "$mode" in
            export)  printf 'export %s\n' "$v" ;;
            env)     printf '%s\n' "$v" ;;
            flatpak) printf -- '--env=%s\n' "$v" ;;
        esac
    done
}

starch_flatpak_env_args() {
    local args=()
    case "$STARCH_PROFILE" in
        nvidia)
            args+=(
                --env=LIBVA_DRIVER_NAME=nvidia
                --env=NVD_BACKEND=direct
                --env=__GLX_VENDOR_LIBRARY_NAME=nvidia
                --env=GBM_BACKEND=nvidia-drm
            )
            ;;
        optimus)
            args+=(
                --env=LIBVA_DRIVER_NAME=nvidia
                --env=NVD_BACKEND=direct
            )
            # Add the full PRIME offload set so the sandboxed app renders
            # on the NVIDIA dGPU.
            local v
            while IFS= read -r v; do
                [ -n "$v" ] && args+=("$v")
            done < <(starch_prime_env flatpak)
            ;;
        amd)
            args+=(
                --env=LIBVA_DRIVER_NAME=radeonsi
                --env=AMD_VULKAN_ICD=RADV
            )
            ;;
    esac
    printf '%s\n' "${args[@]}"
}
