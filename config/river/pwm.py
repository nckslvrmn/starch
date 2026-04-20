"""
starch — river-pwm configuration

Replicates the riversnap workflow on River 0.4:
  Super+Left   → tile-right  (focused window = left master)
  Super+Right  → tile-bottom (focused window = right master… via reversed tile)
  Super+Up     → monocle     (focused window fullscreen)
  Alt+Tab      → focus next
  Super+Space  → bemenu launcher
  Super+Shift+E → quit
  Media keys   → volume / brightness
"""

import subprocess
import sys
import os

from pubsub import pub
from pwm import RiverWM, RiverConfig, Modifiers, XKB
from pwm import topics
from pwm.layouts import (
    TilingLayout,
    MonocleLayout,
    LayoutDirection,
)

# XF86 media keysyms (from xkbcommon-keysyms.h, not in river-pwm's XKB class)
class XF86:
    AudioRaiseVolume  = 0x1008FF13
    AudioLowerVolume  = 0x1008FF11
    AudioMute         = 0x1008FF12
    MonBrightnessUp   = 0x1008FF02
    MonBrightnessDown = 0x1008FF03

# Custom event topics for media keys
TOPIC_VOL_UP   = "starch.vol_up"
TOPIC_VOL_DOWN = "starch.vol_down"
TOPIC_VOL_MUTE = "starch.vol_mute"
TOPIC_BRI_UP   = "starch.bri_up"
TOPIC_BRI_DOWN = "starch.bri_down"

def _spawn(cmd: str):
    subprocess.Popen(cmd, shell=True, start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

pub.subscribe(lambda: _spawn("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), TOPIC_VOL_UP)
pub.subscribe(lambda: _spawn("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), TOPIC_VOL_DOWN)
pub.subscribe(lambda: _spawn("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), TOPIC_VOL_MUTE)
pub.subscribe(lambda: _spawn("brightnessctl set 5%+"), TOPIC_BRI_UP)
pub.subscribe(lambda: _spawn("brightnessctl set 5%-"), TOPIC_BRI_DOWN)

# --- layouts -----------------------------------------------------------------
# Match riversnap's 3 useful modes:
#   tile-right  ≈  riversnap "left"  / "tiled"  (master on left, stack on right)
#   tile-bottom ≈  riversnap "right" (master on top, stack on bottom — closest
#                   built-in equivalent; a true right-master would need a custom
#                   layout class but this is a fine starting point)
#   monocle     ≈  riversnap "full"

GAP = 10

layouts = [
    TilingLayout(LayoutDirection.HORIZONTAL, gap=GAP + 4),  # tile-right  (default)
    TilingLayout(LayoutDirection.VERTICAL, gap=GAP + 4),    # tile-bottom
    MonocleLayout(gap=GAP + 4),                             # monocle
]

# --- custom keybindings ------------------------------------------------------
# river-pwm's defaults use Alt (MOD1) as the modifier.  We keep those for
# window/workspace management but layer our starch bindings on top.

SUPER = Modifiers.MOD4
ALT = Modifiers.MOD1

# No modifier needed for media keys
NONE = Modifiers(0)

custom_keys = [
    # ── snap-style layout switching (Super + arrows) ─────────────────────
    # These fire the built-in cycle-layout command.  Because we only define
    # 3 layouts above, cycling wraps around quickly.
    #   Super+Left  → previous layout  (tile-right when starting from monocle)
    #   Super+Right → next layout
    #   Super+Up    → next layout      (monocle when starting from tile-bottom)
    (XKB.Left,  SUPER, topics.CMD_CYCLE_LAYOUT_REVERSE, {}),
    (XKB.Right, SUPER, topics.CMD_CYCLE_LAYOUT,         {}),
    (XKB.Up,    SUPER, topics.CMD_CYCLE_LAYOUT,         {}),

    # ── focus ────────────────────────────────────────────────────────────
    (XKB.Tab, ALT, topics.CMD_FOCUS_NEXT, {}),
    (XKB.Tab, ALT | Modifiers.SHIFT, topics.CMD_FOCUS_PREV, {}),

    # ── launcher ─────────────────────────────────────────────────────────
    (XKB.space, SUPER, topics.CMD_SPAWN_LAUNCHER, {}),

    # ── quit ─────────────────────────────────────────────────────────────
    (XKB.e, SUPER | Modifiers.SHIFT, topics.CMD_QUIT, {}),

    # ── media keys (volume / brightness) ─────────────────────────────────
    (XF86.AudioRaiseVolume,  NONE, TOPIC_VOL_UP,   {}),
    (XF86.AudioLowerVolume,  NONE, TOPIC_VOL_DOWN, {}),
    (XF86.AudioMute,         NONE, TOPIC_VOL_MUTE, {}),
    (XF86.MonBrightnessUp,   NONE, TOPIC_BRI_UP,   {}),
    (XF86.MonBrightnessDown, NONE, TOPIC_BRI_DOWN, {}),
]

# --- config ------------------------------------------------------------------

BEMENU_CMD = (
    'bemenu-run --ch 30 --accept-single -i -c -W 0.33 --hp 10 '
    '--fn "FiraCodeNerdFont 24" -p "  run  "'
)

config = RiverConfig(
    # Use Alt as the base modifier (matches river-pwm defaults for
    # workspace switching, window close, etc.)
    mod=ALT,

    # Programs
    terminal=os.getenv("STARCH_TERMINAL", "ghostty"),
    launcher=BEMENU_CMD,

    # Appearance — minimal, black background
    gap=GAP,
    border_width=2,
    border_color="#333333",
    focused_border_color="#5294e2",

    # No server-side decorations (keep it clean like riversnap)
    use_ssd=False,

    # Focus follows mouse
    focus_follows_mouse=True,

    # Only the 3 layouts we care about
    layouts=layouts,

    # Our starch-specific bindings
    custom_keybindings=custom_keys,
)

# --- run ---------------------------------------------------------------------

wm = RiverWM(config)
sys.exit(wm.run())
