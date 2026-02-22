# starch

Post-OS setup for gaming and desktop on Arch Linux with NVIDIA discrete GPU.
Includes a SteamOS-like console session (`start-steam`) and River window manager configuration.

**Hardware target:** Lenovo Legion Pro 7 Gen 8 (Intel 13900HX + RTX 4090 Mobile)

---

## Prerequisites (Base System Setup)

This script assumes you have a **working Arch Linux base** with the following **already in place**:

### Required
- **Base Arch install** with `base linux linux-headers`
- **NVIDIA driver** installed and working (`nvidia-open` recommended for modern cards)
- **NVIDIA kernel module loaded** with `nvidia_drm.modeset=1` (in kernel parameters)
- **BIOS set to Discrete GPU Only** (not Hybrid mode)
- **Display manager** with Wayland session support (tested with `greetd` + `tuigreet`)
- **Session manager** for seat/VT management (`seatd` for Wayland)
- **User account** with sudo access

### Optional but Recommended
- **paru** — AUR helper for optional packages (if not present, install will warn but continue)
- **Git** — for cloning this repo and fetching helper scripts
- **systemd-boot** — for managing kernel parameters (or any other UEFI bootloader)

### Typical Base Install Flow
1. Install Arch base: `pacstrap -K /mnt base linux linux-headers`
2. Install bootloader and set `nvidia_drm.modeset=1` kernel parameter
3. Install NVIDIA driver: `pacman -S nvidia-open`
4. Install display/session managers: `pacman -S greetd tuigreet seatd`
5. Create your user account and add to sudoers
6. Clone this repo and run `sudo bash install.sh`

---

## What this does

Sets up the complete post-OS configuration for this machine:

1. **Steam** — A Wayland session that launches `gamescope → Steam` in Big Picture mode, taking direct DRM ownership for a couch-friendly, controller-first experience on bare metal.

2. **River window manager** — Tiling Wayland compositor with configuration for dual-GPU laptop usage (integrated for desktop/browser, discrete for games).

3. **System configuration** — NVIDIA module options, udev rules, sysctl tweaks, gamemode config.

```
tuigreet / login
├── River          (window manager + desktop environment)
└── Steam
        └── gamescope (fullscreen Wayland server)
                └── steam -gamepadui
```

---

## Quick Start

**Prerequisites:** You have a working Arch Linux base install with NVIDIA driver, greetd, and seatd (see [Prerequisites](#prerequisites-base-system-setup) above).

```bash
# 1. Clone this repo
git clone https://github.com/your-username/starch.git
cd starch

# 2. (Optional) Review what will be installed
cat README.md

# 3. Run the installer as root
# It will ask for your username to configure for gaming
sudo bash install.sh

# 4. Reboot
sudo reboot

# 5. At tuigreet, select either:
#    - "Steam" for gaming
#    - "Desktop" for River window manager
```

The installer will:
- Install packages via pacman and optionally paru (AUR)
- Deploy NVIDIA, gamemode, sysctl, and udev configurations
- Install start-steam and start-river launcher scripts
- Create Wayland session files for greetd/tuigreet
- Configure your user's River configuration
- Fetch SteamOS compatibility helpers from the upstream guide repo

---

## File overview

```
starch/
├── README.md
├── install.sh                                     — Installer (run as root)
├── scripts/
│   ├── start-steam                              — gamescope+Steam launcher
│   └── start-river                              — River window manager launcher
├── sessions/
│   ├── steam.desktop                     — Wayland session for tuigreet
│   └── desktop.desktop                          — Desktop (River) session for tuigreet
├── config/
│   └── river/init                               — River keybindings + workspace config
└── etc/
    ├── greetd/config.toml                       → /etc/greetd/config.toml
    ├── gamemode.ini                             → /etc/gamemode.ini
    ├── modprobe.d/nvidia.conf                   → /etc/modprobe.d/starch-nvidia.conf
    ├── mkinitcpio.conf.d/nvidia.conf            → /etc/mkinitcpio.conf.d/starch-nvidia.conf
    ├── sysctl.d/99-gaming.conf                  → /etc/sysctl.d/99-starch-gaming.conf
    └── udev/rules.d/70-gaming.conf              → /etc/udev/rules.d/70-starch-gaming.rules

## What gets installed where

| Source | Destination | Purpose |
|--------|-------------|---------|
| `scripts/start-steam` | `/usr/local/bin/start-steam` | Gaming session launcher |
| `scripts/start-river` | `/usr/local/bin/start-river` | Desktop session launcher |
| `sessions/*.desktop` | `/usr/share/wayland-sessions/` | Registered sessions for tuigreet |
| `config/river/init` | `~$USER/.config/river/init` | River keybindings for gaming user |
| `etc/greetd/config.toml` | `/etc/greetd/config.toml` | Login manager config |
| `etc/gamemode.ini` | `/etc/gamemode.ini` | Gamemode daemon config |
| `etc/modprobe.d/nvidia.conf` | `/etc/modprobe.d/starch-nvidia.conf` | NVIDIA driver options |
| `etc/mkinitcpio.conf.d/nvidia.conf` | `/etc/mkinitcpio.conf.d/starch-nvidia.conf` | Early module loading |
| `etc/sysctl.d/99-gaming.conf` | `/etc/sysctl.d/99-starch-gaming.conf` | Kernel tuning |
| `etc/udev/rules.d/70-gaming.conf` | `/etc/udev/rules.d/70-starch-gaming.rules` | Input device permissions |
| (cloned from upstream) | `/usr/local/bin/steamos-*` | SteamOS compatibility stubs |
```

---

## Installation Details

The `install.sh` script handles all setup automatically. Here's what it does step-by-step:

### 1. Preflight Checks
- Verifies running as root
- Confirms the target user exists
- Checks for paru (AUR helper) — warns if missing but continues

### 2. Package Installation
Installs via pacman (and paru for AUR packages):
- **Core:** gamescope, steam, nvidia drivers, Vulkan support, Wayland/X11 libs
- **Audio:** pipewire, wireplumber, pipewire-pulse, pipewire-alsa
- **Gaming:** gamemode, mangohud, libdrm
- **Optional (AUR):** xpadneo-dkms for Xbox controller support

See the `install.sh` PACKAGES array for the full list.

### 3. System Configuration
Deploys to `/etc/`:
- **NVIDIA module options:** early loading, suspend preservation, GBM backend config
- **udev rules:** input device and uinput permissions
- **sysctl tweaks:** swappiness, inotify limits, memory mapping
- **Gamemode config:** NVIDIA power settings
- **greetd config:** login manager with tuigreet

### 4. User Group Configuration
Adds gaming user to: `input`, `video`, `audio`, `seat`, `gamemode`

These grants access to:
| Group | Access |
|-------|--------|
| `input` | Raw gamepad events and uinput (virtual controllers) |
| `video` | DRM/KMS display devices |
| `audio` | Audio devices (supplements Pipewire) |
| `seat` | Session/VT management (needed for Wayland) |
| `gamemode` | Request performance profile changes |

### 5. uinput Module
Loads immediately and persists via `/etc/modules-load.d/starch-uinput.conf`

### 6. NVIDIA Power Management Services
Enables `nvidia-suspend`, `nvidia-hibernate`, `nvidia-resume` (required for suspend-to-RAM safety)

### 7. Initramfs Rebuild
Runs `mkinitcpio -P` to apply early NVIDIA module loading

### 8. Helper Scripts
Clones and installs SteamOS compatibility stubs from upstream guide repo

### 9. First Launch (After Reboot)

At tuigreet, select **Steam**:
1. Let Steam update on first run (may take a few minutes)
2. **Settings → Compatibility:** Enable Steam Play for all titles, select Proton version
3. **Settings → Controller:** Enable controller configuration support
4. **Settings → Display:** Disable VSync if you have frame rate issues
5. Update driver and Proton via Steam if prompted

---

## Architecture: why these choices

### gamescope as DRM master

gamescope takes direct ownership of the display hardware via DRM/KMS, eliminating
the need for an intermediate compositor (like cage). This provides:
- Lower latency and fewer composition layers
- Direct KMS scanout via fullscreen flag (`-f`)
- Stable, flicker-free rendering on NVIDIA discrete GPU
- Simpler architecture with fewer failure points

### Early NVIDIA module loading

Without the modules in the initramfs, the kernel loads them lazily after the root
filesystem is mounted. By the time greetd starts, the DRM device may not be fully
initialized, causing gamescope to fail or display corruption on first frame.

### `NVreg_PreserveVideoMemoryAllocations=1`

Without this, NVIDIA flushes VRAM on suspend. On resume, the compositor has dangling
pointers into GPU memory and typically freezes or corrupts the display. This option
tells the driver to preserve those allocations across suspend/resume cycles.

### `GBM_BACKEND=nvidia-drm`

Wayland compositors use GBM (Generic Buffer Management) to allocate shared GPU buffers.
By default, Mesa's GBM implementation is used, which does not support NVIDIA properly.
Setting this variable routes GBM through NVIDIA's own implementation.

### `WLR_NO_HARDWARE_CURSORS=1`

NVIDIA's DRM cursor implementation has historically had issues with flickering and
disappearing cursors on some driver versions. This falls back to software cursor
rendering. Performance impact is negligible.

### Gamemode `nv_powermizer_mode=1`

NVIDIA's powermizer can throttle the GPU to save power even under load. In a gaming
session, this creates frame time spikes. Forcing maximum performance state eliminates
this variable.

---

## Troubleshooting

### Flickering

1. Verify early module loading worked:
   ```bash
   lsmod | grep nvidia_drm
   # Should show nvidia_drm loaded (not just nvidia)
   ```

2. Try disabling VRR/immediate flips in `/usr/local/bin/start-steam`:
   comment out `--adaptive-sync` and `--immediate-flips`

3. Check which DRM device gamescope is using — the session script logs this:
   ```bash
   journalctl --user -u greetd -b | grep "steam-session"
   # or enable logging in scripts/start-steam by uncommenting exec 1>/tmp/steam-session.log
   ```

4. Verify NVIDIA owns the display:
   ```bash
   cat /sys/class/drm/card*-eDP-*/status
   # Should show: connected
   cat /sys/class/drm/card*/device/vendor
   # The card showing 0x10de is NVIDIA
   ```

### Controller not working

1. Check uinput permissions:
   ```bash
   ls -la /dev/uinput          # should be crw-rw---- root input
   groups                      # your user should include 'input'
   ```

2. Reload udev rules after installing:
   ```bash
   sudo udevadm control --reload-rules && sudo udevadm trigger
   ```

3. Check Steam Input is enabled in Steam Settings → Controller

4. For Xbox controllers: install `xpadneo-dkms` from AUR

### Steam doesn't start / crashes immediately

- Verify `lib32-nvidia-utils` is installed (32-bit NVIDIA libs are required)
- Check `vulkan-icd-loader` and `lib32-vulkan-icd-loader` are present
- Run Steam manually from a terminal first to see error output:
  ```bash
  GBM_BACKEND=nvidia-drm __GLX_VENDOR_LIBRARY_NAME=nvidia steam -tenfoot
  ```

### Audio not working

- Ensure `pipewire`, `pipewire-pulse`, and `wireplumber` are installed
- If using a non-systemd session: the session script starts Pipewire manually;
  check if it's running: `pgrep -u $USER pipewire`

### Session not appearing in tuigreet

- Verify the desktop file is in `/usr/share/wayland-sessions/`:
  ```bash
  ls /usr/share/wayland-sessions/
  ```
- Check tuigreet config in `/etc/greetd/config.toml` — ensure it's set to scan
  `/usr/share/wayland-sessions/` for sessions

---

## Performance overlay (MangoHud)

To verify NVIDIA Vulkan is being used and monitor frame times:

```bash
# Edit scripts/start-steam and add before the exec line:
export MANGOHUD=1
export MANGOHUD_CONFIG=fps,frametime,gpu_name,gpu_load,vram,cpu_load,ram
```

Or enable it per-game in Steam launch options: `MANGOHUD=1 %command%`

---

## Attribution

This project includes SteamOS compatibility helper scripts from [shahnawazshahin/steam-using-gamescope-guide](https://github.com/shahnawazshahin/steam-using-gamescope-guide), cloned during installation to provide stubs for system update checks and BIOS updates. These scripts are essential for Steam's SteamOS compatibility features to work correctly.

---

## Adding your own configurations

This repo is organized to support multiple subsystems:

- **Gaming session**: `scripts/start-steam` + `sessions/steam.desktop`
- **Desktop session (River)**: `scripts/start-river` + `config/river/` (add these yourself)
- **System configs**: Files in `etc/` get deployed to `/etc/` and `/etc/modprobe.d/`, etc.

To add a new session or script:
1. Create the script in `scripts/`
2. Create a `.desktop` file in `sessions/` if it needs to appear in login managers
3. Add deployment instructions to `install.sh`
4. Document in this README
