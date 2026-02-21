# starch

SteamOS-like console sessions and a River desktop on Arch Linux.

## Supported hardware

| Profile   | CPU / iGPU    | Discrete GPU       | Role                                               |
|-----------|---------------|--------------------|----------------------------------------------------|
| `nvidia`  | any           | NVIDIA             | NVIDIA drives scanout and rendering                |
| `optimus` | Intel         | NVIDIA             | Intel iGPU scans out; NVIDIA renders via PRIME     |
| `amd`     | AMD           | AMD (dGPU or APU)  | amdgpu drives both scanout and rendering           |

The installer picks the profile automatically from `lspci`. Override with `sudo HW_PROFILE=amd bash install.sh` (values: `nvidia`, `optimus`, `amd`).

---

## What this does

```
SDDM (Wayland, starch theme)
├── Steam    →  start-steam  →  gamescope (DRM master, HDR, VRR) → steam -gamepadui
├── Plex     →  start-plex   →  gamescope (HDR, VRR) → Plex HTPC flatpak
└── Desktop  →  start-river  →  river (wlr-randr display config on init)
```

- **Steam session** — gamescope takes direct DRM ownership and runs Steam in Big Picture mode with HDR and adaptive sync. "Switch to Desktop" in Steam's power menu kills gamescope and returns to SDDM.
- **Plex session** — gamescope runs Plex HTPC fullscreen with adaptive sync and HDR. VRR presents frames at the content's native cadence (24fps, 30fps, etc.) for judder-free playback.
- **Desktop session** — River tiling Wayland compositor with automatic display configuration via `wlr-randr`, HiDPI scaling, and media key bindings.
- **SDDM** — Wayland mode with a custom dark theme. Handles DRM master handoff and PipeWire/audio startup via systemd user session.

---

## Prerequisites

- **Arch Linux** with `base linux linux-headers`
- **`nvidia-open`** driver installed and working (`nvidia` and `optimus` profiles only)
- **`nvidia_drm.modeset=1`** in kernel parameters (`nvidia` and `optimus` profiles only)
- **BIOS graphics mode:**
  - `nvidia` profile → Discrete GPU Only (when the option exists)
  - `optimus` profile → Hybrid / Optimus
- **paru** AUR helper
- **systemd-boot** (recommended)

### Install flow

```bash
git clone https://github.com/your-username/starch.git
cd starch
sudo bash install.sh
# reboot — select Steam, Plex, or Desktop from SDDM
```

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

- **auto** (default) — external if an HDMI/DP cable is plugged in, else internal.
- **internal** — always the laptop panel (`eDP-*` / `LVDS-*` / `DSI-*`).
- **external** — first connected non-internal output; falls back to internal if nothing is plugged in.

---

## Key design decisions

**SDDM handles everything before session launch** — DRM master handoff, PipeWire/audio via systemd user session, `XDG_RUNTIME_DIR`, D-Bus. Session scripts don't need to set any of this up.

**gamescope as DRM master** — Direct KMS scanout, lower latency, HDR, no intermediate compositor.

**gamescope with adaptive sync** — VRR presents each frame at the content's native rate, eliminating pulldown judder that fixed-refresh compositors cause with 24fps/30fps video.

**Early GPU module loading** — Modules in initramfs via `mkinitcpio.conf.d` so DRM devices are ready before SDDM starts.

**`NVreg_PreserveVideoMemoryAllocations=1`** (NVIDIA profiles) — Prevents VRAM corruption on suspend/resume. Matched by `nvidia-suspend`/`nvidia-resume` systemd services.

**river.desktop overwrites the river package's file** — Prevents duplicate SDDM entries. River package updates will clobber it; re-run `install.sh`.

---

## Troubleshooting

**Session logs:**
- Steam: `~/.local/share/steam-session.log`
- Plex: `~/.local/share/plex-session.log`
- River: `~/.local/share/river-session.log`

**Kernel/driver:**
```bash
dmesg | grep -iE 'nvidia|amdgpu|i915'
cat /proc/cmdline
lsmod | grep -E 'nvidia_drm|amdgpu|i915'
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
