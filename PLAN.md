# starch resilience plan

A plan to make starch break less often as Arch moves underneath it — by borrowing the *properties* that make Bazzite robust without becoming a full OS image.

## TL;DR

starch is a well-written imperative installer that mutates a live, rolling-release system. It breaks for the same reason any such layer breaks: the substrate (gamescope, NVIDIA, mesa, steam, river, wireplumber) moves continuously, and starch has no safety net, no reproducibility, and a few places where it fights the package manager. Bazzite isn't more correct — its open issues show the *same* gamescope/NVIDIA breakage we hit — it's just **atomic, version-pinned, and rollback-able**. We can adopt those properties as a config layer. The single highest-ROI work, in order: (1) a test/CI safety net, (2) snapshot + rollback around installs and updates, (3) stop owning package-managed files, (4) vendor + pin the moving parts.

## Where starch is today (honest read of the code)

Strengths worth preserving:

- **Clean shared library.** `scripts/starch-profile.sh` centralizes profile detection, DRM/card resolution, GPU env, audio-sink stabilization, and the compositor crash-retry loop. The session scripts are thin and consistent.
- **Good failure instincts.** `starch_run_compositor` backs off after 3 fast crashes instead of thrashing; `_plex_cleanup` force-kills a wedged flatpak holding DRM master; `starch_ensure_audio` waits for the sink to *stabilize* (not just exist) to dodge the WirePlumber `auto_null` race; `starch-doctor` preflights the common breakages.
- **Drift detection exists in one place.** The `/var/lib/starch/flatpak-gl.version` stamp + `starch_check_nvidia_flatpak_gl` is exactly the right pattern — it's just only applied to one failure class.
- **Profile-aware and reasonably idempotent.** Stale-file cleanup on profile switch, `--needed` package installs, `cmp`-gated initramfs rebuilds.

## Why it breaks — root-cause taxonomy

1. **No atomicity or rollback.** `install.sh` mutates the live system in place. A half-failed run (e.g. `mkinitcpio -P` aborts, or a `paru` transaction dies mid-way) leaves an intermediate state with no defined recovery. This is the biggest single gap versus Bazzite, whose headline feature is `rpm-ostree rollback` / GRUB previous-deployment boot.

2. **Rolling-release drift with nothing pinned.** Nothing records or constrains the versions of the fast-moving packages this depends on. The code already carries scar tissue for this: the comment in `starch_run_compositor` about "gamescope 3.16 has an intermittent assertion," the NVIDIA env-var soup in `starch_apply_gpu_env`, the audio stabilization polling. A routine `pacman -Syu` can break a session entirely independent of any starch change.

3. **We fight the package manager in a few spots.** `sessions/river.desktop` is installed *over* the upstream `/usr/share/wayland-sessions/river.desktop`, and the README admits "a river package update will clobber it — re-run install.sh." `steamos-session-select` is written into `/usr/bin` (package-owned territory) rather than `/usr/local/bin`. Any path we share with a package is a future breakage.

4. **No automated testing.** Despite `set -euo pipefail`, there is no shellcheck, no unit tests for the eminently testable pure functions in `profile.sh` (connector classification, mHz→Hz, the `modetest`/`jq` parsers), and no smoke test of `install.sh`. "Often breaks with changes" is the direct symptom of having no regression gate.

5. **Install-time network + unpinned third party.** `install.sh` clones `shahnawazshahin/steam-using-gamescope-guide` from GitHub into `/tmp` at install time. That's a network dependency, a reproducibility hole, and an unpinned supply-chain surface for scripts we drop into `/usr/local/bin`.

6. **Hardcoded gamescope flags.** `--backend drm --steam --adaptive-sync --hdr-enabled --mangoapp --prefer-output ...` are all version-sensitive gamescope flags passed unconditionally. A gamescope release that renames/removes one takes the session down with no fallback.

7. **No version stamp, no manifest, no uninstall.** There's no record of which starch revision produced the current on-disk state, no manifest of deployed files, and no clean removal path. Stale-file cleanup is hand-maintained inline (`for stale in ...; rm -f`), which is how files get orphaned over time.

8. **Monolithic installer.** `install.sh` is 637 lines mixing package install, `/etc` deployment, systemd units (some heredoc'd inline), flatpak, third-party fetch, ALSA mixer poking, and user-config. Hard to test, hard to re-run a single concern, easy to introduce ordering bugs.

## What Bazzite actually does better (and what's portable)

| Bazzite property | Why it helps | Portable to starch as a config layer? |
|---|---|---|
| Image-based (bootc/rpm-ostree), built + tested as one unit | The whole userland is validated together; you never get a novel package combo | Not directly — but we can pin/record a known-good package set |
| Atomic update + `rpm-ostree rollback` / GRUB previous deployment | One bad update is one command/reboot to undo | **Yes** — btrfs + snapper snapshots, GRUB rollback entries, a transactional update wrapper |
| Deliberate, batched updates (not continuous) | Smaller, reviewable change surface | **Yes** — a `starch-update` flow that snapshots, updates, health-checks, offers rollback |
| Everything vendored into the image | No install-time network, reproducible | **Yes** — vendor the helper scripts, drop the runtime `git clone` |
| Layering is explicit and warned-about | Users understand the blast radius | **Yes** — separate system vs user layers, document the contract |

The takeaway: Bazzite's reliability is **operational**, not magic. Its own tracker has the exact NVIDIA-on-external-display and gamescope-broke-after-update issues we hit. The difference is that when it breaks, you roll back in one step. starch needs that escape hatch far more than it needs cleverer workarounds.

## Design principles to adopt

1. **Never own a file the package manager owns.** Deploy only into `/usr/local`, `/etc/*.d` drop-ins, and dedicated `starch-*` filenames. If an upstream file must be influenced, do it with a drop-in or a pacman hook that re-asserts — never by overwriting.
2. **Converge, don't mutate.** Every step idempotent and individually runnable; re-running is always safe and a no-op when nothing changed.
3. **Make the update surface explicit and reversible.** Snapshot before change; pin or record the moving parts; always have a one-step rollback.
4. **Probe capabilities, don't assume versions.** Feature-detect gamescope flags and tool presence instead of hardcoding.
5. **Vendor external dependencies.** No install-time clones.
6. **Test the pure logic, smoke-test the integration.** A bad edit should fail CI, not a user's boot.

## Priority focus: live audio & display switching (the "amateur feel")

This is the polish that matters most day-to-day, and it's a self-contained win that doesn't depend on the resilience work above. The current experience — "launch river, run select-display, reboot, load Steam, then the whole thing in reverse" — and volume that resets on every boot are both symptoms of **one** architectural choice: starch resolves the display and audio target *once, at session-launch time*, and the audio layer is a hand-rolled virtual-sink system that actively fights the tools that already solve this. Windows feels seamless because it's *reactive* (hotplug re-routes instantly) and it *remembers per-device state*. We can get the same by leaning on WirePlumber and wlroots instead of around them.

### Root cause, mapped to the code

- **Display is launch-time, not reactive.** `profile.sh:_starch_resolve_primary_output` collapses the `auto/internal/external` preference into a single `STARCH_PRIMARY_OUTPUT` at session start. `start-steam`/`start-plex` then pass it once as `--prefer-output "$STARCH_PRIMARY_OUTPUT"`, and `config/river/init:_configure_displays` runs `wlr-randr` exactly once. Plugging in HDMI afterward does nothing — hence the relaunch/reboot dance.
- **gamescope is being underused.** `gamescope -O/--prefer-output` accepts *a list of connectors in order of preference* (comma-separated), but starch passes a single value. A priority list (`HDMI-A-1,DP-1,eDP-1`) makes gamescope auto-pick the external when present and fall back to internal — no config edit, no reboot.
- **Volume amnesia is self-inflicted.** WirePlumber persists per-device volume/mute natively via `device.restore-routes` and restores the last default device on its own. But `starch-audio-setup` does `rm -f .../wireplumber/*restore-stream*` and forces every virtual sink to `100%` on each run, and the virtual-sink loopback graph means the volume you set never lands on the node WirePlumber would remember. We are deleting the exact state that would make volume stick.
- **No "follow HDMI" for audio.** The virtual-sink model requires the user to manually pick a sink in Steam/pavucontrol. There's no logic that makes HDMI audio the default when a display is connected, and the watcher (`starch-audio-port-watcher`) only flips a card profile *after* the user manually selects a virtual sink.

### Target behavior (Windows-like)

- Plug in HDMI → video and audio both move to it automatically, live, in whatever session is running. Unplug → both fall back to internal panel + speakers. No scripts, no reboot.
- Per-device volume is remembered. Set HDMI to 30% and internal speakers to 80% once; each device keeps its own level across reboots and reconnects.
- `auto` is the default and is a *priority order*, not a frozen one-shot choice. `internal`/`external` remain as hard overrides.

### Plan

**Display — make it reactive:**

- [ ] **Desktop (river):** replace the one-shot `_configure_displays` in `config/river/init` with a hotplug daemon — `kanshi` or `way-displays`. way-displays is the better fit for "it just works": auto-arrange, auto-scale by DPI, VRR, and lid-open/close handling, all on hotplug. Define declarative profiles (docked: external primary, internal off-or-secondary; undocked: internal only) and let the daemon apply them on connect/disconnect. Ship it as a systemd user service.
- [ ] **Console (gamescope steam/plex):** add `_starch_output_priority_list` to `profile.sh` (built from the existing connector classification) and pass it to gamescope as a comma-separated `--prefer-output HDMI-A-1,DP-1,eDP-1`. This removes the reboot-to-flip for the common case: the external is preferred automatically at launch, internal is the fallback. Document the caveat that gamescope's *live* hotplug re-pick (while a game is running) is partial upstream; the realistic win is "next session already prefers HDMI with zero manual steps," plus a small `drm`-udev watcher that can re-assert if needed.
- [ ] Keep `starch-select-display` only as an override for the rare "pin to internal even when docked" case; make `auto` the documented default and the priority-list source of truth.

**Audio — stop fighting WirePlumber:**

- [ ] Demote the virtual-sink architecture (`starch-audio-setup` + `starch-audio-port-watcher`) to an opt-in "advanced" mode, and make the default path native WirePlumber. Ship a `~/.config/wireplumber/wireplumber.conf.d/50-starch.conf` that enables `device.restore-routes`, `device.restore-profile`, and default-target restore (per the WirePlumber 0.5 settings doc) so per-device volume and the last-used default both persist.
- [ ] Delete the two lines causing the amnesia: the `rm -f ...restore-stream*` wipe and the forced `set-sink-volume ... 100%` in `starch-audio-setup`. Stop resetting state we want to keep.
- [ ] **Follow-HDMI:** let WirePlumber's default-nodes pick the highest-priority *available* sink (HDMI only becomes available when the display is connected). Tune HDMI sink priority above the internal codec and avoid pinning a *configured* default, so a freshly-connected HDMI takes over automatically and internal returns on unplug. If priority tuning proves too blunt, fall back to a tiny event-driven helper that does `wpctl set-default <hdmi>` on appear and restores the remembered previous default on disappear.
- [ ] Keep the legitimate Realtek quirk fix (Line Out at 0% / Auto-Mute off) but apply it **once** as a route default via WirePlumber/alsactl rather than re-clobbering mixer levels on every `starch-audio-setup` run — re-clobbering competes with the persistence we're trying to enable.

**Unify the event (optional but most Windows-like):**

- [ ] A single `starch-display-watcher` on `drm` udev hotplug that reconfigures *both* video (signal kanshi/way-displays, re-assert gamescope preference) and audio (re-evaluate default sink) on one event, and persists per-output + per-device state under `~/.config/starch/`. This is the most debuggable "I plugged in HDMI and everything followed" path and gives one place to remember arrangement + volume.

### Why this also reduces breakage

Every item here *removes* starch-specific machinery (one-shot resolution, the virtual-sink graph, the restore-state wipe) in favor of upstream WirePlumber/wlroots behavior that is maintained and tested by those projects. Less bespoke code in the hot path means fewer things for an Arch update to break — so this polish work doubles as resilience work.

## Brightness in the Steam session

You want the Steam Quick-Access brightness slider (and the brightness keys) to actually move the panel. Today it does nothing in gamescope. This is fixable, with caveats that depend on the hardware profile.

Self-diagnosis shortcut: **if the slider doesn't appear at all** (this laptop's symptom), gamescope found no writable backlight → it's permissions or env. **If the slider appears but moving it does nothing**, gamescope is writing the wrong backlight device. We're in the first case here, which is the simpler fix.

How it works: gamescope owns brightness in the console session and writes the internal panel level directly to `/sys/class/backlight/<device>/brightness`. Steam only shows the slider when gamescope is integrated (the `--steam` flag, which we already pass) *and* gamescope finds a controllable backlight it can write to. Three things break this on generic laptops:

1. **Permissions.** The session runs as your user, but `/sys/class/backlight/*/brightness` is root-owned by default. gamescope writes sysfs directly (not via logind), so it silently fails. Fix: a udev rule granting the `video`/`seat` group write on `brightness` and `bl_power`. starch already adds the user to `video` and ships a udev file (`etc/udev/rules.d/70-gaming.conf`) — add the backlight rule there.
2. **Wrong backlight device.** Machines expose several (`intel_backlight`, `amdgpu_bl0` *and* `amdgpu_bl1`, `acpi_video0`, occasionally `nvidia_0`). If gamescope targets the inactive one, the slider moves but nothing changes — this is a confirmed, common failure (gamescope issues #2172/#2420). The right device is profile-dependent: **optimus → `intel_backlight`**, **amd → `amdgpu_bl0` (verify; some panels need `bl1`)**, **pure-NVIDIA laptop → usually none/`nvidia_0`**. starch should detect the *active* device (highest `max_brightness`, or the one whose writes take effect) per profile and, where gamescope picks wrong, bridge it.
3. **Missing enablement env.** SteamOS sets `STEAM_ENABLE_DYNAMIC_BACKLIGHT=1` for the session; add it to `start-steam`'s exports alongside the existing `STEAM_GAMESCOPE_SESSION=1`.

Plan:

- [ ] Add a backlight udev rule (group `video`/`seat`, `g+w` on `brightness` + `bl_power`) to `etc/udev/rules.d/70-gaming.conf`. This alone fixes the common single-backlight laptop.
- [ ] Add backlight detection to `profile.sh` (which `/sys/class/backlight` device is live for the current profile) and surface it in `starch-doctor` so a wrong/missing backlight is diagnosed, not mysterious.
- [ ] Export `STEAM_ENABLE_DYNAMIC_BACKLIGHT=1` in `start-steam`.
- [ ] **Out of scope (confirmed):** external monitors have no backlight class — their brightness is DDC/CI over I2C, which gamescope/Steam don't drive natively. We're not chasing external-display brightness; the slider targets the internal panel only. Document this so it's a known limitation, not a bug.
- [ ] Caveat to document: brightness control breaking *after suspend* is a known gamescope/SteamOS bug (#1987); the resume hook in the polish backlog below should re-assert the backlight on wake.

## "Switch to Desktop" / Exit to Desktop — the actual bug

This has never worked because of an argument mismatch in our own `scripts/steamos-session-select`, not a deep session-manager problem. **Steam's "Switch to Desktop" button invokes `steamos-session-select plasma`** (the arg is `plasma`; persistent variants are `plasma-wayland-persistent` / `plasma-x11-persistent`). Our script's `case` only accepts the literal words `desktop|gamescope` and sends everything else — including `plasma` — to the `*) ... exit 1` branch, so it prints "unknown target 'plasma'" and exits **without ever calling `steam -shutdown`**. The graceful shutdown logic we wrote is correct; it's just gated behind a `case` Steam never matches.

Context that confirms nothing *else* is broken:

- `-steamos3` is what makes the button invoke the script at all — we already pass `steam -gamepadui -steamos3`, so the call fires.
- The os-release spoof (`ID=steamos`) is correct, so the button is present.
- `starch-steam-launch` runs bwrap *without* `--unshare-pid`, so the PID namespace is shared and even the `pkill gamescope` fallback reaches the real process.
- Our model needs no desktop hand-off: SDDM launches `start-steam` directly, so once Steam shuts down, `gamescope --steam` exits cleanly, `starch_run_compositor` returns 0, `start-steam` ends, and SDDM redisplays the greeter — exactly the "fall back to SDDM and re-login to river" behavior wanted.

The original shahnawazshahin reference script is literally `#!/bin/bash` + `steam -shutdown` with no argument parsing — it works *because* it ignores the argument. Our stricter validation is the regression.

Plan:

- [ ] Rewrite the `case` so any desktop-ish target (`plasma`, `plasma-*`, `desktop`, empty) runs the existing `steam -shutdown` → wait → `pkill -TERM` → `pkill -KILL` + restart-SDDM escalation, and reserve a no-op (or relaunch) only for `gamescope`. Keep the escalation logic as-is.
- [ ] Cheap confirmation before/after: have the script log its `$@` and exit path to `~/.local/share/steam-session.log` (or a dedicated file) so we can *see* Steam call it with `plasma` and watch it take the shutdown path. This turns "it mysteriously doesn't work" into a logged event.
- [ ] Add a `starch-doctor` check that `steamos-session-select` exists, is executable, and accepts a `plasma` argument without erroring (a tiny `--dry-run` mode that validates the arg and exits 0 without shutting down Steam).
- [ ] When we move binaries out of `/usr/bin` (Phase 3), keep `steamos-session-select` discoverable on `PATH` inside the Steam bwrap namespace — Steam invokes it by bare name, so wherever it lives must be on `PATH`.

## Feature & polish backlog (the "console-grade" feel)

Grouped by theme. None of these are required for correctness — they're the difference between "a clever script collection" and "a product." Pick off whatever's highest-value.

**On-screen feedback**

- [ ] Volume/brightness/mute OSD in the desktop session via **SwayOSD** (GTK, has a libinput backend for the media keys and a brightness indicator) — today `config/river/init` changes volume/brightness on keypress with zero visual feedback, which is the single most "amateur" desktop tell. `wob` is a lighter alternative. The Steam session already has its own OSD.

**Battery, network, Bluetooth in gamemode**

- [ ] Ensure `upower` is installed and running — Steam's gamepadui reads it to show the **battery indicator**; without it there's just no battery on a laptop. Verify the Wi-Fi and Bluetooth panels inside Steam Settings work (they need NetworkManager + bluez, both present, plus the SteamOS session marker, which `starch-steam-launch` already spoofs).
- [ ] **Bluetooth audio auto-switch:** enable WirePlumber `bluetooth.autoswitch-to-headset-profile` and have a connected BT headset become the default sink on connect (ties directly into the audio-follow work above). Make controller + headset pairing from within Steam "just work."

**Suspend / resume robustness**

- [ ] A resume hook (logind sleep target or `nvidia-resume`-adjacent unit) that re-asserts backlight, re-evaluates the default audio sink, and re-applies display config on wake — the same reactive watcher that handles hotplug should handle resume. This is where most "it worked until I closed the lid" reports come from.
- [ ] Lid-switch handling: on a laptop docked to HDMI, closing the lid should keep output on the external, not blank everything. way-displays/kanshi profiles cover this for the desktop; the console session needs the equivalent.

**Boot & session UX**

- [ ] **Keep SDDM** as the login/boot front end (explicit decision — no autologin/boot-straight-to-Steam). Polish within that: make SDDM remember and pre-select the last-used session so entering Steam is one button, not a menu hunt. `RememberLastUser=true` is already set; add last-session memory.
- [ ] A **Plymouth** boot splash matching the SDDM `starch` theme — independent of SDDM, it just removes the text-mode boot scroll before the greeter and makes a console build feel finished.
- [ ] First-run setup: a small TUI on first boot to set primary-display preference, audio default, and timezone, instead of the current "run these scripts by hand" onboarding.

**Display & color**

- [ ] Night-light / color-temperature on the desktop session (`wlsunset` or `gammastep`).
- [ ] Verify HDR tone-mapping correctness for the Steam and Plex sessions across the profiles (the flags are set; the *results* aren't validated anywhere).

**Recovery & support**

- [ ] `starch-doctor --bundle` (already noted in Phase 5): one zip with session logs, GPU `dmesg`, versions, and detected backlight/audio/display state for fast triage.

## Phased plan

### Phase 0 — Safety net (do first; highest ROI, lowest risk)

- [ ] Add `shellcheck` across all scripts + `install.sh`. Wire a `Makefile` (`make lint`, `make test`) and a GitHub Actions workflow that runs it on every push/PR. This alone catches a large share of "broke with a change."
- [ ] Extract the pure functions from `profile.sh` and cover them with `bats` tests — these are the bits most exposed to upstream format drift:
  - `_starch_is_internal_connector` (eDP/LVDS/DSI classification)
  - the mHz→Hz conversion in `config/river/init`
  - the `modetest` refresh-parsing awk in `starch_probe_refresh`
  - the `jq` card/port parser in `starch-audio-setup` (feed it captured `pactl -f json` fixtures)
- [ ] Add a `STARCH_DRY_RUN` mode to `install.sh` and a container smoke test (run it in an `archlinux` container with a fake rootfs / stubbed `pacman`/`flatpak`) so the orchestration is exercised in CI without hardware.

### Phase 1 — Rollback & update safety (the core Bazzite gap)

- [ ] Adopt btrfs + `snapper` (or `snap-pac`) and take a **pre-install snapshot** at the top of `install.sh`. Document the GRUB "boot previous snapshot" recovery path in the README.
- [ ] Add a pacman hook (`/etc/pacman.d/hooks/`) that snapshots before any `gamescope`/`nvidia*`/`mesa`/`steam`/`river`/`wireplumber` transaction, so even a manual `pacman -Syu` is reversible.
- [ ] Ship `starch-update`: snapshot → `paru -Syu` → `starch-doctor` → if checks fail, print the exact rollback command (and optionally auto-rollback). This is the Arch-side analogue of Bazzite's transactional update.

### Phase 2 — Reproducibility & pinning

- [ ] Record a known-good version manifest (`starch-lock.txt`) capturing the exact versions of the critical fast-movers (gamescope, nvidia-open/utils, mesa, steam, river/wlroots, wireplumber, pipewire). `starch-doctor` flags drift from the locked set.
- [ ] Provide an opt-in `IgnorePkg` hold for those packages plus a deliberate `starch-bump <pkg>` flow that updates the lock, snapshots, and re-runs doctor. Lets users pull updates on purpose instead of by accident.
- [ ] **Vendor** the five `shahnawazshahin` helper scripts into `scripts/vendor/` (attribution already in README) and delete the install-time `git clone`. Pin to a known commit; document how to refresh.

### Phase 3 — Stop fighting the package manager

- [ ] Rename `sessions/river.desktop` → `starch-river.desktop` (and `Name=Desktop` stays) so we stop overwriting the upstream river session entry. Removes the "re-run install.sh after a river update" footgun entirely.
- [ ] Move `steamos-session-select` out of `/usr/bin` into `/usr/local/bin` (and verify nothing relies on the `/usr/bin` path; symlink only if a package truly requires it).
- [ ] Replace the README's "re-run install.sh" guidance with pacman hooks that re-assert any starch-owned drop-in an update might revert.
- [ ] Introduce a deployed-file **manifest** and an `install.sh --uninstall`. Replace the hand-maintained inline `for stale in ...` cleanups with manifest-diff cleanup so files never orphan.

### Phase 4 — Structure & maintainability

- [ ] Split `install.sh` into a thin orchestrator + idempotent step modules under `lib/install.d/` (e.g. `10-packages`, `20-etc`, `30-services`, `40-flatpak`, `50-sessions`, `60-user-config`), each runnable standalone (`install.sh --only packages`). Makes partial re-runs and CI targeting trivial.
- [ ] Move the inline heredoc systemd units (`starch-audio-setup.service`, etc.) into real files under `etc/systemd/` so they're lintable and diffable.
- [ ] Add a `/etc/starch/version` stamp written at install, and `starch-doctor --repair` to re-converge a drifted box without a full reinstall (extends the existing flatpak-GL stamp pattern to everything).

### Phase 5 — Capability-probing & resilience polish

- [ ] Feature-detect gamescope flags before use (parse `gamescope --help`), dropping unsupported flags with a warning rather than failing to launch. Same idea for any tool whose CLI surface drifts.
- [ ] `starch-doctor --bundle`: zip session logs + `dmesg` GPU lines + versions into a single file for fast triage.

## Suggested sequencing

Two independent tracks. The **live audio & display switching** work above is the day-to-day polish you care most about and is self-contained — it can land first and on its own, and it happens to delete bespoke code so it doubles as resilience. In parallel, **Phase 0 → Phase 1** answer "it often breaks with changes": CI stops *our* edits from breaking it, and snapshots/rollback make *upstream's* changes survivable. Do the switching work and Phase 0 first (a few of the switching changes are exactly the pure functions Phase 0 would test). Phases 2–3 reduce the rate of breakage at the source; Phases 4–5 are quality-of-life and land incrementally.

## Explicitly out of scope (for now)

Going fully image-based (archiso/mkosi/an immutable Arch image) would get true Bazzite parity but abandons the "config layer on base Arch" premise and is a much larger lift. Worth revisiting only if the snapshot+pin approach proves insufficient. Noting it here so the option isn't lost.
