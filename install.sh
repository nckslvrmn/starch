#!/bin/bash
# starch installer. Declarative where possible:
#   rootfs/  mirrors /            (system files; @@GAMING_USER@@ is templated)
#   userfs/  mirrors $GAMING_HOME (per-user config, installed as the user)
# Executable bits in the repo decide install modes; sudoers files get 0440.
set -euo pipefail

info()  { echo -e "\e[32m[starch]\e[0m $*"; }
warn()  { echo -e "\e[33m[starch]\e[0m WARNING: $*"; }
error() { echo -e "\e[31m[starch]\e[0m ERROR: $*" >&2; }
step()  { echo ""; echo -e "\e[1m--- $* ---\e[0m"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------------------------------------------------------
step "Preflight"

if [ "$(id -u)" -ne 0 ]; then
    error "Run this script as root: sudo bash install.sh"
    exit 1
fi

if [ -z "${GAMING_USER:-}" ]; then
    GAMING_USER="${SUDO_USER:-}"
fi
if [ -z "${GAMING_USER:-}" ]; then
    read -rp "Username to configure for gaming: " GAMING_USER
fi
if ! id "$GAMING_USER" &>/dev/null; then
    error "User '$GAMING_USER' does not exist."
    exit 1
fi
GAMING_HOME=$(getent passwd "$GAMING_USER" | cut -d: -f6)

if ! sudo -u "$GAMING_USER" -H bash -c 'command -v paru' &>/dev/null; then
    error "paru not found for user $GAMING_USER."
    error "Install paru first, then re-run this script:"
    error "  https://github.com/morganamilo/paru#installation"
    exit 1
fi

# steam and the lib32-* stack live in [multilib]; stock Arch ships it disabled.
if ! pacman -Sl multilib &>/dev/null; then
    error "The [multilib] repository is not enabled in /etc/pacman.conf."
    error "Uncomment the [multilib] section, run 'pacman -Sy', and re-run."
    exit 1
fi

# Without nvidia_drm.modeset=1, Wayland sessions and NVIDIA suspend silently
# break. Checked up front so failure costs seconds, not a full package install.
if ! grep -Eq 'nvidia[-_]drm\.modeset=1' /proc/cmdline 2>/dev/null; then
    if [ "${STARCH_SKIP_CMDLINE_CHECK:-0}" = "1" ]; then
        warn "/proc/cmdline is missing nvidia_drm.modeset=1 (skipped via STARCH_SKIP_CMDLINE_CHECK=1)"
    else
        error "/proc/cmdline is missing nvidia_drm.modeset=1."
        error "Add 'nvidia_drm.modeset=1' to your bootloader kernel parameters and re-run."
        error "Already updated the bootloader but not rebooted? STARCH_SKIP_CMDLINE_CHECK=1 to override."
        exit 1
    fi
fi

info "Installing starch for user: $GAMING_USER ($GAMING_HOME)"
# starch targets a single hardware config: Intel + NVIDIA-discrete, BIOS set to
# "Discrete GPU Only" so the NVIDIA GPU drives both scanout and rendering.

# ---------------------------------------------------------------------------
step "Installing packages"

REPO_PACKAGES=(
    alsa-firmware
    alsa-utils
    bluez
    bluez-utils
    brightnessctl
    bubblewrap
    cage
    dolphin-emu
    foot                    # fallback terminal (ghostty is primary)
    fuzzel
    gamescope
    ghostty
    grim
    iwd
    jack2
    jq
    lib32-mangohud
    lib32-mesa
    lib32-nvidia-utils
    lib32-pipewire
    lib32-vulkan-icd-loader
    libdrm                  # modetest (refresh-rate probe)
    libnewt                 # whiptail (starch-select-display TUI)
    libnotify
    libpulse
    fwupd
    libfreeaptx              # aptX for Bluetooth headphones
    mako
    mangohud
    networkmanager
    noto-fonts
    noto-fonts-emoji
    nvidia-utils
    pacman-contrib           # checkupdates (starch-update, Steam update UI)
    pavucontrol
    pipewire
    pipewire-alsa
    pipewire-pulse
    qt6-svg
    qt6-wayland
    river-classic
    scx-scheds               # sched-ext schedulers (STARCH_SCX_SCHED)
    sddm
    slurp
    sof-firmware
    steam
    swayidle
    swaylock
    ttf-dejavu
    upower
    vulkan-icd-loader
    wireplumber
    wl-clipboard
    wlr-randr
    xdg-desktop-portal-gtk
    xdg-desktop-portal-wlr
    xorg-xrdb
    xorg-xwayland
    zram-generator
)

AUR_PACKAGES=(
    brave-bin
    way-displays
    xpadneo-dkms
)

MISSING_REPO=()
for pkg in "${REPO_PACKAGES[@]}"; do
    pacman -Qi "$pkg" &>/dev/null || MISSING_REPO+=("$pkg")
done
MISSING_AUR=()
for pkg in "${AUR_PACKAGES[@]}"; do
    pacman -Qi "$pkg" &>/dev/null || MISSING_AUR+=("$pkg")
done

PACKAGES_NEWLY_INSTALLED=false
if [ ${#MISSING_REPO[@]} -gt 0 ]; then
    info "Installing ${#MISSING_REPO[@]} repo package(s): ${MISSING_REPO[*]}"
    pacman -S --needed --noconfirm "${MISSING_REPO[@]}"
    PACKAGES_NEWLY_INSTALLED=true
fi
if [ ${#MISSING_AUR[@]} -gt 0 ]; then
    info "Installing ${#MISSING_AUR[@]} AUR package(s): ${MISSING_AUR[*]}"
    sudo -u "$GAMING_USER" -H paru -S --needed --noconfirm --skipreview "${MISSING_AUR[@]}"
    PACKAGES_NEWLY_INSTALLED=true
fi
[ "$PACKAGES_NEWLY_INSTALLED" = "false" ] && info "All packages already present."

# ---------------------------------------------------------------------------
step "Deploying system files (rootfs/ → /)"

NEED_INITRAMFS=0

# Wipe the theme before redeploying so removed assets don't linger.
rm -rf /usr/share/sddm/themes/starch

while IFS= read -r -d '' src; do
    dst="${src#"$SCRIPT_DIR"/rootfs}"
    mode=644
    [ -x "$src" ] && mode=755
    case "$dst" in /etc/sudoers.d/*) mode=440 ;; esac

    case "$dst" in
        /etc/mkinitcpio.conf.d/*)
            cmp -s "$src" "$dst" 2>/dev/null || NEED_INITRAMFS=1 ;;
    esac

    if grep -q '@@GAMING_USER@@\|@@GAMING_HOME@@' "$src" 2>/dev/null; then
        sed -e "s/@@GAMING_USER@@/$GAMING_USER/g" \
            -e "s|@@GAMING_HOME@@|$GAMING_HOME|g" "$src" \
            | install -Dm"$mode" /dev/stdin "$dst"
        info "  $dst ($GAMING_USER)"
    else
        install -Dm"$mode" "$src" "$dst"
        info "  $dst"
    fi
done < <(find "$SCRIPT_DIR/rootfs" -type f -print0 | sort -z)

if ! visudo -cf /etc/sudoers.d/starch-perf >/dev/null 2>&1; then
    rm -f /etc/sudoers.d/starch-perf
    error "sudoers drop-in failed visudo validation — removed; perf mode will not work"
    exit 1
fi

# ---------------------------------------------------------------------------
step "Writing /etc/starch/profile.conf"

# Preserve any value the user already set; defaults apply only when unset/empty.
# set +e inside the subshell so a broken conf can't trip the installer's set -e.
_existing() {
    [ -r /etc/starch/profile.conf ] || return 0
    ( set +e; . /etc/starch/profile.conf 2>/dev/null; eval "printf '%s' \"\${$1:-}\"" )
    return 0
}
V_REFRESH=$(_existing STARCH_REFRESH_FALLBACK)
V_SCX=$(_existing STARCH_SCX_SCHED); V_SCX="${V_SCX:-scx_lavd}"
V_STEAM_UPD=$(_existing STARCH_STEAM_UPDATES); V_STEAM_UPD="${V_STEAM_UPD:-0}"
V_ITM=$(_existing STARCH_HDR_ITM); V_ITM="${V_ITM:-0}"
V_SDR_NITS=$(_existing STARCH_HDR_SDR_NITS)
V_SCALER=$(_existing STARCH_SCALER)
V_SHARP=$(_existing STARCH_SHARPNESS)
V_EXTRA=$(_existing STARCH_EXTRA_GAMESCOPE_ARGS)

cat > /etc/starch/profile.conf <<EOF
# Fallback refresh rate (Hz) used when modetest probing fails. Set to your
# panel's native rate so a tooling regression doesn't silently drop to 60Hz.
STARCH_REFRESH_FALLBACK=${V_REFRESH}

# sched-ext scheduler run by starch-perf-mode during Steam sessions
# (scx-scheds package). Default scx_lavd; empty disables.
STARCH_SCX_SCHED=${V_SCX}

# 1 = let Steam's gamepad UI check for and apply OS updates (pacman -Syu via
# the root-side starch-update-* units). Prototype — the progress display in
# Steam may need iteration. 0 = Steam always sees "no updates".
STARCH_STEAM_UPDATES=${V_STEAM_UPD}

# --- gamescope tuning (Steam session), all optional ---
# SDR→HDR inverse tone mapping (1 = on). Makes SDR games use HDR headroom.
STARCH_HDR_ITM=${V_ITM}
# Luminance of SDR content in HDR mode. Empty = gamescope default (400).
# Note: this laptop's panel reports max ~497 nits via EDID, so there is no
# headroom to raise this on the internal display — set it when docked to a
# brighter HDR TV.
STARCH_HDR_SDR_NITS=${V_SDR_NITS}
# Upscaler: fsr | nis | linear | nearest | pixel. Empty = gamescope default.
# (FSR 1.0 here is shader-based and vendor-agnostic — fine on NVIDIA; nis is
# the NVIDIA-branded equivalent.)
STARCH_SCALER=${V_SCALER}
# Upscaler sharpness 0 (max) – 20 (min). Empty = default.
STARCH_SHARPNESS=${V_SHARP}
# Extra args appended verbatim to the gamescope command line.
STARCH_EXTRA_GAMESCOPE_ARGS="${V_EXTRA}"
EOF
info "  refresh=${V_REFRESH:-<unset>} scx=${V_SCX:-<off>} steam-updates=${V_STEAM_UPD}"

install -d -m755 /var/lib/starch

# gamescope's --rt realtime scheduling and nice -20 need CAP_SYS_NICE, else it
# logs "Performance will be affected" and runs at normal priority. The pacman
# hook (rootfs/etc/pacman.d/hooks) reapplies the cap after each upgrade.
if [ -x /usr/bin/gamescope ] && command -v setcap >/dev/null 2>&1; then
    setcap cap_sys_nice=eip /usr/bin/gamescope \
        && info "  setcap cap_sys_nice=eip /usr/bin/gamescope" \
        || warn "  setcap on gamescope failed — --rt will fall back to normal priority"
else
    warn "  /usr/bin/gamescope or setcap not found — skipping CAP_SYS_NICE grant"
fi

# ---------------------------------------------------------------------------
step "Deploying user files (userfs/ → $GAMING_HOME)"

while IFS= read -r -d '' src; do
    rel="${src#"$SCRIPT_DIR"/userfs/}"
    dst="$GAMING_HOME/$rel"
    mode=644
    [ -x "$src" ] && mode=755
    # Install as the user so created parent dirs get the right ownership.
    sudo -u "$GAMING_USER" install -Dm"$mode" "$src" "$dst"
    info "  $dst"
done < <(find "$SCRIPT_DIR/userfs" -type f -print0 | sort -z)

# ---------------------------------------------------------------------------
step "Configuring user groups for $GAMING_USER"

for group in input video audio seat lp; do
    if getent group "$group" &>/dev/null; then
        usermod -aG "$group" "$GAMING_USER"
        info "  Added $GAMING_USER to group: $group"
    else
        warn "  Group '$group' does not exist — skipping. (install relevant packages?)"
    fi
done

# ---------------------------------------------------------------------------
step "Enabling services"

systemctl daemon-reload

# iwd owns WiFi, networkd wired, resolved DNS; NetworkManager stays as a
# passive connectivity monitor for Steam's online check. oomd needs the zram
# swap from zram-generator. nvidia-powerd drives Dynamic Boost; the
# suspend/resume units preserve VRAM across sleep.
for svc in sddm NetworkManager iwd systemd-networkd systemd-resolved \
           systemd-oomd bluetooth \
           nvidia-suspend nvidia-hibernate nvidia-resume nvidia-powerd; do
    if systemctl list-unit-files --quiet "${svc}.service" 2>/dev/null | grep -q "$svc"; then
        systemctl enable "${svc}.service"
        info "  Enabled: ${svc}.service"
    else
        warn "  ${svc}.service not found — skipping"
    fi
done

# Steam ⇄ Desktop switching + Steam-UI updates: path units watch the user's
# request files (Steam's container can only talk to the host via the
# filesystem). The update-check timer feeds Steam's "update available" state.
for unit in starch-session-handoff.path starch-update-apply.path \
            starch-update-check.timer fstrim.timer paccache.timer; do
    systemctl enable "$unit"
    systemctl start "$unit" 2>/dev/null || true
    info "  Enabled: $unit"
done

# logind drop-in (power button = suspend) applies on the next boot. NEVER
# restart systemd-logind here: it removes every active session — running this
# installer from inside river kicked the session to SDDM and left seat
# management thrashed (every relogin's DRM fd got revoked) until a reboot.
info "  Power-button behavior (logind drop-in) applies after reboot"

# BlueZ: Experimental enables BLE battery reporting (controller battery in
# gamepadui, headphone battery via upower); FastConnectable speeds pairing.
# No conf.d support in bluez — edit main.conf in place (pacman treats it as a
# backup file, so upgrades leave it alone and drop a .pacnew).
if [ -f /etc/bluetooth/main.conf ]; then
    _bt_before=$(md5sum /etc/bluetooth/main.conf)
    sed -i -E \
        -e 's|^[#[:space:]]*Experimental[[:space:]]*=.*|Experimental = true|' \
        -e 's|^[#[:space:]]*FastConnectable[[:space:]]*=.*|FastConnectable = true|' \
        /etc/bluetooth/main.conf
    if [ "$_bt_before" != "$(md5sum /etc/bluetooth/main.conf)" ]; then
        systemctl try-restart bluetooth.service 2>/dev/null || true
        info "  BlueZ: Experimental + FastConnectable enabled (BT battery reporting)"
    fi
fi

# resolved only answers if resolv.conf points at its stub.
if [ "$(readlink -f /etc/resolv.conf 2>/dev/null)" != "/run/systemd/resolve/stub-resolv.conf" ]; then
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    info "  /etc/resolv.conf → systemd-resolved stub"
fi

# upower drives Steam's battery indicator. The unit is D-Bus activated (no
# [Install]), so Steam starts it on demand; we just kick it now.
if systemctl list-unit-files --quiet upower.service 2>/dev/null | grep -q upower; then
    systemctl start upower.service 2>/dev/null \
        && info "  upower.service started (battery indicator)" \
        || info "  upower.service present (D-Bus activated on demand)"
else
    warn "  upower.service not found — Steam won't show a battery indicator"
fi

# zram swap now, not just after reboot (the generator ran at daemon-reload).
if ! swapon --show --noheadings 2>/dev/null | grep -q zram; then
    systemctl start systemd-zram-setup@zram0.service 2>/dev/null \
        && info "  zram swap active" \
        || warn "  zram swap not active yet — it will come up on reboot"
fi

# oomd protection should start now too (it needs the zram swap, which is up).
systemctl start systemd-oomd.service 2>/dev/null \
    && info "  systemd-oomd active" \
    || warn "  systemd-oomd not started — it will come up on reboot"

# ---------------------------------------------------------------------------
step "Kernel modules, udev, sysctl"

modprobe uinput 2>/dev/null && info "  uinput loaded" || warn "  uinput already loaded or unavailable"

udevadm control --reload-rules
# Trigger only the subsystems our rules touch. A blanket trigger re-fires DRM
# device events while a live session holds the GPU — part of the session-kick
# incident (see the logind comment above).
udevadm trigger --action=add \
    --subsystem-match=input --subsystem-match=hidraw \
    --subsystem-match=backlight --subsystem-match=usb --subsystem-match=misc
info "  udev rules reloaded (input/hidraw/backlight/usb/misc re-triggered)"

sysctl --system &>/dev/null && info "  sysctl settings applied" || warn "  sysctl apply had warnings (non-fatal)"

# ---------------------------------------------------------------------------
step "ALSA mixer sanity (Realtek Line Out fix)"

/usr/local/lib/starch/fix-alsa
if command -v alsactl >/dev/null 2>&1; then
    alsactl store >/dev/null 2>&1 \
        && info "  ALSA mixer levels persisted (Line Out, Auto-Mute, etc.)" \
        || warn "  alsactl store failed — Line Out may not survive reboot"
fi

# ---------------------------------------------------------------------------
if [ "$PACKAGES_NEWLY_INSTALLED" = "true" ] || [ "$NEED_INITRAMFS" = "1" ]; then
    step "Rebuilding initramfs"
    info "  Running mkinitcpio -P (this will take a moment)..."
    mkinitcpio -P
    info "  Initramfs rebuilt."
else
    info "Skipping initramfs rebuild (nothing changed)"
fi

echo ""
echo "================================================================"
info "starch installation complete!"
echo "================================================================"
echo ""
echo "  BIOS: set graphics to 'Discrete GPU Only' (NVIDIA drives the panel)."
echo ""
echo "  REBOOT to apply:"
echo "    - Early module loading (mkinitcpio change)"
echo "    - Group membership changes for $GAMING_USER"
echo "    - Network stack handoff (iwd / networkd / resolved)"
echo "    - Power-button behavior (tap = suspend, hold = poweroff)"
echo ""
echo "  After rebooting:"
echo "    1. Select 'Steam' or 'Desktop' from SDDM"
echo "    2. Allow Steam to update on first launch (Steam session only)"
echo "    3. In Steam Settings > Compatibility:"
echo "         Enable 'Steam Play for all titles'"
echo "         Select Proton Experimental or latest stable"
echo "    4. In Steam Settings > Controller:"
echo "         Enable controller configuration support"
echo ""
echo "  Pick which display is primary (internal eDP vs external HDMI/DP):"
echo "    starch-select-display            # interactive TUI"
echo "    starch-select-display external   # or pass directly"
echo "    starch-select-display --show     # show current preference"
echo ""
echo "  'Switch to Desktop' in Steam's power menu returns to SDDM."
echo ""
echo "  If you need to troubleshoot:"
echo "    - Run 'starch-doctor' for a preflight check of every common breakage"
echo "    - Drop to a TTY (Ctrl+Alt+F2) if SDDM itself fails to come up"
echo "    - Kernel logs:  dmesg | grep -i nvidia"
echo "    - SDDM logs:    journalctl -u sddm -b"
echo "    - Session logs: ~/.local/share/{steam,river}-session.log"
echo ""
