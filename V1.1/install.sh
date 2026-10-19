#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly WAYBAR_RELATIVE_FILES=(
  config.jsonc
  style.css
  scripts/mango-tags
  scripts/mango-title
  scripts/brightness-control
)
readonly WAYBAR_MODES=(0644 0644 0755 0755 0755)

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
  printf '[waybar-mango] %s\n' "$*"
}

warn() {
  printf '[waybar-mango] Warning: %s\n' "$*" >&2
}

die() {
  printf '[waybar-mango] Error: %s\n' "$*" >&2
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

hash_file() {
  sha256sum -- "$1" | awk '{print $1}'
}

has_waybar_startup() {
  grep -R -I -E --include='*.conf' \
    '^[[:space:]]*exec_once[[:space:]]*=.*waybar([[:space:]]|$)' \
    "$mango_dir" >/dev/null 2>&1 && return 0
  grep -R -I -E --include='*.sh' \
    '^[[:space:]]*(waybar([[:space:]]|$)|[^#]*[[:space:];|&]waybar([[:space:]]|$))' \
    "$mango_dir" >/dev/null 2>&1
}

[[ -n "${HOME:-}" && "$HOME" == /* ]] || die 'HOME must be set to an absolute path.'
[[ "$EUID" -ne 0 ]] || die 'Run this installer as your normal user; it uses sudo only after package-install confirmation.'

config_home="${XDG_CONFIG_HOME:-"$HOME/.config"}"
state_home="${XDG_STATE_HOME:-"$HOME/.local/state"}"
[[ "$config_home" == /* && "$state_home" == /* ]] || die 'XDG_CONFIG_HOME and XDG_STATE_HOME must be absolute paths.'
waybar_dir="$config_home/waybar"
mango_dir="$config_home/mango"
mango_config="$mango_dir/config.conf"
state_dir="$state_home/waybar-mango"

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
    warn "This host is not identified as Arch Linux or an Arch-based distribution (${ID:-unknown}); pacman checks are skipped and a real install would stop here."
  else
    die "This host is not identified as Arch Linux or an Arch-based distribution (${ID:-unknown})."
  fi
elif ! command -v pacman >/dev/null 2>&1; then
  if (( dry_run )); then
    warn 'pacman is unavailable; package checks are skipped in dry-run mode.'
    arch_based=0
  else
    die 'pacman is required on Arch Linux.'
  fi
fi

config_file="$SCRIPT_DIR/config.jsonc"
style_file="$SCRIPT_DIR/style.css"
[[ -r "$config_file" && -r "$style_file" ]] || die 'Run this installer from the V1.1 repository directory.'

for script in mango-tags mango-title brightness-control; do
  [[ -r "$SCRIPT_DIR/scripts/$script" ]] || die "Required helper script is missing: scripts/$script"
  bash -n "$SCRIPT_DIR/scripts/$script" || die "Shell syntax check failed: scripts/$script"
done

missing_packages=()
ddc_i2c_available=0
for device in /dev/i2c-*; do
  if [[ -e "$device" ]]; then
    ddc_i2c_available=1
    break
  fi
done

if (( arch_based )); then
  required_packages=(waybar jq ttf-jetbrains-mono-nerd ttf-font-awesome brightnessctl)
  if (( ddc_i2c_available )); then
    required_packages+=(ddcutil)
  elif ! pacman -Qq ddcutil >/dev/null 2>&1; then
    if (( dry_run )); then
      warn 'Dry run: ddcutil is an optional package for DDC/CI displays and will be offered during installation.'
    elif confirm 'Include optional ddcutil for external-monitor DDC/CI brightness detection?'; then
      required_packages+=(ddcutil)
    else
      warn 'ddcutil was not selected; DDC/CI monitor brightness will be unavailable until it is installed.'
    fi
  fi
  for package in "${required_packages[@]}"; do
    if ! pacman -Qq "$package" >/dev/null 2>&1; then
      missing_packages+=("$package")
    fi
  done

  if ! pacman -Qq pipewire-pulse >/dev/null 2>&1 &&
     ! pacman -Qq pulseaudio >/dev/null 2>&1; then
    warn 'No pipewire-pulse or pulseaudio package is installed. The volume module needs one running PulseAudio-compatible server.'
  fi
else
  warn 'Package availability could not be checked on this non-Arch host.'
fi

if ((${#missing_packages[@]})); then
  info "Missing packages: ${missing_packages[*]}"
  if (( dry_run )); then
    info 'Dry run: no package manager or privileged command will be invoked.'
  elif confirm "Install these packages with pacman?"; then
    command -v sudo >/dev/null 2>&1 || die 'sudo is required to install packages as a normal user.'
    sudo pacman -S --needed "${missing_packages[@]}" ||
      die 'pacman package installation failed; no Waybar files have been deployed.'
  else
    die 'Package installation was declined; no Waybar files have been deployed.'
  fi
elif (( arch_based )); then
  info 'Required Arch packages are already installed.'
fi

json_validated=0
if command -v jq >/dev/null 2>&1; then
  jq empty "$config_file" || die "Invalid JSON/JSONC syntax in $config_file."
  json_validated=1
elif command -v python3 >/dev/null 2>&1; then
  python3 -m json.tool "$config_file" >/dev/null ||
    die "Invalid JSON/JSONC syntax in $config_file."
  json_validated=1
elif (( dry_run )); then
  warn 'Neither jq nor python3 is available; JSON syntax validation was skipped in dry-run mode.'
else
  die 'jq is required to validate config.jsonc and run the helper scripts.'
fi
if (( json_validated )); then
  info 'JSONC and helper-script syntax checks passed.'
else
  info 'Helper-script syntax checks passed; JSON syntax could not be checked in this dry run.'
fi

changed_files=()
changed_sources=()
changed_modes=()
for index in "${!WAYBAR_RELATIVE_FILES[@]}"; do
  relative="${WAYBAR_RELATIVE_FILES[$index]}"
  source="$SCRIPT_DIR/$relative"
  destination="$waybar_dir/$relative"
  [[ -f "$source" ]] || die "Required repository file is missing: $relative"

  if [[ -L "$destination" ]]; then
    die "Refusing to replace symlink $destination; install the file manually or remove the symlink yourself."
  fi
  if [[ -e "$destination" && ! -f "$destination" ]]; then
    die "Refusing to replace non-file path $destination."
  fi
  if [[ ! -f "$destination" ]] || ! cmp -s -- "$source" "$destination"; then
    changed_files+=("$relative")
    changed_sources+=("$source")
    changed_modes+=("${WAYBAR_MODES[$index]}")
  fi
done

add_startup=0
if [[ -f "$mango_config" ]]; then
  if [[ -L "$mango_config" ]]; then
    warn "MangoWM config is a symlink; startup integration will not modify it: $mango_config"
  elif grep -Fq '# BEGIN V1.1 Waybar autostart' "$mango_config" ||
       grep -Fq '# END V1.1 Waybar autostart' "$mango_config"; then
    if grep -Fq '# BEGIN V1.1 Waybar autostart' "$mango_config" &&
       grep -Fq '# END V1.1 Waybar autostart' "$mango_config"; then
      info 'The V1.1 MangoWM startup entry is already present.'
    else
      warn 'An incomplete V1.1 startup marker exists; refusing to edit MangoWM config.'
    fi
  elif has_waybar_startup; then
    info 'A Waybar launch is already referenced by MangoWM config/autostart; no duplicate entry will be added.'
  elif (( dry_run )); then
    info "Dry run: MangoWM startup integration is available in $mango_config (exec_once=waybar), but requires confirmation."
  elif confirm "Add one managed exec_once=waybar entry to $mango_config?"; then
    add_startup=1
  else
    info 'MangoWM startup integration declined; Waybar files can still be installed.'
  fi
elif [[ -f "$mango_dir/config.toml" ]]; then
  warn 'MangoWM uses config.toml; automatic startup editing is skipped to avoid changing TOML syntax. Add an exec_once entry using MangoWM documentation if desired.'
elif [[ -e "$mango_dir" ]]; then
  warn "No regular MangoWM config.conf was found under $mango_dir; startup integration is skipped."
else
  warn "MangoWM config directory $mango_dir was not found; startup integration is skipped."
fi

if (( dry_run )); then
  if ((${#changed_files[@]})); then
    info 'Dry run: would install or replace these Waybar files:'
    printf '  %s\n' "${changed_files[@]}"
  else
    info 'Dry run: all managed Waybar files are already up to date.'
  fi
  (( add_startup )) && info 'Dry run: startup integration would be appended.' || true
  info 'Dry run complete. No files, packages, permissions, or startup entries were changed.'
  exit 0
fi

if ((${#changed_files[@]})) && ! confirm 'Deploy the listed Waybar files? Existing targets will be backed up first.'; then
  die 'Waybar file deployment was declined.'
fi

if ((${#changed_files[@]} == 0 && !add_startup)); then
  info 'Nothing to install; the managed files and startup entry are already current.'
  exit 0
fi

if [[ -L "$state_dir" || ( -e "$state_dir" && ! -d "$state_dir" ) ]]; then
  die "State path exists but is not a directory: $state_dir"
fi
[[ ! -L "$state_dir/current" ]] || die "Refusing to overwrite symlink $state_dir/current."
[[ ! -L "$state_dir/backups" ]] || die "Refusing to write through symlink $state_dir/backups."
mkdir -p "$state_dir/backups"
backup_dir="$(mktemp -d "$state_dir/backups/$(date +%Y%m%d-%H%M%S)-XXXXXX")"
manifest="$backup_dir/manifest.tsv"
: >"$manifest"
if [[ -r "$state_dir/current" ]]; then
  cp -a -- "$state_dir/current" "$backup_dir/previous"
fi

save_original() {
  local relative="$1"
  local destination="$2"
  if [[ -e "$destination" ]]; then
    mkdir -p "$backup_dir/original/$(dirname -- "$relative")"
    cp -a -- "$destination" "$backup_dir/original/$relative"
    printf '%s\tpresent\t' "$relative" >>"$manifest"
  else
    printf '%s\tabsent\t' "$relative" >>"$manifest"
  fi
}

record_installed_hash() {
  local relative="$1"
  local destination="$2"
  local hash
  hash="$(hash_file "$destination")"
  printf '%s\n' "$hash" >>"$manifest"
}

for index in "${!changed_files[@]}"; do
  relative="waybar/${changed_files[$index]}"
  destination="$waybar_dir/${changed_files[$index]}"
  save_original "$relative" "$destination"
  if ! install -D -m "${changed_modes[$index]}" -- "${changed_sources[$index]}" "$destination"; then
    if [[ -e "$backup_dir/original/$relative" ]]; then
      cp -a -- "$backup_dir/original/$relative" "$destination" ||
        warn "Could not restore the original file automatically; recover it from $backup_dir/original/$relative."
    else
      rm -f -- "$destination" ||
        warn "Could not remove the incomplete installer-created file $destination."
    fi
    sed -i '$d' "$manifest"
    die "Could not install $destination. Its original, if present, is backed up at $backup_dir/original/."
  fi
  record_installed_hash "$relative" "$destination"
done

if (( add_startup )); then
  if [[ -L "$mango_config" || ! -f "$mango_config" ]]; then
    warn 'MangoWM config changed since detection; startup integration was skipped.'
  else
    save_original 'mango/config.conf' "$mango_config"
    if ! {
      printf '\n# BEGIN V1.1 Waybar autostart\nexec_once=waybar\n# END V1.1 Waybar autostart\n' >>"$mango_config"
    }; then
      cp -a -- "$backup_dir/original/mango/config.conf" "$mango_config"
      sed -i '$d' "$manifest"
      die "Could not update $mango_config; the previous config was restored."
    fi
    if command -v mango >/dev/null 2>&1; then
      if mango -c "$mango_config" -p; then
        record_installed_hash 'mango/config.conf' "$mango_config"
        info 'Added and validated exec_once=waybar in MangoWM config.'
      else
        cp -a -- "$backup_dir/original/mango/config.conf" "$mango_config"
        sed -i '$d' "$manifest"
        warn 'MangoWM rejected the startup change; its original config was restored. Waybar files remain installed.'
      fi
    else
      record_installed_hash 'mango/config.conf' "$mango_config"
      warn 'Added exec_once=waybar, but mango is not installed here so its config syntax could not be checked.'
    fi
  fi
fi

if [[ -s "$manifest" ]]; then
  printf '%s\n' "$backup_dir" >"$state_dir/current"
  chmod 0600 "$state_dir/current" "$manifest"
  info "Rollback data saved under $backup_dir."
fi

if command -v mmsg >/dev/null 2>&1; then
  info 'mmsg found; MangoWM tag/title IPC helpers are ready.'
else
  warn 'mmsg was not found. Tag and title modules will show unavailable until Waybar is launched inside MangoWM with mmsg installed.'
fi

if compgen -G '/sys/class/backlight/*/brightness' >/dev/null; then
  if command -v brightnessctl >/dev/null 2>&1; then
    info 'Kernel backlight interface and brightnessctl are available; verify user write permissions with the brightness tooltip.'
  else
    warn 'A kernel backlight exists, but brightnessctl is unavailable.'
  fi
else
  info 'No kernel backlight device detected; brightness-control will probe DDC/CI at runtime and show unavailable if unsupported.'
fi
if command -v ddcutil >/dev/null 2>&1; then
  ddcutil detect --brief || warn 'ddcutil is installed but could not detect DDC/CI displays; check permissions and monitor support.'
fi

info 'Installation complete. Start Waybar from the MangoWM session or log in again after adding the startup entry.'
