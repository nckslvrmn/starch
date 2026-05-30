# starch

SteamOS-style console sessions plus a River desktop on Arch.

Pick Steam, Plex, or Desktop from SDDM. The console sessions hand the display straight to gamescope (DRM master, HDR, VRR). Desktop is River.

```
SDDM (Wayland, starch theme)
├── Steam    →  gamescope → steam -gamepadui
├── Plex     →  gamescope → Plex HTPC
└── Desktop  →  river
```

## Hardware

Three profiles, auto-detected from `lspci`:

| Profile   | Setup                                          | Notes                                |
|-----------|------------------------------------------------|--------------------------------------|
| `nvidia`  | NVIDIA dGPU drives everything                  | BIOS in Discrete-only when available |
| `optimus` | Intel iGPU scans out, NVIDIA renders via PRIME | BIOS in Hybrid                       |
| `amd`     | amdgpu drives everything                       | dGPU or APU                          |

Override detection with `sudo HW_PROFILE=amd bash install.sh`.

## Install

You need Arch with `linux-headers`, `paru`, and for the NVIDIA profiles a working `nvidia-open` driver with `nvidia_drm.modeset=1` on the kernel cmdline.

```bash
git clone <repo> starch && cd starch
sudo bash install.sh
# reboot, pick a session at SDDM
```

## Sessions

- **Steam**: gamescope with HDR and adaptive sync, Steam in Big Picture. "Switch to Desktop" drops back to SDDM. The brightness slider and battery indicator work.
- **Plex**: gamescope plus Plex HTPC. VRR matches the content cadence so 24/30fps playback doesn't judder.
- **Desktop**: River. Displays are handled live by way-displays, so plugging in HDMI just works with no reboot. `Super+Shift+E` exits.

SDDM (Wayland) handles the DRM master handoff and starts PipeWire / D-Bus / `XDG_RUNTIME_DIR` through the systemd user session, so the session scripts don't have to.

## Primary display

The console sessions auto-prefer an external when one's plugged in, internal otherwise. If you want to pin it:

```bash
starch-select-display            # TUI: auto / internal / external
starch-select-display external   # non-interactive
starch-select-display --show
```

That lives in `~/.config/starch/display.conf` and feeds the gamescope output priority. On the desktop, way-displays handles hotplug on its own via `~/.config/way-displays/cfg.yaml`.

## Audio

Native WirePlumber. Per-device volume sticks across reboots, and HDMI becomes the default sink when you plug in a display (you can also just pick it in Steam's audio settings). If you'd rather have one selectable sink per physical jack, run `starch-audio-setup`, it's opt-in.

## Design notes

- **gamescope owns the display directly.** Direct KMS scanout, no intermediate compositor, lower latency, real HDR.
- **VRR for video.** Adaptive sync presents each frame at its native rate, which kills pulldown judder on 24/30fps content.
- **GPU modules in initramfs** (via `mkinitcpio.conf.d`) so DRM devices exist before SDDM starts.
- **NVIDIA suspend safety.** `NVreg_PreserveVideoMemoryAllocations=1` plus the `nvidia-suspend`/`nvidia-resume` units so VRAM doesn't corrupt across sleep.
- **Nothing lives in package-owned paths.** Sessions go in `/usr/local/share/wayland-sessions` and SDDM only looks there, so a river package update can't clobber anything and you won't see a stray upstream River entry.

## Troubleshooting

Session logs are in `~/.local/share/{steam,plex,river}-session.log`. Run `starch-doctor` for a preflight check of the common breakages.

```bash
journalctl -u sddm -b                          # SDDM
dmesg | grep -iE 'nvidia|amdgpu|i915'          # GPU
systemctl --user status pipewire wireplumber   # audio
ls /usr/local/share/wayland-sessions/          # session entries
```

Controller not detected? Make sure your user is in the `input` group and `/dev/uinput` exists.

For per-game overlays, set `MANGOHUD=1 %command%` as a Steam launch option.

## Attribution

SteamOS compatibility helper scripts from [shahnawazshahin/steam-using-gamescope-guide](https://github.com/shahnawazshahin/steam-using-gamescope-guide).
