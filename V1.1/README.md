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
when VCP feature `0x10` is readable. Some monitors expose a readable value
but reject writes; those command failures are reported and no changed value
is claimed. Software gamma is never substituted for hardware brightness.

## Arch Linux dependencies

Install the bar, JSON parser, Nerd Font, and Font Awesome from Arch packages.
The installer checks for `waybar`, `jq`, both fonts, and `brightnessctl`.
It includes `ddcutil` when `/dev/i2c-*` devices are present, or offers it as
an optional package when no I2C device is visible. DDC/CI remains optional;
install `ddcutil` later if your graphics driver exposes DDC/CI.

The volume module needs a running PulseAudio-compatible server: install either
`pipewire-pulse` (for PipeWire) or `pulseaudio`. The installer warns if neither
package is installed; it does not choose or replace your audio stack. MangoWM
must be installed with `mmsg` available, and Waybar must inherit the MangoWM
instance environment. `mmsg` is supplied by MangoWM; if it is missing, install
MangoWM using its upstream Arch instructions (which currently list the AUR
package `mangowm-git`) and verify `mmsg` is in `PATH`. No Hyprland module or
IPC command is used.

## Install and rollback

From this directory in the repository, first review the planned operations:

```sh
./install.sh --dry-run
```

Run the installer interactively:

```sh
./install.sh
```

It identifies Arch-based systems, validates the JSONC and helper scripts,
checks required packages, and asks before using `sudo pacman` or changing any
existing Waybar configuration. Declining a prompt makes no corresponding
change. The script only manages `config.jsonc`, `style.css`, and the three
helpers used by this configuration; unrelated files in `~/.config/waybar` are
left alone. Existing target files are backed up before replacement.

If `~/.config/mango/config.conf` exists and no Waybar launch is already
referenced by its `exec_once` entry or shell autostart scripts, the installer
offers to add one marked `exec_once=waybar` entry. The change is backed up,
uses MangoWM's documented config syntax, and is not added twice. TOML configs
and absent MangoWM config files are not modified; add the entry manually if
needed. For a `config.conf` file, the line is:

```ini
exec_once=waybar
```

For `config.toml`, use the current MangoWM TOML configuration documentation
instead of copying the `config.conf` syntax verbatim.

To roll back, inspect the changes and run:

```sh
./uninstall.sh --dry-run
./uninstall.sh
```

Rollback restores the pre-install copies (or removes files that did not exist
before installation) only if the managed file still matches what the installer
deployed. Files subsequently modified by the user are preserved and reported
instead of being overwritten or deleted. Backups remain under
`~/.local/state/waybar-mango/backups/`. Package changes are not undone.

Start `waybar` from the MangoWM session if no startup entry was added. The tag
buttons switch to tags 1-5 on left-click and toggle them in the current view on
right-click. Window and tag status refresh every second; the title is truncated
in the bar, with the full title available in its tooltip. CPU and RAM refresh
every 3 and 5 seconds. Volume scrolling changes the volume by 5 percentage
points.

The brightness indicator shows the selected device and backend in its tooltip.
Scroll up/down to adjust it by about 5%; click to cycle between detected
controllable devices when more than one is available. To select a particular
device explicitly, run
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
cannot read VCP `0x10`, the monitor/adapter/driver does not expose brightness
through that path. A readable control can still reject writes; the helper
reports the failed DDC command. Install `ddcutil`'s packaged
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
