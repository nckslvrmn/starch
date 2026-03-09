# starch

Post-OS setup for a SteamOS-like console session and River window manager on Arch Linux.
Supports both NVIDIA discrete GPU and AMD integrated GPU configurations.

**Hardware targets:**
- Lenovo Legion Pro 7 Gen 8 — Intel 13900HX + RTX 4090 Mobile (discrete-only mode)
- Lenovo laptop — AMD Radeon 7730U iGPU, external display via HDMI

---

## Prerequisites (Base System Setup)

This installer assumes a **working Arch Linux base** with the following **already in place**:

### Required (both systems)
- **Base Arch install** with `base linux linux-headers`
- **GPU driver** installed and working
  - NVIDIA: `nvidia-open` recommended for modern cards
  - AMD: `mesa` (amdgpu loads automatically)
- **User account** with sudo access
- **paru** — AUR helper (required for `xpadneo-dkms`)

### Required (NVIDIA only)
- **NVIDIA kernel module** loaded with `nvidia_drm.modeset=1` (in kernel parameters)
- **BIOS set to Discrete GPU Only** (not Hybrid/Optimus mode)

### Optional but Recommended
- **Git** — for cloning this repo
- **systemd-boot** — for managing kernel parameters

### Typical Base Install Flow

**NVIDIA:**
1. Install Arch base: `pacstrap -K /mnt base linux linux-headers`
2. Install bootloader and set `nvidia_drm.modeset=1` kernel parameter
3. Install NVIDIA driver: `pacman -S nvidia-open`
4. Create user, add to sudoers, install paru
5. Clone this repo and run `sudo bash install.sh`

**AMD:**
1. Install Arch base: `pacstrap -K /mnt base linux linux-headers mesa`
2. Create user, add to sudoers, install paru
3. Clone this repo and run `sudo bash install.sh`

---

## What this does

Sets up the complete post-OS configuration for a gaming machine:

1. **Steam session** — A Wayland session that launches `gamescope → Steam` in Big Picture mode with HDR enabled, taking direct DRM ownership for a couch-friendly, controller-first experience on bare metal. When exited, falls back to the River desktop session.

2. **River window manager** — Tiling Wayland compositor with GPU-aware display configuration via `wlr-randr`.

3. **SDDM display manager** — Runs in Wayland mode with a custom "starch" dark theme. Handles DRM master handoff, PipeWire/audio startup via systemd user session, and session selection.

4. **System configuration** — GPU-specific module options, udev rules, sysctl tweaks, gamemode config, GameCube adapter support (Dolphin).

```
SDDM (Wayland, starch theme)
├── Desktop  →  start-river  →  river (+ wlr-randr display config on init)
└── Steam    →  start-steam  →  gamescope (DRM master, HDR) → steam -gamepadui
                                    └── (on exit) → start-river
```

---

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/your-username/starch.git
cd starch

# 2. Run the installer as root
#    It detects your GPU automatically and asks for your username
sudo bash install.sh

# 3. Reboot
sudo reboot

# 4. At SDDM, select either:
#    - "Steam"   for the gaming session
#    - "Desktop" for River window manager
```

The installer:
- Detects your GPU (NVIDIA or AMD) and installs the appropriate packages
- Deploys system configuration files conditionally based on GPU
- Installs `start-steam` and `start-river` launcher scripts
- Installs and enables SDDM with the custom starch theme
- Creates Wayland session files for SDDM
- Configures your user's River init script (with automatic display setup)
- Fetches SteamOS compatibility helpers from the upstream guide repo

---

## File Overview

```
starch/
├── README.md
├── install.sh                          — Installer (run as root, auto-detects GPU)
├── scripts/
│   ├── start-steam                     — gamescope+Steam session launcher
│   └── start-river                     — River window manager launcher
├── sessions/
│   ├── steam.desktop                   — "Steam" entry in SDDM
│   └── desktop.desktop                 — "Desktop" entry in SDDM
├── config/
│   └── river/init                      — River display config + keybindings
└── etc/
    ├── sddm.conf.d/10-wayland.conf     → /etc/sddm.conf.d/10-wayland.conf
    ├── sddm/themes/starch/             → /usr/share/sddm/themes/starch/
    ├── gamemode.ini                    → /etc/gamemode.ini
    ├── modprobe.d/nvidia.conf          → /etc/modprobe.d/starch-nvidia.conf      (NVIDIA only)
    ├── modprobe.d/gcadapter.conf       → /etc/modprobe.d/starch-gcadapter.conf   (both)
    ├── mkinitcpio.conf.d/nvidia.conf   → /etc/mkinitcpio.conf.d/starch-nvidia.conf (NVIDIA only)
    ├── sysctl.d/99-gaming.conf         → /etc/sysctl.d/99-starch-gaming.conf
    └── udev/rules.d/70-gaming.conf     → /etc/udev/rules.d/70-starch-gaming.rules
```

---

## What Gets Installed Where

| Source | Destination | GPU |
|--------|-------------|-----|
| `scripts/start-steam` | `/usr/local/bin/start-steam` | Both |
| `scripts/start-river` | `/usr/local/bin/start-river` | Both |
| `sessions/*.desktop` | `/usr/share/wayland-sessions/` | Both |
| `config/river/init` | `~$USER/.config/river/init` | Both |
| `etc/sddm.conf.d/10-wayland.conf` | `/etc/sddm.conf.d/10-wayland.conf` | Both |
| `etc/sddm/themes/starch/` | `/usr/share/sddm/themes/starch/` | Both |
| `etc/gamemode.ini` | `/etc/gamemode.ini` | Both |
| `etc/modprobe.d/gcadapter.conf` | `/etc/modprobe.d/starch-gcadapter.conf` | Both |
| `etc/modprobe.d/nvidia.conf` | `/etc/modprobe.d/starch-nvidia.conf` | NVIDIA |
| `etc/mkinitcpio.conf.d/nvidia.conf` | `/etc/mkinitcpio.conf.d/starch-nvidia.conf` | NVIDIA |
| `etc/sysctl.d/99-gaming.conf` | `/etc/sysctl.d/99-starch-gaming.conf` | Both |
| `etc/udev/rules.d/70-gaming.conf` | `/etc/udev/rules.d/70-starch-gaming.rules` | Both |
| (cloned from upstream) | `/usr/local/bin/steamos-*` | Both |

---

## Installation Details

### GPU Detection

`install.sh` reads PCI vendor IDs from `/sys/class/drm/card*/device/vendor` at the start and
branches all GPU-specific logic from that single detection. Every script (`start-steam`,
`start-river`, `river/init`) performs the same runtime detection so they work correctly
regardless of which machine they're running on.

| Vendor ID | GPU | Behaviour |
|-----------|-----|-----------|
| `0x10de` | NVIDIA | GBM/EGL/GLX NVIDIA backend, NVDEC VA-API, NVAPI Proton, hardware cursor workaround |
| `0x1002` | AMD | Mesa radeonsi VA-API, standard Mesa GBM |

### Package Installation

**Universal packages** (installed on all systems):
- `gamescope`, `steam`
- `vulkan-icd-loader`, `lib32-vulkan-icd-loader`, `lib32-mesa`
- `xorg-xwayland`
- `gamemode`, `lib32-gamemode`, `mangohud`, `lib32-mangohud`
- `pipewire`, `pipewire-pulse`, `pipewire-alsa`, `lib32-pipewire`, `wireplumber`
- `wlr-randr` — display output configuration (used by river/init)
- `jq` — JSON parsing for wlr-randr output
- `brightnessctl` — backlight/brightness control (media keys in River)
- `sddm`, `weston`, `qt6-wayland`, `qt6-svg` — display manager and Wayland greeter stack
- `dolphin-emu` — GameCube/Wii emulator (GameCube USB adapter configured via modprobe)
- `xpadneo-dkms` (AUR) — improved Xbox controller driver

**NVIDIA-only packages:**
- `lib32-nvidia-utils` — 32-bit NVIDIA userspace libs (required for most games via Proton)

**AMD-only packages:**
- `vulkan-radeon`, `lib32-vulkan-radeon` — RADV Mesa Vulkan driver
- `libva-mesa-driver`, `lib32-libva-mesa-driver` — VA-API hardware video decode

### User Group Configuration

Adds the gaming user to: `input`, `video`, `audio`, `seat`, `gamemode`

| Group | Access |
|-------|--------|
| `input` | Raw gamepad events and uinput (virtual controllers) |
| `video` | DRM/KMS display devices |
| `audio` | Audio devices (supplements PipeWire) |
| `seat` | Session/VT management (required for Wayland) |
| `gamemode` | Request performance profile changes |

### NVIDIA-Only Steps

These steps are **skipped on AMD** systems:
- Deploy `modprobe.d/nvidia.conf` (kernel module options, suspend preservation)
- Deploy `mkinitcpio.conf.d/nvidia.conf` (early module loading)
- Enable `nvidia-suspend`, `nvidia-hibernate`, `nvidia-resume` systemd services
- Run `mkinitcpio -P` to rebuild the initramfs

---

## How the Sessions Work

### Steam Session (`start-steam`)

**GPU detection:**
Reads PCI vendor from `/sys/class/drm/card*/device/vendor` to identify GPU and determine the DRM device node.

**Refresh rate detection:**
Runs `modetest -D <drm-device>` and uses `awk` to scan connected connectors and pick the highest advertised refresh rate. Passed to gamescope as `-r` so it doesn't cap at 60fps on a high-refresh display.

**Environment:**
Sets GPU-specific environment variables. SDDM and the systemd user session handle DRM master handoff and PipeWire/audio startup before this script runs — no manual setup needed.

**gamescope:**
Launches `gamescope --backend wayland --steam -f --rt --hdr-enabled [-r REFRESH] -- steam -gamepadui`.
Resolution is auto-detected from the EDID preferred mode; `-r` is added only when successfully detected.

**Fallback:**
When the Steam session exits (e.g. via the power menu), the script falls back to `exec start-river`, dropping into the River desktop session.

### Desktop Session (`start-river`)

Detects GPU vendor at launch and exports the appropriate driver hints before `exec river`:
- NVIDIA: `GBM_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME`, `__EGL_VENDOR_LIBRARY_FILENAMES`, `WLR_NO_HARDWARE_CURSORS`, `ENABLE_IMPLICIT_SYNC`
- AMD: `LIBVA_DRIVER_NAME=radeonsi`
- Both: `XDG_CURRENT_DESKTOP=river`, `MOZ_ENABLE_WAYLAND=1`, `SDL_VIDEODRIVER=wayland`

### River Display Configuration (`config/river/init`)

Runs on every River startup. Uses `wlr-randr --json` combined with `jq` to find and apply the
highest refresh rate mode for each connected output. GPU-aware rules:
- **NVIDIA**: enables all connected outputs at their highest refresh rate
- **AMD**: disables `eDP-*` (internal panel — AMD laptop is HDMI-out only), enables all external outputs at their highest refresh rate

The wlr-randr refresh values are in mHz as per the Wayland protocol; the init script converts to Hz automatically and handles both unit conventions defensively.

### SDDM Theme (`etc/sddm/themes/starch/`)

A custom minimal dark theme with prominent session and user selectors. Built in QML with SVG icons for Steam and Desktop sessions. SDDM runs in Wayland mode using weston as the greeter compositor (`weston --shell=kiosk`).

---

## Architecture: Why These Choices

### SDDM as display manager

SDDM in Wayland mode handles DRM master handoff to the session compositor, starts the systemd user session (which brings up PipeWire via socket activation), and provides `XDG_RUNTIME_DIR` and D-Bus. This eliminates the need for manual audio startup or DRM synchronization in session scripts — everything is ready before `start-steam` runs.

### gamescope as DRM master

gamescope takes direct ownership of the display hardware via DRM/KMS, eliminating the need for an intermediate compositor. This provides:
- Lower latency and fewer composition layers
- Direct KMS scanout via fullscreen flag (`-f`)
- Stable, flicker-free rendering with HDR support (`--hdr-enabled`)
- Simpler architecture with fewer failure points

Resolution is intentionally **not** hardcoded — gamescope queries the connector's EDID and selects the preferred mode itself. Only `-r` (target framerate) is passed, sourced from the max refresh rate across all modes advertised by the display.

### Smart display selection

`river/init` selects the right output based on GPU type rather than a hardcoded name like `eDP-1`. This matters because:
- The NVIDIA laptop uses an internal eDP panel; its card index isn't always 1
- The AMD laptop uses HDMI out exclusively with the internal panel disabled
- Future hardware may have different connector names entirely

### Early NVIDIA module loading

Without the modules in the initramfs, the kernel loads them lazily. By the time SDDM starts, the DRM device may not be fully initialized. Early loading eliminates this race entirely.

### `NVreg_PreserveVideoMemoryAllocations=1`

Without this, NVIDIA flushes VRAM on suspend. On resume, the compositor has dangling pointers into GPU memory and typically freezes or corrupts the display. The matching systemd services (`nvidia-suspend`, `nvidia-resume`) handle save/restore of that state.

### `GBM_BACKEND=nvidia-drm`

Wayland compositors use GBM to allocate shared GPU buffers. Mesa's default GBM implementation doesn't support NVIDIA. This routes GBM through NVIDIA's own backend. Not set on AMD — Mesa handles this correctly by default.

### AMD display disable in River

The AMD laptop routes all output through HDMI with the internal panel physically unused. `wlr-randr --output eDP-1 --off` in `river/init` enforces this in software on every compositor start, regardless of what state the DRM driver initializes to.

### GameCube adapter (Dolphin)

`etc/modprobe.d/gcadapter.conf` prevents `usbhid` from claiming the GameCube USB adapter, allowing Dolphin to open it directly via libusb. Applied unconditionally on both GPU configurations.

---

## Troubleshooting

### Session log

The Steam session logs to `~/.local/share/steam-session.log`. Check this first for any launch failures.

### Refresh rate not detected

If you see `Refresh: 0Hz` in the log:

```bash
# Verify modetest works and shows your connector
modetest -D /dev/dri/card1

# Check what DRM device was detected
grep "device:" ~/.local/share/steam-session.log
```

### Flickering (NVIDIA)

1. Verify early module loading:
   ```bash
   lsmod | grep nvidia_drm
   ```
2. Check that `nvidia_drm.modeset=1` is in your kernel parameters:
   ```bash
   cat /proc/cmdline | grep nvidia_drm
   ```
3. Check the session log: `~/.local/share/steam-session.log`

### Wrong display used (AMD)

If gamescope or River is using the internal panel instead of HDMI:

```bash
# Check what connectors exist and their status
cat /sys/class/drm/card*-*/status

# Verify output names (connected ones)
grep -l "^connected$" /sys/class/drm/card*-*/status
```

If your external output isn't named `HDMI-A-*` or `DP-*`, update the preferred output pattern in `river/init`.

### Controller not working

1. Check uinput permissions:
   ```bash
   ls -la /dev/uinput          # should be crw-rw---- root input
   groups                      # your user should include 'input'
   ```
2. Reload udev rules:
   ```bash
   sudo udevadm control --reload-rules && sudo udevadm trigger
   ```
3. Verify Steam Input is enabled: **Settings → Controller**

### Steam doesn't start / crashes

- **NVIDIA:** verify `lib32-nvidia-utils` is installed (32-bit libs required for Proton)
- **AMD:** verify `vulkan-radeon` and `lib32-vulkan-radeon` are installed
- Run Steam manually to see error output:
  ```bash
  # NVIDIA
  GBM_BACKEND=nvidia-drm __GLX_VENDOR_LIBRARY_NAME=nvidia steam -tenfoot
  # AMD
  steam -tenfoot
  ```

### Audio not working

- Verify `pipewire`, `pipewire-pulse`, and `wireplumber` are installed
- SDDM starts the systemd user session which activates PipeWire via socket activation
- Check if PipeWire is running: `pgrep -u $USER pipewire`
- Check systemd user session: `systemctl --user status pipewire wireplumber`

### Session not appearing in SDDM

```bash
ls /usr/share/wayland-sessions/   # should contain steam.desktop and desktop.desktop
systemctl status sddm             # verify SDDM is running
journalctl -u sddm -b             # SDDM logs
```

### SDDM theme not showing

```bash
ls /usr/share/sddm/themes/starch/   # theme files should be present
cat /etc/sddm.conf.d/10-wayland.conf  # should reference Theme=starch
```

---

## Performance Overlay (MangoHud)

To monitor frame times, GPU load, and verify the correct driver is in use:

```bash
# Per-game in Steam launch options:
MANGOHUD=1 %command%

# Or globally — add to start-steam before the exec line:
export MANGOHUD=1
export MANGOHUD_CONFIG=fps,frametime,gpu_name,gpu_load,vram,cpu_load,ram
```

---

## Attribution

This project includes SteamOS compatibility helper scripts from
[shahnawazshahin/steam-using-gamescope-guide](https://github.com/shahnawazshahin/steam-using-gamescope-guide),
cloned during installation to provide stubs for system update and BIOS update checks.
These stubs are required for Steam's SteamOS compatibility features to function correctly.
