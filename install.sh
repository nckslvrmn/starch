#!/bin/bash
# install.sh — Deploy starch gaming session to an Arch Linux system
#
# Run as root from the starch/ directory:
#   sudo bash install.sh
#
# Or specify a username directly:
#   sudo GAMING_USER=myuser bash install.sh

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
# 1. Packages
# ---------------------------------------------------------------------------

step "Installing packages"

PACKAGES=(
    # Gamescope — Valve's micro-compositor, runs as DRM master
    gamescope

    # Steam client
    steam

    # NVIDIA userspace (32-bit libs needed for most games via Proton/WINE)
    lib32-nvidia-utils

    # Vulkan
    vulkan-icd-loader
    lib32-vulkan-icd-loader

    # Mesa 32-bit (fallback for non-Vulkan paths in older games)
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

    # kmsprint — used by start-steam to detect display resolution
    libdrm

    # AUR: improved Xbox controller driver (rumble, adaptive triggers,
    # better Bluetooth reliability vs the in-kernel xpad module)
    xpadneo-dkms
)

# paru refuses to run as root; invoke it as the gaming user.
# -H sets HOME to the user's home so paru uses the correct cache/config.
# --skipreview suppresses the AUR PKGBUILD diff prompt for non-interactive use.
sudo -u "$GAMING_USER" -H paru -S --needed --noconfirm --skipreview "${PACKAGES[@]}"

info "Packages installed."

# ---------------------------------------------------------------------------
# 2. Deploy /etc configuration files
# ---------------------------------------------------------------------------

step "Deploying /etc configuration"

# NVIDIA kernel module options (fbdev, NVreg tweaks, suspend preservation)
install -Dm644 "$SCRIPT_DIR/etc/modprobe.d/nvidia.conf" \
    /etc/modprobe.d/starch-nvidia.conf
info "  /etc/modprobe.d/starch-nvidia.conf"

# Early NVIDIA module loading in initramfs
install -Dm644 "$SCRIPT_DIR/etc/mkinitcpio.conf.d/nvidia.conf" \
    /etc/mkinitcpio.conf.d/starch-nvidia.conf
info "  /etc/mkinitcpio.conf.d/starch-nvidia.conf"

# Input device / uinput udev rules
install -Dm644 "$SCRIPT_DIR/etc/udev/rules.d/70-gaming.conf" \
    /etc/udev/rules.d/70-starch-gaming.rules
info "  /etc/udev/rules.d/70-starch-gaming.rules"

# Kernel sysctl tweaks (swappiness, inotify, max_map_count)
install -Dm644 "$SCRIPT_DIR/etc/sysctl.d/99-gaming.conf" \
    /etc/sysctl.d/99-starch-gaming.conf
info "  /etc/sysctl.d/99-starch-gaming.conf"

# Gamemode daemon configuration
install -Dm644 "$SCRIPT_DIR/etc/gamemode.ini" \
    /etc/gamemode.ini
info "  /etc/gamemode.ini"

# greetd login manager configuration (tuigreet with --time --remember --asterisks)
install -Dm644 "$SCRIPT_DIR/etc/greetd/config.toml" \
    /etc/greetd/config.toml
info "  /etc/greetd/config.toml"

# ---------------------------------------------------------------------------
# 3. Session launcher script
# ---------------------------------------------------------------------------

step "Installing start-steam"

install -Dm755 "$SCRIPT_DIR/scripts/start-steam" \
    /usr/local/bin/start-steam
info "  /usr/local/bin/start-steam"

install -Dm755 "$SCRIPT_DIR/scripts/start-river" \
    /usr/local/bin/start-river
info "  /usr/local/bin/start-river"

# ---------------------------------------------------------------------------
# 3b. SteamOS compatibility helpers (from shahnawazshahin/steam-using-gamescope-guide)
# ---------------------------------------------------------------------------

step "Installing SteamOS compatibility helpers"

# Clone/update the source repository
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
# 4. Wayland session descriptors (picked up by greetd/tuigreet)
# ---------------------------------------------------------------------------

step "Installing Wayland session descriptors"

install -Dm644 "$SCRIPT_DIR/sessions/steam.desktop" \
    /usr/share/wayland-sessions/steam.desktop
info "  /usr/share/wayland-sessions/steam.desktop"

install -Dm644 "$SCRIPT_DIR/sessions/desktop.desktop" \
    /usr/share/wayland-sessions/desktop.desktop
info "  /usr/share/wayland-sessions/desktop.desktop"

# ---------------------------------------------------------------------------
# 4b. River configuration
# ---------------------------------------------------------------------------

step "Installing River configuration for $GAMING_USER"

GAMING_HOME=$(eval echo ~"$GAMING_USER")
GAMING_GROUP=$(id -gn "$GAMING_USER")
install -Dm755 "$SCRIPT_DIR/config/river/init" \
    "$GAMING_HOME/.config/river/init"
chown "$GAMING_USER:$GAMING_GROUP" "$GAMING_HOME/.config/river/init"
info "  $GAMING_HOME/.config/river/init"

# ---------------------------------------------------------------------------
# 5. User groups
# ---------------------------------------------------------------------------

step "Configuring user groups for $GAMING_USER"

for group in input video audio seat gamemode; do
    if getent group "$group" &>/dev/null; then
        usermod -aG "$group" "$GAMING_USER"
        info "  Added $GAMING_USER to group: $group"
    else
        warn "  Group '$group' does not exist — skipping. (install relevant packages?)"
    fi
done

# ---------------------------------------------------------------------------
# 6. uinput module — load immediately and persist across reboots
# ---------------------------------------------------------------------------

step "Configuring uinput module"

modprobe uinput 2>/dev/null && info "  uinput loaded" || warn "  uinput already loaded or unavailable"

cat > /etc/modules-load.d/starch-uinput.conf << 'EOF'
# Load uinput on boot for Steam Input virtual controller support
uinput
EOF
info "  /etc/modules-load.d/starch-uinput.conf"

# Reload udev rules so controller rules take effect immediately
udevadm control --reload-rules
udevadm trigger
info "  udev rules reloaded"

# ---------------------------------------------------------------------------
# 7. NVIDIA power management services
# ---------------------------------------------------------------------------

step "Enabling NVIDIA power management services"
# Required when NVreg_PreserveVideoMemoryAllocations=1 is set.
# Without these, suspend/resume will corrupt VRAM and likely freeze the system.

for svc in nvidia-suspend nvidia-hibernate nvidia-resume; do
    if systemctl list-unit-files --quiet "${svc}.service" 2>/dev/null | grep -q "$svc"; then
        systemctl enable "${svc}.service"
        info "  Enabled: ${svc}.service"
    else
        warn "  ${svc}.service not found — install nvidia-utils if not present"
    fi
done

# ---------------------------------------------------------------------------
# 8. Apply sysctl settings immediately (no reboot needed for these)
# ---------------------------------------------------------------------------

step "Applying sysctl settings"
sysctl --system &>/dev/null && info "  sysctl settings applied" || warn "  sysctl apply had warnings (non-fatal)"

# ---------------------------------------------------------------------------
# 9. Rebuild initramfs
# ---------------------------------------------------------------------------

step "Rebuilding initramfs"
info "  Running mkinitcpio -P (this will take a moment)..."
mkinitcpio -P
info "  Initramfs rebuilt."

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "================================================================"
info "starch installation complete!"
echo "================================================================"
echo ""
echo "  Before rebooting, verify your systemd-boot entry contains:"
echo "    nvidia_drm.modeset=1"
echo "  (You indicated this is already set — just confirming.)"
echo ""
echo "  REBOOT to apply:"
echo "    - Early NVIDIA module loading (mkinitcpio change)"
echo "    - Group membership changes for $GAMING_USER"
echo ""
echo "  After rebooting:"
echo "    1. Select 'Steam' or 'Desktop' from tuigreet"
echo "    2. Allow Steam to update on first launch (Steam session only)"
echo "    3. In Steam Settings > Compatibility:"
echo "         Enable 'Steam Play for all titles'"
echo "         Select Proton Experimental or latest stable"
echo "    4. In Steam Settings > Controller:"
echo "         Enable controller configuration support"
echo ""
echo "  If you need to troubleshoot, check:"
echo "    - Kernel logs: dmesg | grep -i nvidia"
echo "    - Session logs: journalctl --user -u greetd -b | grep steam"
echo "    - For detailed session logging, uncomment 'exec 1>/tmp/steam-session.log' in start-steam"
echo ""
