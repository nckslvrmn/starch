# starch

Minimal SteamOS-like console session for Arch Linux with NVIDIA discrete GPU.

**Hardware target:** Lenovo Legion Pro 7 Gen 8 (Intel 13900HX + RTX 4090 Mobile)
**Prerequisites:** Arch base, greetd + tuigreet + seatd, nvidia-open, River session working

---

## What this does

Installs a second Wayland session alongside River that launches `gamescope → Steam`
in Big Picture mode, going direct to DRM with no parent compositor. The result is a
couch-friendly, controller-first experience on bare metal — as close to SteamOS as
you can get on a standard Arch install.

```
tuigreet
├── River          (existing desktop session)
└── Steam Gaming Session   ← this project adds this
        └── gamescope --backend drm
                └── steam -tenfoot -steamos3
```

---

## Quick start

```bash
git clone <this-repo> starch
cd starch
sudo bash install.sh
# reboot
```

---

## File overview

```
starch/
├── README.md
├── install.sh                          — package install + config deploy (run as root)
├── scripts/
│   └── steam-session.sh               — gamescope+Steam launcher
├── sessions/
│   └── steam-gaming.desktop           — Wayland session descriptor for tuigreet
└── etc/
    ├── modprobe.d/nvidia.conf          → /etc/modprobe.d/starch-nvidia.conf
    ├── mkinitcpio.conf.d/nvidia.conf   → /etc/mkinitcpio.conf.d/starch-nvidia.conf
    ├── udev/rules.d/70-gaming.conf     → /etc/udev/rules.d/70-starch-gaming.rules
    ├── sysctl.d/99-gaming.conf         → /etc/sysctl.d/99-starch-gaming.conf
    └── gamemode.ini                    → /etc/gamemode.ini
```

---

## Step-by-step (manual)

### 1. Verify BIOS and kernel parameter

In BIOS: GPU mode must be **Discrete GPU Only** (not Hybrid).
In your systemd-boot loader entry: confirm `nvidia_drm.modeset=1` is present.

```bash
cat /sys/module/nvidia_drm/parameters/modeset   # should print Y
```

### 2. Install packages

```bash
sudo pacman -S --needed \
    gamescope steam lib32-nvidia-utils \
    vulkan-icd-loader lib32-vulkan-icd-loader lib32-mesa \
    xorg-xwayland \
    gamemode lib32-gamemode \
    mangohud lib32-mangohud \
    pipewire pipewire-pulse pipewire-alsa lib32-pipewire wireplumber \
    libdrm
```

**Optional — better Xbox controller support (AUR):**
```bash
yay -S xpadneo-dkms
```
PS4/PS5 (DualShock 4, DualSense) and generic HID gamepads work out of the box via
kernel modules (`hid-playstation`, `hid-generic`). Xbox controllers work via the
built-in `xpad` module. `xpadneo` adds proper rumble, adaptive triggers, and
improved Bluetooth reliability for Xbox controllers.

### 3. Deploy config files

```bash
# NVIDIA module options
sudo install -Dm644 etc/modprobe.d/nvidia.conf /etc/modprobe.d/starch-nvidia.conf

# Early module loading
sudo install -Dm644 etc/mkinitcpio.conf.d/nvidia.conf /etc/mkinitcpio.conf.d/starch-nvidia.conf

# Input device udev rules
sudo install -Dm644 etc/udev/rules.d/70-gaming.conf /etc/udev/rules.d/70-starch-gaming.rules

# Sysctl tweaks
sudo install -Dm644 etc/sysctl.d/99-gaming.conf /etc/sysctl.d/99-starch-gaming.conf

# Gamemode config
sudo install -Dm644 etc/gamemode.ini /etc/gamemode.ini
```

### 4. Install the session launcher

```bash
sudo install -Dm755 scripts/steam-session.sh /usr/local/bin/steam-session.sh
sudo install -Dm644 sessions/steam-gaming.desktop /usr/share/wayland-sessions/steam-gaming.desktop
```

### 5. User groups

```bash
sudo usermod -aG input,video,audio,seat,gamemode YOUR_USERNAME
```

Group purposes:
| Group | Why |
|---|---|
| `input` | raw input device access (gamepad events, uinput) |
| `video` | DRM/KMS device access |
| `audio` | audio device access (supplement to Pipewire) |
| `seat` | seatd session management (already needed for River) |
| `gamemode` | allowed to request gamemode optimizations |

### 6. uinput module

```bash
sudo modprobe uinput
echo "uinput" | sudo tee /etc/modules-load.d/starch-uinput.conf
sudo udevadm control --reload-rules && sudo udevadm trigger
```

### 7. NVIDIA power management services

Required if you ever suspend the system (prevents VRAM corruption on wake).
The `NVreg_PreserveVideoMemoryAllocations=1` modprobe option only works correctly
when these services are enabled:

```bash
sudo systemctl enable nvidia-suspend nvidia-hibernate nvidia-resume
```

### 8. Rebuild initramfs

```bash
sudo mkinitcpio -P
```

### 9. Reboot

```bash
sudo reboot
```

### 10. First launch

1. At tuigreet, select **Steam Gaming Session**
2. Let Steam update (first run only — may take a few minutes)
3. In Steam **Settings → Compatibility**: enable Steam Play for all titles, choose Proton
4. In Steam **Settings → Controller**: enable controller layout support

---

## Architecture: why these choices

### gamescope `--backend drm`

`cage` and other Wayland compositors act as *clients* — they need a parent Wayland
server to connect to. `gamescope --backend drm` is a full DRM/KMS client, meaning
it takes exclusive ownership of the display hardware directly, just like a traditional
X server would. This is why cage fails in a bare greetd session.

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

2. Try disabling VRR/immediate flips in `/usr/local/bin/steam-session.sh`:
   comment out `--adaptive-sync` and `--immediate-flips`

3. Check which DRM device gamescope is using — the session script logs this:
   ```bash
   journalctl --user -u greetd -b | grep "steam-session"
   # or check output in /tmp/steam-session.log if you redirect there
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
# Edit /usr/local/bin/steam-session.sh and add before the exec line:
export MANGOHUD=1
export MANGOHUD_CONFIG=fps,frametime,gpu_name,gpu_load,vram,cpu_load,ram
```

Or enable it per-game in Steam launch options: `MANGOHUD=1 %command%`
