# V1.1 MangoWM Waybar theme

This configuration keeps the reference's slim top bar, charcoal rounded
indicators, subtle borders, muted JetBrains Mono text, and orange active tag.
It places five MangoWM tags and the clock at the left, the active window title
at the actual screen center, and volume, RAM, CPU, and brightness at the right.
There is no Bluetooth module.

The bar uses Waybar's built-in `clock`, `pulseaudio`, `memory`, and `cpu`
modules. MangoWM tag and title status use its documented `mmsg get` IPC via
small JSON-producing scripts. Brightness is detected at runtime: kernel
backlights use `brightnessctl`; external displays use DDC/CI through `ddcutil`
only when VCP feature `0x10` is readable and settable. It never substitutes
software gamma for hardware brightness.

## Arch Linux dependencies

Install the bar, JSON parser, and fonts:

```sh
sudo pacman -S waybar jq ttf-jetbrains-mono-nerd ttf-font-awesome
```

Install the brightness backend(s) appropriate to the hardware:

```sh
sudo pacman -S brightnessctl  # laptop/internal kernel backlight devices
sudo pacman -S ddcutil        # external DDC/CI monitors (optional)
```

Install either `pipewire-pulse` (for PipeWire) or `pulseaudio` and make sure
the PulseAudio-compatible server is running for Waybar's `pulseaudio` module.
MangoWM must be running with its `mmsg` command available and its instance
environment passed to Waybar. No Hyprland module or IPC command is used.

## Install

From the repository root, back up existing files, then install the Waybar
configuration and helpers:

```sh
mkdir -p ~/.config/waybar/scripts
for file in config.jsonc style.css; do
  target="$HOME/.config/waybar/$file"
  if [ -e "$target" ]; then
    cp -a "$target" "$target.bak-$(date +%Y%m%d%H%M%S)"
  fi
done
install -m 0644 V1.1/config.jsonc ~/.config/waybar/config.jsonc
install -m 0644 V1.1/style.css ~/.config/waybar/style.css
install -m 0755 V1.1/scripts/mango-tags ~/.config/waybar/scripts/mango-tags
install -m 0755 V1.1/scripts/mango-title ~/.config/waybar/scripts/mango-title
install -m 0755 V1.1/scripts/brightness-control ~/.config/waybar/scripts/brightness-control
```

Start `waybar` from the MangoWM session (for example, through MangoWM's
autostart configuration). The tag buttons switch to tags 1-5 on left-click
and toggle them in the current view on right-click. Window and tag status
refresh every second; the title is truncated in the bar, with the full title
available in its tooltip. CPU and RAM refresh every 3 and 5 seconds. Volume
scrolling changes the volume by 5 percentage points.

The brightness indicator shows the selected device and backend in its tooltip.
Scroll up/down to adjust it by about 5%; click to cycle between detected
controllable devices. To select a particular device explicitly, run
`~/.config/waybar/scripts/brightness-control list` to enumerate available
targets, then use `~/.config/waybar/scripts/brightness-control select N` with
the target's 1-based position. The selection is stored under
`~/.cache/waybar-brightness-target` (or `$XDG_CACHE_HOME`).

## Brightness permissions and limits

The helper does not invoke `sudo`. `brightnessctl` uses kernel backlight
devices exposed under `/sys/class/backlight`; the active user's access depends
on the installed udev rules and session permissions. If status works but
adjustment reports a permission error, install/enable the package's udev
permissions, inspect the device's ownership and rules, then log out and back
in. Do not run Waybar or its helper as root.

DDC/CI requires monitor support, a graphics driver that exposes the monitor's
DDC channel over I2C, and access to the corresponding `/dev/i2c-*` device.
Some monitor OSD settings disable DDC/CI. If `ddcutil` detects a display but
cannot read VCP `0x10`, the monitor/adapter/driver does not offer a usable
hardware brightness control through that path. Install `ddcutil`'s packaged
udev rules where available and grant the user's account access to the `i2c`
device group/rule as appropriate for the installed system; log in again
after changing group membership. Do not apply a blanket world-writable
permission to I2C devices.

Multiple kernel backlights and DDC/CI displays are detected independently.
Disconnected or unsupported displays are omitted on the next refresh. If no
supported backend is found, the module displays an unavailable marker and a
tooltip explaining the detected limitation; it does not fake a brightness
value. DDC/CI feature support and permissions are hardware- and driver-specific.

## Troubleshooting

- **Tags/title show unavailable:** start Waybar from the MangoWM session so
  `MANGO_INSTANCE_SIGNATURE` is inherited, verify `mmsg get tags <output-name>`
  and `mmsg get monitor <output-name>` in a terminal, and check that MangoWM
  exposes tags 1-5. The custom scripts use Waybar's output-name environment.
- **No volume status:** ensure a PulseAudio-compatible server is running and
  that the user session can connect to it.
- **Brightness says unavailable:** install `brightnessctl` for a
  `/sys/class/backlight` device or `ddcutil` for DDC/CI monitors, then inspect
  the tooltip and the relevant device permissions. A virtual display or a
  monitor/adapter without hardware brightness control cannot be controlled by
  this module.
- **Missing icons:** install the Nerd Font and Font Awesome packages above,
  confirm JetBrainsMono Nerd Font is selected/available, and restart Waybar.

The checked-in `config.jsonc.bak` and `style.css.bak` are backups of the
pre-existing V1.1 configuration files.
