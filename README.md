# starch

SteamOS-like console sessions and a River desktop on Arch Linux. NVIDIA only.

**Hardware:** Lenovo Legion Pro 7 Gen 8 — Intel 13900HX + RTX 4090 Mobile, discrete-only BIOS mode.

---

## What this does

```
SDDM (Wayland, starch theme)
├── Steam    →  start-steam  →  gamescope (DRM master, HDR) → steam -gamepadui
├── Plex     →  start-plex   →  gamescope (adaptive sync) → Plex HTPC flatpak
└── Desktop  →  start-river  →  river (wlr-randr display config on init)
```

- **Steam session** — gamescope takes direct DRM ownership and runs Steam in Big Picture mode. HDR enabled, refresh rate auto-detected via `modetest`. "Switch to Desktop" in Steam's power menu kills gamescope, ending the session and returning to SDDM.
- **Plex session** — gamescope runs Plex HTPC fullscreen with adaptive sync. VRR presents frames at the content's native cadence (24fps, 30fps, etc.) for judder-free video playback.
- **Desktop session** — River tiling Wayland compositor with automatic display configuration via `wlr-randr`, HiDPI scaling, and media key bindings.
- **SDDM** — Wayland mode with a custom dark theme. Handles DRM master handoff and PipeWire/audio startup via systemd user session.

---

## Prerequisites

- **Arch Linux** with `base linux linux-headers`
- **`nvidia-open`** driver installed and working
- **`nvidia_drm.modeset=1`** in kernel parameters
- **BIOS set to Discrete GPU Only** (not Hybrid/Optimus)
- **paru** AUR helper
- **systemd-boot** (recommended)

### Install flow

```bash
# 1. Base Arch install with NVIDIA driver already working
# 2. Clone and run
git clone https://github.com/your-username/starch.git
cd starch
sudo bash install.sh

# 3. Reboot — select Steam, Plex, or Desktop from SDDM
```

---

## Packages

Installed automatically by `install.sh`:

| Category | Packages |
|----------|----------|
| Gaming | `gamescope`, `steam`, `gamemode`, `lib32-gamemode`, `mangohud`, `lib32-mangohud` |
| Vulkan | `vulkan-icd-loader`, `lib32-vulkan-icd-loader`, `lib32-mesa`, `lib32-nvidia-utils` |
| Wayland | `xorg-xwayland`, `wlr-randr`, `jq`, `wl-clipboard` |
| Audio | `pipewire`, `pipewire-pulse`, `pipewire-alsa`, `lib32-pipewire`, `wireplumber` |
| Desktop | `bemenu`, `brightnessctl`, `xdg-desktop-portal-wlr`, `xdg-desktop-portal-gtk` |
| Display manager | `sddm`, `weston`, `qt6-wayland`, `qt6-svg` |
| Controllers | `xpadneo-dkms` (AUR), `dolphin-emu` |
| Other | `flatpak`, `networkmanager` |

---

## File map

```
starch/
├── install.sh                          — Installer (run as root)
├── scripts/
│   ├── start-steam                     — gamescope + Steam session
│   ├── start-plex                      — gamescope + Plex HTPC session
│   ├── start-river                     — River WM session
│   ├── steamos-session-select          — Session switcher (kills gamescope → SDDM)
│   └── nvidia-flatpak-gl-sync          — Sync NVIDIA GL libs to flatpak
├── sessions/
│   ├── steam.desktop                   — SDDM "Steam" entry
│   ├── river.desktop                   — SDDM "Desktop" entry (overwrites river package)
│   └── plex.desktop                    — SDDM "Plex" entry
├── config/
│   ├── river/init                      — Display config + keybindings
│   ├── brave-flags.conf                — Wayland flags for Brave
│   └── xdg-desktop-portal/portals.conf
└── etc/
    ├── sddm.conf.d/10-wayland.conf     → /etc/sddm.conf.d/
    ├── sddm/themes/starch/             → /usr/share/sddm/themes/starch/
    ├── modprobe.d/nvidia.conf          → /etc/modprobe.d/starch-nvidia.conf
    ├── modprobe.d/gcadapter.conf       → /etc/modprobe.d/starch-gcadapter.conf
    ├── mkinitcpio.conf.d/nvidia.conf   → /etc/mkinitcpio.conf.d/starch-nvidia.conf
    ├── pacman.d/hooks/nvidia-flatpak-gl.hook
    ├── gamemode.ini                    → /etc/gamemode.ini
    ├── sysctl.d/99-gaming.conf         → /etc/sysctl.d/99-starch-gaming.conf
    ├── udev/rules.d/70-gaming.conf     → /etc/udev/rules.d/70-starch-gaming.rules
    └── NetworkManager/conf.d/iwd-backend.conf
```

---

## Session switching

**Steam → SDDM:** Steam power menu → "Switch to Desktop" calls `steamos-session-select desktop`, which kills gamescope. The session ends and SDDM takes back the display.

**Plex → SDDM:** Close Plex. Gamescope exits when its client does, ending the session.

**Desktop → SDDM:** `Super+Shift+E` exits River.

From SDDM, pick any session.

---

## Key design decisions

**SDDM handles everything before session launch** — DRM master handoff, PipeWire/audio via systemd user session, `XDG_RUNTIME_DIR`, D-Bus. Session scripts don't need to set any of this up.

**gamescope as DRM master** — Direct KMS scanout, lower latency, HDR, no intermediate compositor. Resolution auto-detected from EDID; only refresh rate (`-r`) is passed.

**gamescope with adaptive sync for Plex** — VRR presents each frame at the content's native rate, eliminating pulldown judder that fixed-refresh compositors cause with 24fps/30fps video.

**Early NVIDIA module loading** — Modules in initramfs via `mkinitcpio.conf.d` so DRM devices are ready before SDDM starts.

**`NVreg_PreserveVideoMemoryAllocations=1`** — Prevents VRAM corruption on suspend/resume. Matched by `nvidia-suspend`/`nvidia-resume` systemd services.

**river.desktop overwrites the river package's file** — Prevents duplicate SDDM entries. River package updates will clobber it; re-run `install.sh`.

---

## Troubleshooting

**Session logs:**
- Steam: `~/.local/share/steam-session.log`
- Plex: `~/.local/share/plex-session.log`

**Refresh rate shows 0Hz:**
```bash
modetest -M nvidia-drm    # verify connector modes
```

**Kernel/driver:**
```bash
dmesg | grep -i nvidia
cat /proc/cmdline          # should contain nvidia_drm.modeset=1
lsmod | grep nvidia_drm
```

**SDDM:**
```bash
journalctl -u sddm -b
ls /usr/share/wayland-sessions/    # steam.desktop, river.desktop, plex.desktop
```

**Controller:**
```bash
ls -la /dev/uinput         # crw-rw---- root input
groups                     # should include 'input'
```

**Audio:**
```bash
systemctl --user status pipewire wireplumber
```

---

## MangoHud

```bash
# Per-game Steam launch option:
MANGOHUD=1 %command%
```

---

## Attribution

SteamOS compatibility helper scripts from [shahnawazshahin/steam-using-gamescope-guide](https://github.com/shahnawazshahin/steam-using-gamescope-guide).
