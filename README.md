# starch

SteamOS-like console sessions and a River desktop on Arch Linux.

**Supported hardware profiles:**

| Profile    | Example hardware                                 | GPU mode                                             |
|------------|--------------------------------------------------|------------------------------------------------------|
| `nvidia`   | Lenovo Legion Pro 7 Gen 8 (13900HX + RTX 4090M)  | NVIDIA-only, BIOS set to Discrete GPU Only           |
| `optimus`  | Dell Precision 5550 (i7-10xxH + T2000 Max-Q)     | Hybrid — Intel iGPU scans out, NVIDIA PRIME renders  |
| `amd`      | Any AMD desktop GPU / APU                        | amdgpu drives both scanout and rendering             |

The installer auto-detects which profile applies from `lspci`, or you can override with `sudo HW_PROFILE=amd bash install.sh` (values: `nvidia`, `optimus`, `amd`). The legacy name `discrete` is still accepted as a synonym for `nvidia`.

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
- **BIOS graphics mode:**
  - `discrete` profile → Discrete GPU Only
  - `optimus` profile → Hybrid / Optimus (Intel iGPU + NVIDIA dGPU visible)
- **paru** AUR helper
- **systemd-boot** (recommended)

### Install flow

```bash
# 1. Base Arch install with NVIDIA driver already working
# 2. Clone and run
git clone https://github.com/your-username/starch.git
cd starch
sudo bash install.sh
# or force the Optimus profile on a Precision 5550:
# sudo HW_PROFILE=optimus bash install.sh

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
| Other | `flatpak`, `networkmanager`, `libnewt` (whiptail) |
| Optimus-only | `mesa`, `vulkan-intel`, `lib32-vulkan-intel`, `intel-media-driver`, `libva-utils` |

---

## File map

```
starch/
├── install.sh                                — Installer (run as root)
├── scripts/
│   ├── starch-profile.sh                     — Shared helper: profile + GPU env
│   │                                           + primary-output resolution
│   │                                           + audio sink wait
│   ├── starch-select-display                 — TUI to pick primary display
│   ├── start-steam                           — gamescope + Steam session
│   ├── start-plex                            — gamescope + Plex HTPC session
│   ├── start-river                           — River WM session
│   ├── steamos-session-select                — Session switcher (kills gamescope → SDDM)
│   └── nvidia-flatpak-gl-sync                — Sync NVIDIA GL libs to flatpak
├── sessions/
│   ├── steam.desktop                         — SDDM "Steam" entry
│   ├── river.desktop                         — SDDM "Desktop" entry (overwrites river package)
│   └── plex.desktop                          — SDDM "Plex" entry
├── config/
│   ├── river/init                            — Display config + keybindings
│   ├── brave-flags.conf                      — Wayland flags for Brave
│   └── xdg-desktop-portal/portals.conf
└── etc/
    ├── sddm.conf.d/10-wayland.conf           → /etc/sddm.conf.d/
    ├── sddm/themes/starch/                   → /usr/share/sddm/themes/starch/
    ├── modprobe.d/nvidia.conf                → /etc/modprobe.d/starch-nvidia.conf (discrete)
    ├── modprobe.d/nvidia-optimus.conf        → /etc/modprobe.d/starch-nvidia.conf (optimus)
    ├── modprobe.d/gcadapter.conf             → /etc/modprobe.d/starch-gcadapter.conf
    ├── mkinitcpio.conf.d/nvidia.conf         → /etc/mkinitcpio.conf.d/starch-nvidia.conf (discrete)
    ├── mkinitcpio.conf.d/nvidia-optimus.conf → /etc/mkinitcpio.conf.d/starch-nvidia.conf (optimus)
    ├── pacman.d/hooks/nvidia-flatpak-gl.hook
    ├── gamemode.ini                          → /etc/gamemode.ini
    ├── sysctl.d/99-gaming.conf               → /etc/sysctl.d/99-starch-gaming.conf
    ├── udev/rules.d/70-gaming.conf           → /etc/udev/rules.d/70-starch-gaming.rules
    └── NetworkManager/conf.d/iwd-backend.conf
```

Profile state lives at `/etc/starch/profile.conf` (written by `install.sh`).
User display preference lives at `~/.config/starch/display.conf` (written by `starch-select-display`).

---

## Session switching

**Steam → SDDM:** Steam power menu → "Switch to Desktop" calls `steamos-session-select desktop`, which kills gamescope. The session ends and SDDM takes back the display.

**Plex → SDDM:** Close Plex. Gamescope exits when its client does, ending the session.

**Desktop → SDDM:** `Super+Shift+E` exits River.

From SDDM, pick any session.

---

## Primary display selection

On laptops you can pin scanout to a specific connector — the internal eDP panel or an external HDMI/DP — so gamescope and River always use the display you expect.

```bash
starch-select-display            # whiptail TUI: auto / internal / external
starch-select-display external   # non-interactive
starch-select-display --show     # print current preference
```

The preference is stored per-user in `~/.config/starch/display.conf` and read by every start-* script on session launch:

- **auto** (default) — external if a HDMI/DP cable is plugged in, else internal.
- **internal** — always the laptop panel (`eDP-*` / `LVDS-*` / `DSI-*`).
- **external** — first connected non-internal output; falls back to internal if nothing is plugged in.

gamescope receives `--prefer-output <connector>`; River's init places the chosen output at x=0 and tiles any others to its right.

---

## Optimus (Precision 5550) notes

The `optimus` profile differs from `discrete` in a few targeted ways:

- **Intel iGPU drives scanout.** `WLR_DRM_DEVICES="<intel>:<nvidia>"` tells wlroots to open the Intel card first, so that's what gamescope / River treat as the display device. The NVIDIA card remains in the list as a secondary render device.
- **NVIDIA is used via PRIME render offload.** `__NV_PRIME_RENDER_OFFLOAD=1`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `__VK_LAYER_NV_optimus=NVIDIA_only`, `VK_ICD_FILENAMES=.../nvidia_icd.json` are all exported for the session, so Steam/games/Plex render on the T2000 Max-Q and only their final framebuffer copies to the iGPU.
- **No `nvidia-drm fbdev=1`.** On the discrete profile nvidia takes over fbcon; on Optimus that fights with i915 and causes black screens. The Optimus modprobe file sets `fbdev=0`.
- **`NVreg_DynamicPowerManagement=0x02`.** The T2000 enters D3cold when idle, which matters for battery life on a laptop.
- **No HDR.** HDR scanout isn't supported end-to-end through the Intel display pipe, so `--hdr-enabled` is omitted from gamescope on this profile.
- **modetest uses i915.** Refresh-rate probing in `start-steam` targets the i915 module instead of nvidia-drm.

BIOS should be left at Hybrid/Optimus (not Discrete-only). The installer installs `mesa`, `vulkan-intel`, `lib32-vulkan-intel`, `intel-media-driver`, and `libva-utils` alongside the usual NVIDIA 32-bit userspace.

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
