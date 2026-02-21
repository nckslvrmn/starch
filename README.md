# starch

A SteamOS-style console session plus a River desktop on Arch.

Pick Steam or Desktop from SDDM. The Steam session hands the display straight to gamescope (DRM master, HDR, VRR). Desktop is River.

```
SDDM (Wayland, starch theme)
├── Steam    →  gamescope → steam -gamepadui
└── Desktop  →  river
```

## Hardware

One target: an Intel + NVIDIA-discrete laptop with the BIOS set to Discrete GPU Only, so the NVIDIA GPU drives both scanout and rendering. The Intel iGPU is unused. No Optimus, no AMD, this is tuned for exactly one machine.

## Install

Prerequisites:

- Arch with `linux` + `linux-headers` and a working NVIDIA driver (`nvidia-open` for Turing and newer)
- `nvidia_drm.modeset=1` on the kernel cmdline
- the `[multilib]` repo enabled in `/etc/pacman.conf` (steam and the lib32 stack live there)
- `git` and [`paru`](https://github.com/morganamilo/paru#installation) (a few packages come from the AUR)

```bash
git clone <repo> starch && cd starch
sudo bash install.sh
# reboot, pick a session at SDDM
```

The installer is a manifest: `rootfs/` mirrors `/`, `userfs/` mirrors the gaming user's home. Both are deployed verbatim on every run — the repo is the source of truth, so local edits to deployed files get overwritten; change them here instead. `docs/UNINSTALL.md` covers removal.

## Sessions

- **Steam**: gamescope with HDR and adaptive sync, Steam in Big Picture. "Switch to Desktop" lands you directly in the River desktop (one-shot SDDM autologin handoff — the greeter is back on next boot). The battery indicator works. Brightness does not show up as a slider in Steam, gamescope can't drive the NVIDIA native backlight, so use the hardware keys or `brightnessctl`.
- **Desktop**: River. Displays are handled live by way-displays, so plugging in HDMI just works with no reboot. Terminal is ghostty (foot is installed as fallback). The session locks after 10 idle minutes and before suspend (swaylock). The layout daemon is `riversnap` — a self-built binary, not packaged; on a machine without it the session falls back to stock `rivertile` (the `Super+←/→/↑` snap bindings need riversnap).

Key bindings (Desktop):

| Chord | Action |
|---|---|
| `Super+Space` | launcher (fuzzel) |
| `Super+Return` | terminal |
| `Super+Q` | close window |
| `Alt+Tab` / `Alt+Shift+Tab` | focus next / prev |
| `Super+Z` | zoom (bump to top of stack) |
| `Super+←/→/↑` | snap left / right / full (riversnap) |
| `Super+Shift+S` | region screenshot → clipboard |
| `Super+B` | battery OSD |
| `Super+Shift+E` | exit to SDDM |

Switching the other way: launch **"Switch to Steam"** from fuzzel (or run `starch-session-request steam`) to leave the desktop and go straight into the gamescope session. `starch-session-request desktop` works from a TTY/SSH too.

SDDM (Wayland) handles the DRM master handoff and starts PipeWire / D-Bus / `XDG_RUNTIME_DIR` through the systemd user session, so the session scripts don't have to.

## Performance

- **Session-scoped perf mode.** `start-steam` flips `starch-perf-mode on` (and `off` on exit): on AC it pins the performance governor, intel_pstate EPP, and ACPI platform profile, plus NVIDIA persistence; on battery it biases (balanced profile, EPP) without pinning the governor. Optional: set `STARCH_SCX_SCHED=scx_lavd` in `/etc/starch/profile.conf` (with the `scx-scheds` package) to run a sched-ext scheduler during sessions.
- **zram + oomd.** Compressed swap (`zram-generator`, half of RAM, zstd) plus `systemd-oomd`, so a leaking game or Proton shader compile gets killed instead of hard-freezing the box.
- **Realtime gamescope.** `--rt` and `nice -20` need `CAP_SYS_NICE`; install.sh grants it and a pacman hook reapplies it after every gamescope upgrade.
- **MangoHud** ships with a default config (`Shift_R+F12` toggles the HUD, `Shift_L+F1` cycles FPS caps). Per-game on the desktop: `MANGOHUD=1 %command%`.

## Network

iwd owns WiFi (association + DHCP), systemd-networkd owns wired, systemd-resolved owns DNS. NetworkManager runs only as a passive connectivity monitor because Steam queries it over D-Bus; it manages nothing.

## Primary display

The Steam session auto-prefers an external when one's plugged in, internal otherwise. If you want to pin it:

```bash
starch-select-display            # TUI: auto / internal / external
starch-select-display external   # non-interactive
starch-select-display --show
```

That lives in `~/.config/starch/display.conf` and feeds the gamescope output priority. On the desktop, way-displays handles hotplug on its own via `~/.config/way-displays/cfg.yaml`.

## Audio

Native WirePlumber. Per-device volume sticks across reboots, and HDMI becomes the default sink when you plug in a display. Two caveats, both intentional:

- Bluetooth headphones outrank freshly plugged HDMI while connected.
- Once you pick a sink manually (in Steam's audio settings or `wpctl`), that preference outranks the automation until you clear it (`wpctl settings --delete default-configured-audio-sink`) or pick again.

If you'd rather have one selectable sink per physical jack, run `starch-audio-setup`, it's opt-in.

## Design notes

- **gamescope owns the display directly.** Direct KMS scanout, no intermediate compositor, lower latency, real HDR on the Mini-LED panel.
- **GPU modules in initramfs** (via `mkinitcpio.conf.d`) so DRM devices exist before SDDM starts.
- **NVIDIA suspend safety.** `NVreg_PreserveVideoMemoryAllocations=1` plus the `nvidia-suspend`/`nvidia-resume` units so VRAM doesn't corrupt across sleep.
- **Nothing lives in package-owned paths.** Sessions go in `/usr/local/share/wayland-sessions` and SDDM only looks there, so a river package update can't clobber anything and you won't see a stray upstream River entry.
- **Session switching is filesystem-mediated.** Steam's client runs in a PID-namespaced, nosuid pressure-vessel container — it can't see host processes or escalate, so `steamos-session-select` just writes `~/.local/state/starch/session-request`; a root-side systemd path unit (`starch-session-handoff`) performs the teardown and a one-shot SDDM autologin into the target session. Same approach SteamOS uses.
- **Rolling-release guardrails.** A pacman hook warns loudly when the kernel or NVIDIA driver updates (reboot before gaming), and `starch-doctor` checks for module/userspace version drift.

## Troubleshooting

Session logs are in `~/.local/share/{steam,river}-session.log`. Run `starch-doctor` for a preflight check of the common breakages — including the rolling-release classics (kernel upgraded since boot, NVIDIA userspace/module drift).

```bash
journalctl -u sddm -b                          # SDDM
dmesg | grep -i nvidia                         # GPU
systemctl --user status pipewire wireplumber   # audio
ls /usr/local/share/wayland-sessions/          # session entries
```

Controller not detected? Make sure your user is in the `input` group and `/dev/uinput` exists.

## Attribution

SteamOS compatibility helper scripts vendored (under `rootfs/usr/local/bin/`) from [shahnawazshahin/steam-using-gamescope-guide](https://github.com/shahnawazshahin/steam-using-gamescope-guide).

## License

MIT — see `LICENSE`.
