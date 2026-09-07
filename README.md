# starch

A SteamOS-style console session plus a River desktop on Arch.

Pick Steam or Desktop from SDDM. The Steam session hands the display straight to gamescope (DRM master, HDR, VRR). Desktop is River.

```
SDDM (Wayland, starch theme)
├── Steam    →  gamescope → steam -gamepadui
└── Desktop  →  river → canoe
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
- **Desktop**: River 0.4 with [canoe](https://github.com/roblillack/canoe) as the window manager. River 0.4 is a compositor only — window management is a separate client speaking `river-window-management-v1`, so layout, focus, decorations and every keybinding come from canoe, configured in `~/.config/canoe/canoe.toml` (`pkill -HUP canoe` reloads it live). Windows float and are snapped on demand, and drag-to-move/resize works. `~/.config/river/init` is a startup script only: way-displays, mako, swayidle, canoe. Displays are handled live by way-displays, so plugging in HDMI just works with no reboot. Terminal is ghostty via `starch-terminal` (foot is the fallback). The session locks after 10 idle minutes and before suspend (swaylock).

Key bindings (Desktop):

| Chord | Action |
|---|---|
| `Super+Space` | launcher (fuzzel) |
| `Super+Return` | terminal |
| `Super+Q` / `Super+W` | close window |
| `Super+Tab` / `Super+Shift+Tab` | window switcher |
| `` Super+` `` | cycle windows of the same app |
| `Super+←/→` | snap left / right half |
| `Super+↑` / `Super+↓` | maximize / unmaximize, else minimize |
| `Super+drag` | move window (`Super+right-drag` resizes) |
| `Super+Alt+←/→` | send window to another output |
| `Super+L` | lock |
| `Super+Shift+S` | region screenshot → clipboard |
| `Super+A` | cycle audio output (OSD) |
| `Super+B` | battery OSD |
| `Super+Shift+E` | exit to SDDM |

canoe's built-in actions aren't remappable (only spawn-a-command hotkeys are), so window cycling is `Super+Tab` and closing is natively `Super+W`. `Super+Q` still works via `wlrctl toplevel close state:active`, which goes through the compositor's foreign-toplevel protocol instead.

Switching the other way: launch **"Switch to Steam"** from fuzzel (or run `starch-session-request steam`) to leave the desktop and go straight into the gamescope session. `starch-session-request desktop` works from a TTY/SSH too.

Console mode: `starch-select-boot steam` makes every boot go straight into the Steam session (no keyboard needed); `starch-select-boot greeter` restores the login screen. The power button taps to suspend, holds to power off.

SDDM (Wayland) handles the DRM master handoff and starts PipeWire / D-Bus / `XDG_RUNTIME_DIR` through the systemd user session, so the session scripts don't have to.

## Performance

- **Session-scoped perf mode.** `start-steam` flips `starch-perf-mode on` (and `off` on exit), which switches the ACPI platform profile to performance and puts the old one back afterwards. A sched-ext scheduler can optionally run for the session (`STARCH_SCX_SCHED` in `/etc/starch/profile.conf`), off by default after scx_lavd measured ~30% FPS loss in CPU-bound UE5 here.
- **Power profiles.** `starch-power-watch` drives governor, EPP, turbo, RAPL limits and PCIe ASPM off the FN+Q platform profile, since the EC only moves its fan curve and the dGPU budget and nothing else listens. Presets are overridable in `/etc/starch/power.conf` (see `power.conf.example`).
- **gamescope tuning knobs** live in `/etc/starch/profile.conf`: SDR→HDR inverse tone mapping, SDR nits, FSR/NIS upscaling + sharpness, and a free-form extra-args escape hatch. All off by default.
- **zram + oomd.** Compressed swap (`zram-generator`, half of RAM, zstd) plus `systemd-oomd`, so a leaking game or Proton shader compile gets killed instead of hard-freezing the box.
- **Realtime gamescope.** `--rt` and `nice -20` need `CAP_SYS_NICE`; install.sh grants it and a pacman hook reapplies it after every gamescope upgrade.
- **MangoHud** ships with a default config (`Shift_R+F12` toggles the HUD, `Shift_L+F1` cycles FPS caps). Per-game on the desktop: `MANGOHUD=1 %command%`.
- **Telemetry capture.** `starch-gameload %command%` in a game's Steam launch options samples GPU power/util/clocks/temps, CPU clock and live PL1 for the game's lifetime, then writes a CSV and a verdict to `~/.local/share/starch/`. It reads `clocks_throttle_reasons`, so it distinguishes "GPU-bound at its power limit" (nothing to fix) from thermal throttling or a CPU preset that never reached performance. Also runs standalone (`starch-gameload`, Ctrl-C to stop) when there's a terminal to hand.

## Updates

`starch-update` runs the full upgrade (`paru -Syu`) and tells you loudly if the kernel or NVIDIA driver changed (reboot before gaming); `starch-update --check` lists what's pending. A pacman hook prints the same warning on any update path.

Optional: set `STARCH_STEAM_UPDATES=1` in `/etc/starch/profile.conf` and Steam's gamepad UI can check for and apply OS updates itself (Settings → System). A root-side timer feeds the "update available" state and a path unit runs the actual `pacman -Syu` — Steam's container can't touch pacman directly. Prototype: the in-Steam progress display may need iteration.

## Network

NetworkManager owns IP configuration on every interface, iwd is the WiFi backend (`iwctl` still works for scanning and diagnostics), systemd-resolved owns DNS.

NM manages everything rather than sitting passive because Steam's gamepadui network panel reads NM over D-Bus — an interface NM doesn't manage is invisible there, so a docked ethernet link would show as "no network" while routing perfectly well.

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
- Once you pick a sink manually (in Steam's audio settings or `wpctl`), that preference outranks the automation until you clear it or pick again.

Super+A cycles the default sink and moves playing streams onto it; Super+Shift+A drops the manual pick so HDMI-follow takes over again. Speakers and headphones are two ports on one sink, switched by jack detection, so they don't appear as separate entries.

### Internal speakers (TAS2781 smart amp)

On machines whose speakers run through a TAS2781 amp (Lenovo Legion and friends —
`Speaker Profile Id` shows up in `amixer controls`), the amp runtime-suspends 3s
after the speakers go idle and only reloads its DSP program from the driver's
playback hook. The next stream races that reload, and when it loses, the sink,
the active port, the Speaker/Headphone switches and every volume read correct,
the codec pin is unmuted, and the speakers are still silent. Turning the volume
up does nothing, because nothing is reaching the amp's DSP.

The classic trigger is coming back from a long stretch on headphones, but the
suspend is driven by **idle, not by the jack** — anything that leaves the
speakers quiet for a few seconds arms the trap. In a Steam session that reads as
"the startup chime played, then nothing else ever did".

`71-starch-audio.rules` pins the amp's runtime PM (`power/control=on`) so it
never suspends and the program stays resident. That removes the race rather than
reacting to it, at the cost of the amp's idle draw. `starch-doctor` warns if the
pin isn't applied.

`starch-speaker-rearm.service` remains as the manual escape, and still watches
the headphone jack — it re-selects the RCA profile to mark the config dirty, then
plays a zero-volume stream so the reload happens before real audio. If speakers
ever go quiet anyway, `starch-speaker-rearm` fixes it on the spot without a
reboot.

To tell an amp failure apart from a routing one, run a game with
`starch-gameload %command%` as its Steam launch option: the audio log it writes
next to the telemetry records the sink, port and every stream's target, mute and
cork state. A correct graph with silent speakers is this bug.

## Design notes

- **gamescope owns the display directly.** Direct KMS scanout, no intermediate compositor, lower latency, real HDR (the internal panel is a DisplayHDR-400-class IPS — EDID reports ~500 nits max — and HDR externals work too).
- **GPU modules in initramfs** (via `mkinitcpio.conf.d`) so DRM devices exist before SDDM starts.
- **NVIDIA suspend safety.** `NVreg_PreserveVideoMemoryAllocations=1` plus the `nvidia-suspend`/`nvidia-resume` units so VRAM doesn't corrupt across sleep.
- **Nothing lives in package-owned paths.** Sessions go in `/usr/local/share/wayland-sessions` and SDDM only looks there, so a river package update can't clobber anything and you won't see a stray upstream River entry.
- **The compositor and the window manager are separate processes.** River 0.4 has no built-in window management; canoe is a normal Wayland client that drives it over `river-window-management-v1`. Practical consequence: a session with no window manager renders nothing at all, so `river/init` exits the compositor rather than leaving a black screen, and `starch-doctor` treats a missing canoe as a hard failure. The upside is that canoe can be restarted — or swapped for another window manager — without taking down the session and every app in it.
- **Session switching is filesystem-mediated.** Steam's client runs in a PID-namespaced, nosuid pressure-vessel container — it can't see host processes or escalate, so `steamos-session-select` just writes `~/.local/state/starch/session-request`; a root-side systemd path unit (`starch-session-handoff`) performs the teardown and a one-shot SDDM autologin into the target session. Same approach SteamOS uses.
- **Rolling-release guardrails.** A pacman hook warns loudly when the kernel or NVIDIA driver updates (reboot before gaming), and `starch-doctor` checks for module/userspace version drift.

## Troubleshooting

Session logs are in `~/.local/share/{steam,river}-session.log`. Run `starch-doctor` for a preflight check of the common breakages — including the rolling-release classics (kernel upgraded since boot, NVIDIA userspace/module drift).

A desktop session that comes up as an empty screen with no windows and no working keys means canoe isn't running — river 0.4 draws nothing on its own. Check the session log for canoe's stderr, and from a TTY confirm `pacman -Q canoe river`. Editing `~/.config/canoe/canoe.toml` and running `pkill -HUP canoe` re-reads bindings and theming without restarting anything.

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
