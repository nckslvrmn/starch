# starch

SteamOS-style console sessions and a River desktop on Arch Linux.

Pick Steam, Plex, or Desktop from SDDM. The console sessions hand the display straight to gamescope (DRM master, HDR, VRR); the desktop session is River.

```
SDDM (Wayland, starch theme)
├── Steam    →  gamescope → steam -gamepadui
├── Plex     →  gamescope → Plex HTPC
└── Desktop  →  river
```

## Hardware

Three profiles, auto-detected from `lspci`:

| Profile   | Setup                            | Notes                                      |
|-----------|----------------------------------|--------------------------------------------|
| `nvidia`  | NVIDIA dGPU drives everything    | BIOS in Discrete-only when available       |
| `optimus` | Intel iGPU scans out, NVIDIA renders via PRIME | BIOS in Hybrid                  |
| `amd`     | amdgpu drives everything         | dGPU or APU                                |

Override detection: `sudo HW_PROFILE=amd bash install.sh`.

## Install

Prereqs: Arch with `linux-headers`, `paru`, and (for NVIDIA profiles) a working `nvidia-open` driver with `nvidia_drm.modeset=1` on the kernel cmdline.

```bash
git clone <repo> starch && cd starch
sudo bash install.sh
# reboot, pick a session at SDDM
```

## Sessions

- **Steam** — gamescope with HDR + adaptive sync, Steam in Big Picture. "Switch to Desktop" in Steam's power menu drops back to SDDM.
- **Plex** — gamescope + Plex HTPC. VRR matches the content's native cadence so 24/30fps playback doesn't judder.
- **Desktop** — River, configured via `~/.config/river/init`. Display layout is applied with `wlr-randr` on startup. `Super+Shift+E` exits.

SDDM (Wayland) handles DRM master handoff and starts PipeWire / D-Bus / `XDG_RUNTIME_DIR` via the systemd user session, so the session scripts don't have to.

## Primary display

On laptops, pin scanout to a specific connector so gamescope and River always come up where you expect:

```bash
starch-select-display            # TUI: auto / internal / external
starch-select-display external   # non-interactive
starch-select-display --show
```

Preference lives in `~/.config/starch/display.conf` and is read by every `start-*` script. `auto` prefers an external if one is plugged in.

## Design notes

- **gamescope owns the display directly.** Direct KMS scanout — no intermediate compositor, lower latency, real HDR.
- **VRR for video.** Adaptive sync presents each frame at its native rate, which kills pulldown judder on 24/30fps content.
- **GPU modules in initramfs** (via `mkinitcpio.conf.d`) so DRM devices exist before SDDM starts.
- **NVIDIA suspend safety.** `NVreg_PreserveVideoMemoryAllocations=1` plus the `nvidia-suspend`/`nvidia-resume` units to avoid VRAM corruption across sleep.
- **river.desktop overwrites the upstream file** so SDDM doesn't show two River entries. A river package update will clobber it — re-run `install.sh`.

## Troubleshooting

Session logs are in `~/.local/share/{steam,plex,river}-session.log`.

```bash
journalctl -u sddm -b                              # SDDM
dmesg | grep -iE 'nvidia|amdgpu|i915'              # GPU
systemctl --user status pipewire wireplumber      # audio
ls /usr/share/wayland-sessions/                    # session entries
```

Controller not detected? Make sure your user is in the `input` group and `/dev/uinput` exists.

For per-game overlays: `MANGOHUD=1 %command%` as a Steam launch option.

## Attribution

SteamOS compatibility helper scripts from [shahnawazshahin/steam-using-gamescope-guide](https://github.com/shahnawazshahin/steam-using-gamescope-guide).
