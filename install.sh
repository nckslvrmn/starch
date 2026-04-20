#!/bin/bash
# install.sh — Deploy starch gaming session to an Arch Linux system
#
# Run as root from the starch/ directory:
#   sudo bash install.sh
#
# Or specify a username directly:
#   sudo GAMING_USER=myuser bash install.sh
#
# Hardware profile — auto-detected from lspci, or override explicitly:
#   sudo HW_PROFILE=nvidia  bash install.sh   # NVIDIA-only (desktop, Legion Pro 7)
#   sudo HW_PROFILE=optimus bash install.sh   # Intel iGPU + NVIDIA dGPU (Precision 5550)
#   sudo HW_PROFILE=amd     bash install.sh   # AMD CPU + AMD GPU / APU

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { echo -e "\e[32m[starch]\e[0m $*"; }
warn()  { echo -e "\e[33m[starch]\e[0m WARNING: $*"; }
error() { echo -e "\e[31m[starch]\e[0m ERROR: $*" >&2; }
step()  { echo ""; echo -e "\e[1m--- $* ---\e[0m"; }

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    error "Run this script as root: sudo bash install.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

# paru must run as a regular user — verify it is installed for GAMING_USER
if ! sudo -u "$GAMING_USER" -H which paru &>/dev/null; then
    error "paru not found for user $GAMING_USER."
    error "Install paru first, then re-run this script:"
    error "  https://github.com/morganamilo/paru#installation"
    exit 1
fi

info "Installing starch gaming session for user: $GAMING_USER"

# ---------------------------------------------------------------------------
# Hardware profile detection
# ---------------------------------------------------------------------------
#
# nvidia  — NVIDIA-only system (BIOS set to Discrete GPU Only on laptops).
# optimus — Intel iGPU + NVIDIA dGPU hybrid. Intel owns the display pipe,
#           NVIDIA is used for render offload via PRIME (e.g. Precision 5550).
# amd     — AMD GPU (desktop dGPU or APU). amdgpu drives everything.

detect_profile() {
    if ! command -v lspci >/dev/null 2>&1; then
        echo "nvidia"; return
    fi
    local gpus has_intel has_nvidia has_amd
    gpus=$(lspci -nn | grep -Ei 'VGA|3D|Display')
    has_intel=$(echo "$gpus"  | grep -c '\[8086:' || true)
    has_nvidia=$(echo "$gpus" | grep -c '\[10de:' || true)
    has_amd=$(echo "$gpus"    | grep -c '\[1002:' || true)
    if [ "$has_intel" -gt 0 ] && [ "$has_nvidia" -gt 0 ]; then
        echo "optimus"
    elif [ "$has_nvidia" -gt 0 ]; then
        echo "nvidia"
    elif [ "$has_amd" -gt 0 ]; then
        echo "amd"
    else
        echo "nvidia"
    fi
}

if [ -n "${HW_PROFILE:-}" ]; then
    case "$HW_PROFILE" in
        discrete) HW_PROFILE="nvidia" ;;   # legacy alias
        nvidia|optimus|amd) ;;
        *) error "Invalid HW_PROFILE='$HW_PROFILE' (expected nvidia | optimus | amd)"; exit 1 ;;
    esac
    info "Hardware profile (from HW_PROFILE env): $HW_PROFILE"
else
    HW_PROFILE="$(detect_profile)"
    info "Hardware profile (auto-detected): $HW_PROFILE"
fi

# ---------------------------------------------------------------------------
# 1. Packages
# ---------------------------------------------------------------------------

step "Installing packages"

PACKAGES=(
    # Gamescope — Valve's micro-compositor, runs as DRM master
    gamescope

    # Steam client
    steam

    # Vulkan (loader + Mesa fallback for older non-Vulkan game paths)
    vulkan-icd-loader
    lib32-vulkan-icd-loader
    lib32-mesa

    # Xwayland (for X11 games running under Proton)
    xorg-xwayland

    # CPU/GPU performance daemon
    gamemode
    lib32-gamemode

    # Performance overlay — toggle in-game with MANGOHUD=1
    mangohud
    lib32-mangohud

    # Audio
    pipewire
    pipewire-pulse
    pipewire-alsa
    lib32-pipewire
    wireplumber

    # Display output querying (river session display config)
    wlr-randr

    # JSON parsing for wlr-randr output in river/init
    jq

    # Wayland-native application launcher
    fuzzel

    # Brightness control (media keys in river)
    brightnessctl

    # Network manager — required by Steam for network status via D-Bus
    networkmanager

    # XDG Desktop Portal — file dialogs, screen sharing for Wayland apps
    xdg-desktop-portal-wlr
    xdg-desktop-portal-gtk

    # Clipboard support for Wayland
    wl-clipboard

    # Login / display manager
    sddm
    weston          # Wayland compositor for the SDDM greeter
    qt6-wayland     # Qt6 Wayland platform plugin for sddm-greeter-qt6
    qt6-svg         # SVG rendering for Qt6 theme

    # Flatpak runtime (needed for Plex HTPC and other sandboxed apps)
    flatpak

    # AUR: improved Xbox controller driver
    xpadneo-dkms

    # GameCube / Wii emulator
    dolphin-emu

    # whiptail for starch-select-display TUI
    libnewt
)

# Per-profile GPU userspace stacks.
case "$HW_PROFILE" in
    nvidia)
        # NVIDIA 32-bit userspace libs (needed by most games via Proton/WINE).
        PACKAGES+=(lib32-nvidia-utils)
        ;;
    optimus)
        # NVIDIA for render offload + Intel for scanout/decode.
        PACKAGES+=(
            lib32-nvidia-utils
            mesa
            vulkan-intel
            lib32-vulkan-intel
            intel-media-driver
            libva-utils
        )
        ;;
    amd)
        # RADV Vulkan + radeonsi VA-API. No NVIDIA stack involved.
        PACKAGES+=(
            mesa
            vulkan-radeon
            lib32-vulkan-radeon
            libva-mesa-driver
            lib32-libva-mesa-driver
            libva-utils
        )
        ;;
esac

# Compute which packages aren't already installed.
MISSING=()
for pkg in "${PACKAGES[@]}"; do
    pacman -Qi "$pkg" &>/dev/null || MISSING+=("$pkg")
done

PACKAGES_NEWLY_INSTALLED=false
if [ ${#MISSING[@]} -gt 0 ]; then
    info "Installing ${#MISSING[@]} missing package(s): ${MISSING[*]}"
    sudo -u "$GAMING_USER" -H paru -S --needed --noconfirm --skipreview "${MISSING[@]}"
    PACKAGES_NEWLY_INSTALLED=true
    info "Packages installed."
else
    info "All packages already present, skipping installation."
fi

# ---------------------------------------------------------------------------
# 2. Deploy /etc configuration files
# ---------------------------------------------------------------------------

step "Deploying /etc configuration"

# GameCube USB adapter — prevent usbhid from claiming the device so Dolphin
# can open it via libusb.
install -Dm644 "$SCRIPT_DIR/etc/modprobe.d/gcadapter.conf" \
    /etc/modprobe.d/starch-gcadapter.conf
info "  /etc/modprobe.d/starch-gcadapter.conf"

# GPU kernel module options and early initramfs loading — choose the variant
# that matches the detected/selected hardware profile. Each profile gets its
# own filename so switching profiles on the same machine never leaves a stale
# config behind (we also clean up the unused variant below).
case "$HW_PROFILE" in
    optimus)
        MODPROBE_SRC="$SCRIPT_DIR/etc/modprobe.d/nvidia-optimus.conf"
        MKINIT_SRC="$SCRIPT_DIR/etc/mkinitcpio.conf.d/nvidia-optimus.conf"
        MODPROBE_DST="/etc/modprobe.d/starch-nvidia.conf"
        MKINIT_DST="/etc/mkinitcpio.conf.d/starch-nvidia.conf"
        STALE_MODPROBE="/etc/modprobe.d/starch-amdgpu.conf"
        STALE_MKINIT="/etc/mkinitcpio.conf.d/starch-amdgpu.conf"
        ;;
    nvidia)
        MODPROBE_SRC="$SCRIPT_DIR/etc/modprobe.d/nvidia.conf"
        MKINIT_SRC="$SCRIPT_DIR/etc/mkinitcpio.conf.d/nvidia.conf"
        MODPROBE_DST="/etc/modprobe.d/starch-nvidia.conf"
        MKINIT_DST="/etc/mkinitcpio.conf.d/starch-nvidia.conf"
        STALE_MODPROBE="/etc/modprobe.d/starch-amdgpu.conf"
        STALE_MKINIT="/etc/mkinitcpio.conf.d/starch-amdgpu.conf"
        ;;
    amd)
        MODPROBE_SRC="$SCRIPT_DIR/etc/modprobe.d/amdgpu.conf"
        MKINIT_SRC="$SCRIPT_DIR/etc/mkinitcpio.conf.d/amdgpu.conf"
        MODPROBE_DST="/etc/modprobe.d/starch-amdgpu.conf"
        MKINIT_DST="/etc/mkinitcpio.conf.d/starch-amdgpu.conf"
        STALE_MODPROBE="/etc/modprobe.d/starch-nvidia.conf"
        STALE_MKINIT="/etc/mkinitcpio.conf.d/starch-nvidia.conf"
        ;;
esac

STARCH_FORCE_INITRAMFS=0
for stale in "$STALE_MODPROBE" "$STALE_MKINIT"; do
    if [ -e "$stale" ]; then
        rm -f "$stale"
        info "  Removed stale $stale (profile switched)"
        STARCH_FORCE_INITRAMFS=1
    fi
done

install -Dm644 "$MODPROBE_SRC" "$MODPROBE_DST"
info "  $MODPROBE_DST ($HW_PROFILE)"

if ! cmp -s "$MKINIT_SRC" "$MKINIT_DST" 2>/dev/null; then
    STARCH_FORCE_INITRAMFS=1
fi
install -Dm644 "$MKINIT_SRC" "$MKINIT_DST"
info "  $MKINIT_DST ($HW_PROFILE)"

# Record the selected profile so the session launcher scripts know how to
# configure gamescope / wlroots at runtime.
install -d -m755 /etc/starch
cat > /etc/starch/profile.conf <<EOF
# starch hardware profile — regenerated by install.sh.
# Values: nvidia | optimus | amd
STARCH_PROFILE=$HW_PROFILE
EOF
info "  /etc/starch/profile.conf (STARCH_PROFILE=$HW_PROFILE)"

# Input device / uinput udev rules
install -Dm644 "$SCRIPT_DIR/etc/udev/rules.d/70-gaming.conf" \
    /etc/udev/rules.d/70-starch-gaming.rules
info "  /etc/udev/rules.d/70-starch-gaming.rules"

# Kernel sysctl tweaks (swappiness, inotify, max_map_count)
install -Dm644 "$SCRIPT_DIR/etc/sysctl.d/99-gaming.conf" \
    /etc/sysctl.d/99-starch-gaming.conf
info "  /etc/sysctl.d/99-starch-gaming.conf"

# Gamemode daemon configuration — GPU-specific tunables (NVIDIA powermizer
# vs amdgpu DPM). Falls back to the NVIDIA variant on optimus since that's
# where the game actually renders.
case "$HW_PROFILE" in
    amd) GAMEMODE_SRC="$SCRIPT_DIR/etc/gamemode-amd.ini" ;;
    *)   GAMEMODE_SRC="$SCRIPT_DIR/etc/gamemode-nvidia.ini" ;;
esac
install -Dm644 "$GAMEMODE_SRC" /etc/gamemode.ini
info "  /etc/gamemode.ini ($HW_PROFILE)"

# NetworkManager — use iwd as WiFi backend + ensure all interfaces are managed
install -Dm644 "$SCRIPT_DIR/etc/NetworkManager/conf.d/iwd-backend.conf" \
    /etc/NetworkManager/conf.d/iwd-backend.conf
info "  /etc/NetworkManager/conf.d/iwd-backend.conf"
install -Dm644 "$SCRIPT_DIR/etc/NetworkManager/conf.d/starch.conf" \
    /etc/NetworkManager/conf.d/starch.conf
info "  /etc/NetworkManager/conf.d/starch.conf"

# SDDM display manager — Wayland greeter mode (template the default user)
sed "s/@@GAMING_USER@@/$GAMING_USER/" "$SCRIPT_DIR/etc/sddm.conf.d/10-wayland.conf" \
    | install -Dm644 /dev/stdin /etc/sddm.conf.d/10-wayland.conf
info "  /etc/sddm.conf.d/10-wayland.conf (DefaultUser=$GAMING_USER)"

# SDDM theme — starch
find "$SCRIPT_DIR/etc/sddm/themes/starch" -type f | while read -r src; do
    dst="/usr/share/sddm/themes/starch/${src#$SCRIPT_DIR/etc/sddm/themes/starch/}"
    install -Dm644 "$src" "$dst"
    info "  $dst"
done

# ---------------------------------------------------------------------------
# 3. Session launcher scripts
# ---------------------------------------------------------------------------

step "Installing session scripts"

# Shared helper library sourced by every start-* script. Centralises profile
# detection, GPU environment variables, and primary-output resolution.
install -Dm644 "$SCRIPT_DIR/scripts/starch-profile.sh" \
    /usr/local/lib/starch/profile.sh
info "  /usr/local/lib/starch/profile.sh"

install -Dm755 "$SCRIPT_DIR/scripts/start-steam" \
    /usr/local/bin/start-steam
info "  /usr/local/bin/start-steam"

install -Dm755 "$SCRIPT_DIR/scripts/start-river" \
    /usr/local/bin/start-river
info "  /usr/local/bin/start-river"

install -Dm755 "$SCRIPT_DIR/scripts/start-plex" \
    /usr/local/bin/start-plex
info "  /usr/local/bin/start-plex"

install -Dm755 "$SCRIPT_DIR/scripts/starch-select-display" \
    /usr/local/bin/starch-select-display
info "  /usr/local/bin/starch-select-display"

# NVIDIA flatpak GL extension sync — only relevant when nvidia-utils is
# installed. On AMD remove any leftover hook/script from a previous profile.
if [ "$HW_PROFILE" != "amd" ]; then
    install -Dm755 "$SCRIPT_DIR/scripts/nvidia-flatpak-gl-sync" \
        /usr/local/bin/nvidia-flatpak-gl-sync
    info "  /usr/local/bin/nvidia-flatpak-gl-sync"

    install -Dm644 "$SCRIPT_DIR/etc/pacman.d/hooks/nvidia-flatpak-gl.hook" \
        /etc/pacman.d/hooks/nvidia-flatpak-gl.hook
    info "  /etc/pacman.d/hooks/nvidia-flatpak-gl.hook"
else
    for f in /usr/local/bin/nvidia-flatpak-gl-sync \
             /etc/pacman.d/hooks/nvidia-flatpak-gl.hook; do
        if [ -e "$f" ]; then
            rm -f "$f"
            info "  Removed $f (amd profile)"
        fi
    done
fi

install -Dm755 "$SCRIPT_DIR/scripts/steamos-session-select" \
    /usr/bin/steamos-session-select
info "  /usr/bin/steamos-session-select"

# ---------------------------------------------------------------------------
# 4. Flatpak — add Flathub and install Plex HTPC
# ---------------------------------------------------------------------------

step "Configuring Flatpak and installing Plex HTPC"

flatpak remote-add --system --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
info "  Flathub remote present"

if flatpak info --system tv.plex.PlexHTPC &>/dev/null; then
    info "  tv.plex.PlexHTPC already installed, skipping"
else
    flatpak install --system --noninteractive flathub tv.plex.PlexHTPC
    info "  tv.plex.PlexHTPC installed"
fi

# Install the matching NVIDIA GL runtime extension so flatpak apps can use
# the host NVIDIA driver. AMD systems use the default org.freedesktop.Platform
# GL runtime (Mesa) which Flathub ships out of the box — nothing to do.
if [ "$HW_PROFILE" != "amd" ]; then
    RAW_VER=$(modinfo -F version nvidia 2>/dev/null | head -1)
    if [ -n "$RAW_VER" ]; then
        NVIDIA_EXT="org.freedesktop.Platform.GL.nvidia-$(echo "$RAW_VER" | tr '.' '-')"
        if flatpak info --system "$NVIDIA_EXT" &>/dev/null; then
            info "  $NVIDIA_EXT already installed, skipping"
        else
            flatpak install --system --noninteractive flathub "$NVIDIA_EXT" \
                && info "  $NVIDIA_EXT installed" \
                || warn "  Could not install $NVIDIA_EXT — Plex GPU acceleration may not work"
        fi
        NVIDIA_EXT32="${NVIDIA_EXT/GL.nvidia/GL32.nvidia}"
        if flatpak info --system "$NVIDIA_EXT32" &>/dev/null; then
            info "  $NVIDIA_EXT32 already installed, skipping"
        else
            flatpak install --system --noninteractive flathub "$NVIDIA_EXT32" \
                && info "  $NVIDIA_EXT32 installed" \
                || warn "  Could not install $NVIDIA_EXT32 (non-fatal)"
        fi
    else
        warn "  Could not detect NVIDIA driver version — skipping flatpak GL extension install"
        warn "  Manually run: flatpak install flathub org.freedesktop.Platform.GL.nvidia-<major-minor>"
    fi
else
    info "  amd profile: using the default Mesa GL runtime (no NVIDIA extension needed)"
fi

# ---------------------------------------------------------------------------
# 5. SteamOS compatibility helpers
# ---------------------------------------------------------------------------

step "Installing SteamOS compatibility helpers"

STEAMOS_GUIDE_REPO="/tmp/steam-using-gamescope-guide"
if [ -d "$STEAMOS_GUIDE_REPO" ]; then
    (cd "$STEAMOS_GUIDE_REPO" && git pull -q origin main 2>/dev/null) || true
else
    git clone -q https://github.com/shahnawazshahin/steam-using-gamescope-guide.git "$STEAMOS_GUIDE_REPO" 2>/dev/null || {
        warn "Could not clone steamos helper scripts from GitHub. Skipping optional helpers."
        STEAMOS_GUIDE_REPO=""
    }
fi

if [ -n "$STEAMOS_GUIDE_REPO" ] && [ -d "$STEAMOS_GUIDE_REPO/usr/bin" ]; then
    install -Dm755 "$STEAMOS_GUIDE_REPO/usr/bin/steamos-update" \
        /usr/local/bin/steamos-update
    info "  /usr/local/bin/steamos-update"

    install -Dm755 "$STEAMOS_GUIDE_REPO/usr/bin/jupiter-biosupdate" \
        /usr/local/bin/jupiter-biosupdate
    info "  /usr/local/bin/jupiter-biosupdate"

    install -Dm755 "$STEAMOS_GUIDE_REPO/usr/bin/steamos-polkit-helpers/steamos-update" \
        /usr/local/bin/steamos-polkit-helpers/steamos-update
    info "  /usr/local/bin/steamos-polkit-helpers/steamos-update"

    install -Dm755 "$STEAMOS_GUIDE_REPO/usr/bin/steamos-polkit-helpers/jupiter-biosupdate" \
        /usr/local/bin/steamos-polkit-helpers/jupiter-biosupdate
    info "  /usr/local/bin/steamos-polkit-helpers/jupiter-biosupdate"

    install -Dm755 "$STEAMOS_GUIDE_REPO/usr/bin/steamos-polkit-helpers/steamos-set-timezone" \
        /usr/local/bin/steamos-polkit-helpers/steamos-set-timezone
    info "  /usr/local/bin/steamos-polkit-helpers/steamos-set-timezone"
else
    warn "SteamOS helper scripts not available. These are optional but recommended."
fi

# ---------------------------------------------------------------------------
# 6. Wayland session descriptors (picked up by SDDM)
# ---------------------------------------------------------------------------

step "Installing Wayland session descriptors"

install -Dm644 "$SCRIPT_DIR/sessions/steam.desktop" \
    /usr/share/wayland-sessions/steam.desktop
info "  /usr/share/wayland-sessions/steam.desktop"

# Overwrites the river package's river.desktop so only one "Desktop" entry
# appears in SDDM. River updates will clobber this — just re-run install.sh.
install -Dm644 "$SCRIPT_DIR/sessions/river.desktop" \
    /usr/share/wayland-sessions/river.desktop
info "  /usr/share/wayland-sessions/river.desktop (overwritten)"

install -Dm644 "$SCRIPT_DIR/sessions/plex.desktop" \
    /usr/share/wayland-sessions/plex.desktop
info "  /usr/share/wayland-sessions/plex.desktop"

# ---------------------------------------------------------------------------
# 7. River configuration
# ---------------------------------------------------------------------------

step "Installing River configuration for $GAMING_USER"

GAMING_HOME=$(eval echo ~"$GAMING_USER")
GAMING_GROUP=$(id -gn "$GAMING_USER")

# Pre-create config directories owned by the user BEFORE install(1) runs.
# install -D creates parent dirs as root when run from a root script, which
# makes ~/.config root-owned and breaks every app that writes to XDG_CONFIG_HOME
# (Firefox, Steam, etc.).
for _dir in \
    "$GAMING_HOME/.config/river" \
    "$GAMING_HOME/.config/xdg-desktop-portal" \
    "$GAMING_HOME/.local/share"; do
    install -dm755 -o "$GAMING_USER" -g "$GAMING_GROUP" "$_dir"
done

install -Dm755 "$SCRIPT_DIR/config/river/init" \
    "$GAMING_HOME/.config/river/init"
chown "$GAMING_USER:$GAMING_GROUP" "$GAMING_HOME/.config/river/init"
info "  $GAMING_HOME/.config/river/init"

# Brave browser Wayland flags (HiDPI + native Wayland rendering)
install -Dm644 "$SCRIPT_DIR/config/brave-flags.conf" \
    "$GAMING_HOME/.config/brave-flags.conf"
chown "$GAMING_USER:$GAMING_GROUP" "$GAMING_HOME/.config/brave-flags.conf"
info "  $GAMING_HOME/.config/brave-flags.conf"

# XDG Desktop Portal configuration
install -Dm644 "$SCRIPT_DIR/config/xdg-desktop-portal/portals.conf" \
    "$GAMING_HOME/.config/xdg-desktop-portal/portals.conf"
chown "$GAMING_USER:$GAMING_GROUP" "$GAMING_HOME/.config/xdg-desktop-portal/portals.conf"
info "  $GAMING_HOME/.config/xdg-desktop-portal/portals.conf"

# Fix ownership of ~/.config and all parent dirs that install(1) may have
# created as root in this or previous runs.
chown "$GAMING_USER:$GAMING_GROUP" "$GAMING_HOME/.config" "$GAMING_HOME/.local" "$GAMING_HOME/.local/share" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 8. User groups
# ---------------------------------------------------------------------------

step "Configuring user groups for $GAMING_USER"

for group in input video audio seat gamemode lp; do
    if getent group "$group" &>/dev/null; then
        usermod -aG "$group" "$GAMING_USER"
        info "  Added $GAMING_USER to group: $group"
    else
        warn "  Group '$group' does not exist — skipping. (install relevant packages?)"
    fi
done

# ---------------------------------------------------------------------------
# 9. Enable services
# ---------------------------------------------------------------------------

step "Enabling services"

systemctl enable sddm.service
info "  sddm.service enabled"

if ! systemctl is-enabled NetworkManager.service &>/dev/null; then
    systemctl enable NetworkManager.service
    info "  NetworkManager.service enabled"
else
    info "  NetworkManager.service already enabled"
fi

# NVIDIA power management — required when NVreg_PreserveVideoMemoryAllocations=1
# is set (suspend/hibernate/resume) and nvidia-powerd for dynamic clocking on
# Turing+. None of this applies on AMD.
if [ "$HW_PROFILE" != "amd" ]; then
    for svc in nvidia-suspend nvidia-hibernate nvidia-resume nvidia-powerd; do
        if systemctl list-unit-files --quiet "${svc}.service" 2>/dev/null | grep -q "$svc"; then
            systemctl enable "${svc}.service"
            info "  Enabled: ${svc}.service"
        else
            warn "  ${svc}.service not found — install nvidia-utils if not present"
        fi
    done
else
    info "  amd profile: skipping nvidia-* power-management services"
fi

# ---------------------------------------------------------------------------
# 10. uinput module — load immediately and persist across reboots
# ---------------------------------------------------------------------------

step "Configuring uinput module"

modprobe uinput 2>/dev/null && info "  uinput loaded" || warn "  uinput already loaded or unavailable"

cat > /etc/modules-load.d/starch-uinput.conf << 'EOF'
# Load uinput on boot for Steam Input virtual controller support
uinput
EOF
info "  /etc/modules-load.d/starch-uinput.conf"

udevadm control --reload-rules
udevadm trigger
info "  udev rules reloaded"

# ---------------------------------------------------------------------------
# 11. Apply sysctl settings
# ---------------------------------------------------------------------------

step "Applying sysctl settings"
sysctl --system &>/dev/null && info "  sysctl settings applied" || warn "  sysctl apply had warnings (non-fatal)"

# ---------------------------------------------------------------------------
# 12. Rebuild initramfs
# ---------------------------------------------------------------------------

if [ "$PACKAGES_NEWLY_INSTALLED" = "true" ] || [ "${STARCH_FORCE_INITRAMFS:-0}" = "1" ]; then
    step "Rebuilding initramfs"
    info "  Running mkinitcpio -P (this will take a moment)..."
    mkinitcpio -P
    info "  Initramfs rebuilt."
else
    info "Skipping initramfs rebuild (no new packages installed)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "================================================================"
info "starch installation complete!"
echo "================================================================"
echo ""
echo "  Hardware profile: $HW_PROFILE"
case "$HW_PROFILE" in
    optimus)
        echo "    BIOS: leave graphics set to 'Hybrid / Optimus' (NOT Discrete only)."
        echo "    Intel iGPU drives displays; NVIDIA handles PRIME render offload."
        ;;
    nvidia)
        echo "    BIOS: set graphics to 'Discrete GPU Only' if available."
        ;;
    amd)
        echo "    amdgpu drives both scanout and rendering. No NVIDIA stack involved."
        ;;
esac
echo ""

if [ "$HW_PROFILE" != "amd" ]; then
    echo "  Before rebooting, verify your bootloader kernel cmdline contains:"
    echo "    nvidia_drm.modeset=1"
    if ! grep -q 'nvidia_drm\.modeset=1' /proc/cmdline 2>/dev/null; then
        warn "  Current /proc/cmdline is missing nvidia_drm.modeset=1 — add it before rebooting."
    fi
    echo ""
fi
echo "  REBOOT to apply:"
echo "    - Early module loading (mkinitcpio change)"
echo "    - Group membership changes for $GAMING_USER"
echo ""
echo "  After rebooting:"
echo "    1. Select 'Steam', 'Plex', or 'Desktop' from SDDM"
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
echo "  Switch to Desktop from Steam's power menu returns to SDDM."
echo ""
echo "  If you need to troubleshoot, check:"
echo "    - Kernel logs: dmesg | grep -i nvidia"
echo "    - SDDM logs: journalctl -u sddm -b"
echo "    - Steam session log: ~/.local/share/steam-session.log"
echo ""
