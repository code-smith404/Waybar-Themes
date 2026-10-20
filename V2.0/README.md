# V2.0 — MangoWM reference theme

V2.0 recreates the supplied reference as a slim, translucent navy Waybar:
four workspaces at the left, a centered focused-window group, and compact CPU,
memory, network, volume, and date/time status at the right. It has no battery
indicator, no application/terminal name on the left, and no Mangobar branding.

## Focused window icon and title

MangoWM does not provide a native Waybar module that combines an application
icon image and title. The hidden `custom/window-title` module therefore starts
[`scripts/window-title-overlay`](./scripts/window-title-overlay), a GTK3
layer-shell helper. It polls MangoWM using:

```sh
mmsg get monitor "$WAYBAR_OUTPUT_NAME"
```

MangoWM's `active_client.title` and `active_client.appid` fields are used to
update the title and icon together on focus changes. The helper matches the
application ID (or its desktop entry's `StartupWMClass`) against installed
`.desktop` entries and loads the selected `Icon` through the active GTK icon
theme. The image is 18 px, with a 7 px gap before the title; the entire GTK
group is horizontally centered using the Wayland layer-shell protocol. If
there is no matching icon, it uses the generic `application-x-executable`
icon. This uses MangoWM IPC and Wayland layer-shell, not Hyprland IPC or
Hyprland-specific modules.

The Waybar module must run inside the MangoWM session so Waybar supplies its
output name and the helper can access the compositor's IPC.

## Install

From the repository root, use the version selector:

```sh
./install.sh
```

Choose **V2.0**. To preview the V2.0 changes directly:

```sh
./V2.0/install.sh --dry-run
```

The installer targets Arch Linux and Arch-based systems. It checks for the
required packages, offers to install missing packages with `pacman`, and asks
before deploying files. Existing changed files are backed up under
`~/.local/state/waybar-mango-v2/backups/`. It only manages the V2.0 Waybar
configuration, stylesheet, and two helper scripts.

Required packages:

- `waybar`, `jq`
- `python-gobject`, `gtk3`, `gtk-layer-shell`, `hicolor-icon-theme`
- `ttf-jetbrains-mono-nerd`, `ttf-font-awesome`
- MangoWM's `mmsg` IPC command
- A PulseAudio-compatible audio server (`pipewire-pulse` or `pulseaudio`) for
  volume status

The package installer does not install MangoWM; install and configure it using
the upstream MangoWM instructions. After installing, start Waybar from the
MangoWM session. To launch it automatically from a `config.conf` setup, add
this MangoWM startup directive if one is not already present:

```ini
exec_once=waybar
```

Keep Waybar in the compositor session so its Wayland environment and
`WAYBAR_OUTPUT_NAME` are inherited. The icon helper runs as a child of the
Waybar custom module and exits with it.

## Configuration and troubleshooting

- Workspace buttons 1–4 use MangoWM's `mmsg get tags` status and
  `mmsg dispatch view,<tag>` actions.
- The centered label is truncated by the GTK label when necessary; hovering it
  shows the full title.
- Confirm `mmsg get monitor <output-name>` returns an `active_client` object
  with `title` and `appid` fields if the title group is unavailable.
- MangoWM's [IPC documentation](https://mangowm.github.io/docs/ipc/) describes
  the monitor and focused-client queries used by the helper.
- If the generic icon is shown for an application, check that a matching
  `.desktop` entry and its named icon are installed in the active icon theme.
- If the overlay is missing, confirm `gtk-layer-shell` and `python-gobject` are
  installed and that Waybar was started inside MangoWM.
- Install the listed Nerd Font and Font Awesome packages for the bar's
  typography and status glyphs.
