STARCH_SYSTEM_CONF="/etc/starch/profile.conf"
STARCH_USER_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/starch/display.conf"

_starch_load_profile() {
    if [ ! -r "$STARCH_SYSTEM_CONF" ]; then
        echo "[starch] FATAL: $STARCH_SYSTEM_CONF missing or unreadable." >&2
        echo "[starch] Re-run install.sh to regenerate it." >&2
        return 1
    fi
    STARCH_PROFILE=""
    STARCH_REFRESH_FALLBACK=""
    . "$STARCH_SYSTEM_CONF"
    case "$STARCH_PROFILE" in
        discrete)           STARCH_PROFILE="nvidia" ;;
        nvidia|optimus|amd) ;;
        *)
            echo "[starch] FATAL: invalid STARCH_PROFILE='$STARCH_PROFILE' in $STARCH_SYSTEM_CONF" >&2
            echo "[starch] Expected one of: nvidia, optimus, amd." >&2
            return 1
            ;;
    esac
}

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
    local filter="$1"
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

_starch_load_user_pref() {
    STARCH_PRIMARY_PREF="auto"
    if [ -r "$STARCH_USER_CONF" ]; then
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

starch_profile_init() {
    _starch_load_profile || return 1
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

    if [ -z "$STARCH_DISPLAY_CARD" ]; then
        echo "[starch] FATAL: no DRM card found for profile '$STARCH_PROFILE'." >&2
        echo "[starch] /sys/class/drm contents:" >&2
        ls -la /sys/class/drm/ 2>&1 | sed 's/^/[starch]   /' >&2
        echo "[starch] Check that the GPU kernel module is loaded (lsmod | grep -E 'nvidia|amdgpu|i915')." >&2
        return 1
    fi

    _starch_resolve_primary_output

    export STARCH_PROFILE STARCH_REFRESH_FALLBACK \
           STARCH_NVIDIA_CARD STARCH_INTEL_CARD STARCH_AMD_CARD \
           STARCH_DISPLAY_CARD STARCH_RENDER_CARD \
           STARCH_PRIMARY_PREF STARCH_PRIMARY_OUTPUT
}

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

starch_wait_for_drm() {
    local tag="${1:-starch}"
    local timeout_ds="${2:-150}"
    local device="$STARCH_DISPLAY_CARD"
    local card="${device##*/}"

    local i
    for i in $(seq 1 "$timeout_ds"); do
        if [ -w "$device" ] && \
           grep -ql '^connected$' /sys/class/drm/"$card"-*/status 2>/dev/null; then
            echo "[$tag] DRM ready: $device (after ~$((i * 100))ms)"
            return 0
        fi
        sleep 0.1
    done

    echo "[$tag] WARNING: DRM not ready after $((timeout_ds / 10))s — launching anyway"
    return 1
}

starch_session_begin() {
    local name="$1"
    local logfile="$HOME/.local/share/${name}-session.log"
    mkdir -p "$(dirname "$logfile")"

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

## Wait for the default audio sink to *stabilise* — not just exist.
##
## "Any sink visible" is not enough. SDDM unlocks the session before
## WirePlumber's policy pass has finished, so the very first default sink
## can be either:
##
##   1. WirePlumber's `auto_null` fallback, published while real hardware
##      is still being probed. Streams opened against it go to /dev/null
##      once the real sink takes over.
##   2. HDA, then replaced by HDMI/Bluetooth a few hundred ms later.
##
## Either way Steam's gamepadui latches its audio stream onto the first
## default and never migrates — the Steam boot video has sound, nothing
## after that does. We poll `wpctl inspect @DEFAULT_AUDIO_SINK@` for the
## default sink's `node.name`, reject `auto_null`/`dummy` prefixes, and
## require the same value across ~500 ms of consecutive samples before
## returning.
##
## Tunables (positional): tag, overall_timeout_ds, stable_ds
##   tag                — log prefix, e.g. "steam-session"
##   overall_timeout_ds — max wait in deciseconds (default 150 = 15s)
##   stable_ds          — consecutive matches required (default 5 ≈ 500ms)
starch_ensure_audio() {
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

    echo "[$tag] WARNING: default audio sink did not stabilise after $((timeout_ds / 10))s — continuing"
    return 1
}

starch_probe_refresh() {
    local fallback="${STARCH_REFRESH_FALLBACK:-}"
    local result=""

    if command -v modetest >/dev/null 2>&1; then
        local driver=""
        case "$STARCH_PROFILE" in
            nvidia)  driver="nvidia-drm" ;;
            optimus) driver="i915" ;;
            amd)     driver="amdgpu" ;;
        esac

        if [ -n "$driver" ]; then
            local want="${STARCH_PRIMARY_OUTPUT:-}"
            result=$(modetest -M "$driver" 2>/dev/null | awk -v want="$want" '
                $3 == "connected" {
                    match_conn = (want == "" || $4 == want || index($4, want) == 1)
                    in_conn = 1
                    next
                }
                $3 == "disconnected" { in_conn = 0; next }
                in_conn && match_conn && /^[[:space:]]+#[0-9]+/ {
                    if ($3+0 > max) max = $3+0
                }
                END { if (max) printf "%d\n", max }
            ')
        fi
    fi

    if [ -n "$result" ]; then
        printf '%s\n' "$result"
    elif [ -n "$fallback" ]; then
        echo "[starch] modetest probe failed; using STARCH_REFRESH_FALLBACK=${fallback}Hz" >&2
        printf '%s\n' "$fallback"
    else
        echo "[starch] WARNING: could not probe refresh rate and no STARCH_REFRESH_FALLBACK set; gamescope will pick a default" >&2
    fi
}

starch_apply_gpu_env() {
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
            export WLR_DRM_DEVICES="$STARCH_INTEL_CARD"
            export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
            export __GLX_VENDOR_LIBRARY_NAME=mesa
            export LIBVA_DRIVER_NAME=nvidia
            export NVD_BACKEND=direct
            ;;
        amd)
            export WLR_DRM_DEVICES="$STARCH_DISPLAY_CARD"
            export LIBVA_DRIVER_NAME=radeonsi
            export AMD_VULKAN_ICD=RADV
            ;;
    esac
}

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

## Warn if the loaded NVIDIA driver doesn't match the flatpak GL extension
## that nvidia-flatpak-gl-sync last installed. Misalignment causes Plex to
## fall back to software rendering.
starch_check_nvidia_flatpak_gl() {
    local tag="${1:-starch}"
    [ "$STARCH_PROFILE" = "nvidia" ] || [ "$STARCH_PROFILE" = "optimus" ] || return 0

    local stamp="/var/lib/starch/flatpak-gl.version"
    [ -r "$stamp" ] || return 0

    local stamp_ver loaded_ver
    stamp_ver=$(cat "$stamp" 2>/dev/null)
    loaded_ver=$(modinfo -F version nvidia 2>/dev/null | head -1)
    if [ -n "$stamp_ver" ] && [ -n "$loaded_ver" ] && [ "$stamp_ver" != "$loaded_ver" ]; then
        echo "[$tag] WARNING: NVIDIA driver $loaded_ver does not match flatpak GL stamp $stamp_ver." >&2
        echo "[$tag] WARNING: GPU acceleration in flatpak apps (Plex) may be broken." >&2
        echo "[$tag] Run: sudo /usr/local/bin/nvidia-flatpak-gl-sync" >&2
        return 1
    fi
    return 0
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
