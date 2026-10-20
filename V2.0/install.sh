#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly RELATIVE_FILES=(
  config.jsonc
  style.css
  scripts/mango-tags
  scripts/window-title-overlay
)
readonly MODES=(0644 0644 0755 0755)

dry_run=0
case "${1:-}" in
  "")
    ;;
  --dry-run)
    dry_run=1
    ;;
  --help|-h)
    printf 'Usage: %s [--dry-run]\n' "$0"
    exit 0
    ;;
  *)
    printf 'Unknown option: %s\nUsage: %s [--dry-run]\n' "$1" "$0" >&2
    exit 2
    ;;
esac
(( $# <= 1 )) || {
  printf 'Usage: %s [--dry-run]\n' "$0" >&2
  exit 2
}

info() {
  printf '[waybar-mango-v2] %s\n' "$*"
}

warn() {
  printf '[waybar-mango-v2] Warning: %s\n' "$*" >&2
}

die() {
  printf '[waybar-mango-v2] Error: %s\n' "$*" >&2
  exit 1
}

confirm() {
  local answer
  [[ -r /dev/tty && -w /dev/tty ]] || {
    warn 'No interactive terminal is available; refusing to make this change.'
    return 1
  }
  printf '%s [y/N] ' "$1" >/dev/tty
  IFS= read -r answer </dev/tty || return 1
  [[ "${answer,,}" == y || "${answer,,}" == yes ]]
}

[[ -n "${HOME:-}" && "$HOME" == /* ]] || die 'HOME must be set to an absolute path.'
[[ "$EUID" -ne 0 ]] || die 'Run this installer as your normal user.'

config_home="${XDG_CONFIG_HOME:-"$HOME/.config"}"
state_home="${XDG_STATE_HOME:-"$HOME/.local/state"}"
[[ "$config_home" == /* && "$state_home" == /* ]] || die 'XDG_CONFIG_HOME and XDG_STATE_HOME must be absolute paths.'
waybar_dir="$config_home/waybar"
state_dir="$state_home/waybar-mango-v2"

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
else
  ID=''
  ID_LIKE=''
fi

arch_based=0
[[ "${ID:-}" == arch ]] && arch_based=1
read -r -a id_like_values <<<"${ID_LIKE:-}"
for distro_id in "${id_like_values[@]}"; do
  [[ "$distro_id" == arch ]] && arch_based=1
done

if (( ! arch_based )); then
  if (( dry_run )); then
    warn "This host is not identified as Arch Linux or Arch-based (${ID:-unknown}); package checks are skipped in dry-run mode."
  else
    die "This release targets Arch Linux or an Arch-based distribution (${ID:-unknown})."
  fi
elif ! command -v pacman >/dev/null 2>&1; then
  if (( dry_run )); then
    warn 'pacman is unavailable; package checks are skipped in dry-run mode.'
    arch_based=0
  else
    die 'pacman is required on Arch Linux.'
  fi
fi

for relative in "${RELATIVE_FILES[@]}"; do
  [[ -f "$SCRIPT_DIR/$relative" ]] || die "Required repository file is missing: $relative"
done
bash -n "$SCRIPT_DIR/scripts/mango-tags" || die 'Shell syntax check failed: scripts/mango-tags'
python3 -c 'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text(), filename=sys.argv[1])' \
  "$SCRIPT_DIR/scripts/window-title-overlay" ||
  die 'Python syntax check failed: scripts/window-title-overlay'

if command -v jq >/dev/null 2>&1; then
  jq empty "$SCRIPT_DIR/config.jsonc" || die 'Invalid JSON syntax in config.jsonc.'
elif command -v python3 >/dev/null 2>&1; then
  python3 -m json.tool "$SCRIPT_DIR/config.jsonc" >/dev/null || die 'Invalid JSON syntax in config.jsonc.'
else
  die 'jq or python3 is required to validate the Waybar configuration.'
fi
info 'Configuration and helper syntax checks passed.'

missing_packages=()
if (( arch_based )); then
  required_packages=(
    waybar
    jq
    python-gobject
    gtk3
    gtk-layer-shell
    hicolor-icon-theme
    ttf-jetbrains-mono-nerd
    ttf-font-awesome
  )
  for package in "${required_packages[@]}"; do
    pacman -Qq "$package" >/dev/null 2>&1 || missing_packages+=("$package")
  done

  if ! pacman -Qq pipewire-pulse >/dev/null 2>&1 &&
     ! pacman -Qq pulseaudio >/dev/null 2>&1; then
    warn 'The volume module needs a running PulseAudio-compatible server (pipewire-pulse or pulseaudio).'
  fi
fi

if ((${#missing_packages[@]})); then
  info "Missing packages: ${missing_packages[*]}"
  if (( dry_run )); then
    info 'Dry run: no package manager or privileged command will be invoked.'
  elif confirm 'Install these packages with pacman?'; then
    command -v sudo >/dev/null 2>&1 || die 'sudo is required to install packages as a normal user.'
    sudo pacman -S --needed "${missing_packages[@]}" ||
      die 'Package installation failed; no Waybar configuration files were deployed.'
  else
    die 'Package installation was declined; no Waybar files were deployed.'
  fi
elif (( arch_based )); then
  info 'Required Arch packages are already installed.'
fi

if ! command -v mmsg >/dev/null 2>&1; then
  warn 'mmsg was not found. Focus and workspace data require MangoWM IPC and will be unavailable until it is installed.'
fi

changed_files=()
for relative in "${RELATIVE_FILES[@]}"; do
  destination="$waybar_dir/$relative"
  if [[ -L "$destination" ]]; then
    die "Refusing to replace symlink $destination."
  fi
  if [[ -e "$destination" && ! -f "$destination" ]]; then
    die "Refusing to replace non-file path $destination."
  fi
  if [[ ! -f "$destination" ]] || ! cmp -s -- "$SCRIPT_DIR/$relative" "$destination"; then
    changed_files+=("$relative")
  fi
done

if (( dry_run )); then
  if ((${#changed_files[@]})); then
    info 'Dry run: would install or replace these Waybar files:'
    printf '  %s\n' "${changed_files[@]}"
  else
    info 'Dry run: all managed Waybar files are already up to date.'
  fi
  info 'Dry run complete. No files, packages, permissions, or startup entries were changed.'
  exit 0
fi

if ((${#changed_files[@]} == 0)); then
  info 'Nothing to install; all managed Waybar files are already current.'
  exit 0
fi

confirm 'Deploy the listed Waybar files? Existing targets will be backed up first.' ||
  die 'Waybar file deployment was declined.'

if [[ -L "$state_dir" || ( -e "$state_dir" && ! -d "$state_dir" ) ]]; then
  die "State path exists but is not a directory: $state_dir"
fi
mkdir -p "$state_dir/backups"
backup_dir="$(mktemp -d "$state_dir/backups/$(date +%Y%m%d-%H%M%S)-XXXXXX")"
for relative in "${changed_files[@]}"; do
  destination="$waybar_dir/$relative"
  if [[ -e "$destination" ]]; then
    mkdir -p "$backup_dir/original/$(dirname -- "$relative")"
    cp -a -- "$destination" "$backup_dir/original/$relative"
  fi
done

for index in "${!RELATIVE_FILES[@]}"; do
  relative="${RELATIVE_FILES[$index]}"
  found=0
  for changed in "${changed_files[@]}"; do
    [[ "$changed" == "$relative" ]] && found=1
  done
  (( found )) || continue
  install -D -m "${MODES[$index]}" -- "$SCRIPT_DIR/$relative" "$waybar_dir/$relative" ||
    die "Could not install $waybar_dir/$relative. Existing files, if any, were backed up at $backup_dir/original."
done

info "Installation complete. Changed-file backups are at $backup_dir/original (files that did not previously exist have no backup)."
info 'Start Waybar inside your MangoWM session. See README.md for startup and troubleshooting instructions.'
