# Uninstalling starch

starch is a config layer, not a distro, so removing it means deleting the files
it installed and re-enabling whatever you want instead. The repo layout *is* the
manifest: everything under `rootfs/` maps to `/`, everything under `userfs/`
maps to the gaming user's home.

## Remove installed files

From the repo checkout, as root:

```bash
# System files (rootfs/ mirrors /)
(cd rootfs && find . -type f | sed 's|^\.||') | xargs -r rm -f

# Generated at install time (not in rootfs/)
rm -f /etc/starch/profile.conf /etc/resolv.conf
rm -rf /etc/starch /var/lib/starch /usr/share/sddm/themes/starch

# Per-user files (userfs/ mirrors ~)
(cd userfs && find . -type f | sed "s|^\.|$HOME|") | xargs -r rm -f
```

Restore `/etc/resolv.conf` for your replacement DNS setup afterwards.

## Services

```bash
systemctl disable sddm iwd systemd-resolved systemd-oomd
```

(Keep `NetworkManager` or re-point it at full management by deleting the
`NetworkManager/conf.d` files above first.)

## Caps and groups

```bash
setcap -r /usr/bin/gamescope
gpasswd -d <user> input   # and video/audio/seat/lp if unwanted
```

Packages are left installed — remove with pacman/paru as desired.
