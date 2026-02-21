# shellcheck shell=bash
# Sourced library — no shebang on purpose. NVIDIA-discrete only: the NVIDIA GPU
# drives both scanout and rendering; the Intel iGPU is unused (BIOS set to
# "Discrete GPU Only" / dGPU owns the panel).

STARCH_SYSTEM_CONF="/etc/starch/profile.conf"
STARCH_USER_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/starch/display.conf"

_starch_load_conf() {
    STARCH_REFRESH_FALLBACK=""
    # shellcheck source=/dev/null
    [ -r "$STARCH_SYSTEM_CONF" ] && . "$STARCH_SYSTEM_CONF"
}

# The NVIDIA DRM card (vendor 0x10de) drives display and render.
_starch_find_card() {
    STARCH_DISPLAY_CARD=""
    local card vendor
    for card in /sys/class/drm/card[0-9]*; do
        [ -r "$card/device/vendor" ] || continue
        read -r vendor < "$card/device/vendor"
        if [ "$vendor" = "0x10de" ]; then
            STARCH_DISPLAY_CARD="/dev/dri/$(basename "$card")"
            return 0
        fi
    done
}

_starch_list_connectors() {
    local card_basename="${STARCH_DISPLAY_CARD##*/}"
    local sys
    for sys in /sys/class/drm/"$card_basename"-*; do
        [ -r "$sys/status" ] || continue
        local name="${sys##*/"${card_basename}"-}"
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
    local name st
    while read -r name st; do
        [ "$st" = "connected" ] || continue
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
        # shellcheck source=/dev/null
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
        external|auto)
            STARCH_PRIMARY_OUTPUT="$(_starch_first_connected external || true)"
            [ -z "$STARCH_PRIMARY_OUTPUT" ] && \
                STARCH_PRIMARY_OUTPUT="$(_starch_first_connected internal || true)"
            ;;
    esac
}

# gamescope's --prefer-output takes a comma-separated priority list and picks
# the first present connector. Externals first (auto/external), internal as
# fallback, so docking prefers the external and unplug returns to internal with
# no reboot. Echoes the comma-joined list.
_starch_output_priority_list() {
    _starch_load_user_pref
    local -a ext=() int=()
    local name st
    while read -r name st; do
        [ "$st" = "connected" ] || continue
        if _starch_is_internal_connector "$name"; then
            int+=("$name")
        else
            ext+=("$name")
        fi
    done < <(_starch_list_connectors)

    local -a ordered=()
    case "$STARCH_PRIMARY_PREF" in
        internal) ordered=("${int[@]}") ;;
        *)        ordered=("${ext[@]}" "${int[@]}") ;;
    esac

    local IFS=,
    printf '%s\n' "${ordered[*]}"
}

starch_profile_init() {
    local tag="${1:-starch}"
    _starch_load_conf
    _starch_find_card

    if [ -z "$STARCH_DISPLAY_CARD" ]; then
        echo "[$tag] FATAL: no NVIDIA DRM card found." >&2
        echo "[$tag] /sys/class/drm contents:" >&2
        ls -la /sys/class/drm/ 2>&1 | sed "s/^/[$tag]   /" >&2
        echo "[$tag] Check the nvidia module is loaded (lsmod | grep nvidia) and the BIOS is in discrete-GPU mode." >&2
        return 1
    fi
    STARCH_RENDER_CARD="$STARCH_DISPLAY_CARD"

    _starch_resolve_primary_output
    STARCH_OUTPUT_PRIORITY="$(_starch_output_priority_list || true)"

    export STARCH_REFRESH_FALLBACK \
           STARCH_DISPLAY_CARD STARCH_RENDER_CARD \
           STARCH_PRIMARY_PREF STARCH_PRIMARY_OUTPUT STARCH_OUTPUT_PRIORITY

    echo "[$tag] display device: ${STARCH_DISPLAY_CARD}"
    echo "[$tag] primary pref:   ${STARCH_PRIMARY_PREF:-auto}"
    echo "[$tag] primary output: ${STARCH_PRIMARY_OUTPUT:-<any>}"
    echo "[$tag] output priority: ${STARCH_OUTPUT_PRIORITY:-<any>}"
}

starch_check_gpu_modules() {
    local tag="${1:-starch}"
    local missing=()
    for m in nvidia nvidia_modeset nvidia_drm; do
        [ -d "/sys/module/$m" ] || missing+=("$m")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "[$tag] WARNING: NVIDIA kernel modules not loaded: ${missing[*]}"
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

    # tee keeps a copy on SDDM's stdout (journal) as well as the file. Known
    # tradeoff: nothing waits on the tee at exit, so the very last lines can be
    # lost — acceptable for a debug log that also lands in the journal.
    exec > >(tee "$logfile") 2>&1

    STARCH_SESSION_NAME="$name"
    STARCH_SESSION_LOG="$logfile"
    export STARCH_SESSION_NAME STARCH_SESSION_LOG

    echo "[${name}-session] START $(date '+%Y-%m-%d %H:%M:%S')"

    trap '_starch_session_end $?' EXIT
}

_starch_session_end() {
    local rc="$1"
    if [ -n "${STARCH_SESSION_PRE_END:-}" ]; then
        eval "$STARCH_SESSION_PRE_END" || true
    fi
    echo "[${STARCH_SESSION_NAME}-session] END rc=$rc $(date '+%Y-%m-%d %H:%M:%S')"
    if [ "$rc" -ne 0 ] && [ -r "$STARCH_SESSION_LOG" ]; then
        local crash="${STARCH_SESSION_LOG%-session.log}-last-crash.log"
        cp -f "$STARCH_SESSION_LOG" "$crash" 2>/dev/null \
            && echo "[${STARCH_SESSION_NAME}-session] crash log: $crash"
    fi
}

# Wait for the default sink to *stabilise*, not just exist. SDDM unlocks before
# WirePlumber's policy pass finishes, so the first default can be auto_null or
# an HDA stub later replaced by HDMI/Bluetooth — and Steam gamepadui latches the
# first default forever (boot video has sound, nothing after). Reject
# auto_null/dummy and require node.name to hold steady before returning.
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

# Pick the backlight device gamescope should drive. Targeting an inactive one
# (machines expose several) moves the slider but changes nothing. Prefer the
# nvidia panel, else the highest max_brightness. Echoes the basename or nothing.
# NB: gamescope can't drive the nvidia native backlight, so the in-Steam slider
# won't appear on this hardware — the device is still used by brightnessctl.
starch_backlight_device() {
    local dir base best="" best_max=-1 max
    local p
    for p in nvidia_0 nvidia_wmi_ec_backlight; do
        if [ -r "/sys/class/backlight/$p/brightness" ]; then
            printf '%s\n' "$p"
            return 0
        fi
    done

    for dir in /sys/class/backlight/*; do
        [ -r "$dir/max_brightness" ] || continue
        base="${dir##*/}"
        read -r max < "$dir/max_brightness" 2>/dev/null || continue
        if [ "${max:-0}" -gt "$best_max" ] 2>/dev/null; then
            best_max="$max"
            best="$base"
        fi
    done

    [ -n "$best" ] && printf '%s\n' "$best"
}

starch_probe_refresh() {
    local fallback="${STARCH_REFRESH_FALLBACK:-}"
    local result=""

    if command -v modetest >/dev/null 2>&1; then
        local want="${STARCH_PRIMARY_OUTPUT:-}"
        result=$(modetest -M nvidia-drm 2>/dev/null | awk -v want="$want" '
            $3 == "connected" {
                match_conn = (want == "" || $4 == want)
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
    export WLR_NO_HARDWARE_CURSORS=1
    export ENABLE_IMPLICIT_SYNC=1
    export WLR_DRM_DEVICES="$STARCH_DISPLAY_CARD"
    export GBM_BACKEND=nvidia-drm
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/10_nvidia.json
    export LIBVA_DRIVER_NAME=nvidia
    export NVD_BACKEND=direct
}

# Retry the compositor on non-zero exit. Gamescope 3.16 has an intermittent
# assertion in wlr_seat_keyboard_notify_enter; a clean exit means the user
# logged out, anything else is treated as a crash. Three fast crashes in a
# row gives up so the user falls back to SDDM rather than thrashing.
starch_run_compositor() {
    local tag="$1"; shift
    [ "${1:-}" = "--" ] && shift

    local max_fast_attempts=3
    local fast_threshold_s=15
    local backoff_s=2
    local fast_attempts=0
    local rc t0 t1 elapsed

    while :; do
        echo "[$tag] launching compositor"
        t0=$(date +%s)
        "$@"
        rc=$?
        t1=$(date +%s)
        elapsed=$(( t1 - t0 ))

        if [ "$rc" -eq 0 ]; then
            echo "[$tag] compositor exited cleanly after ${elapsed}s"
            return 0
        fi

        if [ "$elapsed" -lt "$fast_threshold_s" ]; then
            fast_attempts=$((fast_attempts + 1))
            if [ "$fast_attempts" -ge "$max_fast_attempts" ]; then
                echo "[$tag] compositor crashed ${fast_attempts}× in under ${fast_threshold_s}s each — giving up, returning to SDDM" >&2
                return "$rc"
            fi
            echo "[$tag] compositor crashed rc=$rc after ${elapsed}s (fast crash ${fast_attempts}/${max_fast_attempts}) — retrying in ${backoff_s}s" >&2
            sleep "$backoff_s"
        else
            fast_attempts=0
            echo "[$tag] compositor crashed rc=$rc after ${elapsed}s — relaunching" >&2
            sleep "$backoff_s"
        fi
    done
}
