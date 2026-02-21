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

info "Installing starch gaming session for user: $GAMING_USER"

# ---------------------------------------------------------------------------
# 1. Packages
# ---------------------------------------------------------------------------

step "Installing packages"

PACKAGES=(
    # Valve's micro-compositor — the core of this setup
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

    # kmsprint — used by steam-session.sh to detect display resolution
    libdrm
)

pacman -S --needed --noconfirm "${PACKAGES[@]}"

info "Core packages installed."
warn "For better Xbox controller support (rumble, adaptive triggers),"
warn "install 'xpadneo-dkms' from the AUR after this script completes:"
warn "  yay -S xpadneo-dkms  (or your preferred AUR helper)"

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

# ---------------------------------------------------------------------------
# 3. Session launcher script
# ---------------------------------------------------------------------------

step "Installing steam-session.sh"

install -Dm755 "$SCRIPT_DIR/scripts/steam-session.sh" \
    /usr/local/bin/steam-session.sh
info "  /usr/local/bin/steam-session.sh"

# ---------------------------------------------------------------------------
# 4. Wayland session descriptor (picked up by greetd/tuigreet)
# ---------------------------------------------------------------------------

step "Installing Wayland session descriptor"

install -Dm644 "$SCRIPT_DIR/sessions/steam-gaming.desktop" \
    /usr/share/wayland-sessions/steam-gaming.desktop
info "  /usr/share/wayland-sessions/steam-gaming.desktop"

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
echo "    1. Select 'Steam Gaming Session' from tuigreet"
echo "    2. Allow Steam to update on first launch"
echo "    3. In Steam Settings > Compatibility:"
echo "         Enable 'Steam Play for all titles'"
echo "         Select Proton Experimental or latest stable"
echo "    4. In Steam Settings > Controller:"
echo "         Enable controller configuration support"
echo ""
echo "  ANTI-FLICKER:"
echo "    If flickering occurs after reboot, edit:"
echo "      /usr/local/bin/steam-session.sh"
echo "    Comment out --adaptive-sync and/or --immediate-flips"
echo ""
echo "  AUR package (optional, for Xbox controller rumble/triggers):"
echo "    yay -S xpadneo-dkms"
echo ""
