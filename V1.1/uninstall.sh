#!/usr/bin/env bash
set -Eeuo pipefail

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

[[ -n "${HOME:-}" && "$HOME" == /* ]] || die 'HOME must be set to an absolute path.'
[[ "$EUID" -ne 0 ]] || die 'Run uninstall as your normal user.'

config_home="${XDG_CONFIG_HOME:-"$HOME/.config"}"
state_home="${XDG_STATE_HOME:-"$HOME/.local/state"}"
[[ "$config_home" == /* && "$state_home" == /* ]] || die 'XDG_CONFIG_HOME and XDG_STATE_HOME must be absolute paths.'
waybar_dir="$config_home/waybar"
mango_config="$config_home/mango/config.conf"
state_dir="$state_home/waybar-mango"
current_file="$state_dir/current"

[[ ! -L "$state_dir" && ! -L "$current_file" && ! -L "$state_dir/backups" ]] ||
  die 'The rollback state path is a symlink; refusing to follow it.'
[[ -r "$current_file" ]] || die "No Waybar Mango installation record found at $current_file."
IFS= read -r backup_dir <"$current_file" || die 'The current rollback record is empty.'
case "$backup_dir" in
  "$state_dir"/backups/*)
    ;;
  *)
    die 'The rollback record points outside the managed backup directory; refusing to continue.'
    ;;
esac

manifest="$backup_dir/manifest.tsv"
[[ -r "$manifest" ]] || die "Rollback manifest is missing: $manifest"

restore_relative=()
restore_destinations=()
restore_originals=()
restore_existed=()
skip_count=0

while IFS=$'\t' read -r relative existed expected_hash; do
  [[ -n "$relative" ]] || continue
  [[ "$expected_hash" =~ ^[[:xdigit:]]{64}$ ]] ||
    die "Invalid rollback manifest entry for $relative."
  case "$relative" in
    waybar/config.jsonc)
      destination="$waybar_dir/config.jsonc"
      ;;
    waybar/style.css)
      destination="$waybar_dir/style.css"
      ;;
    waybar/scripts/mango-tags)
      destination="$waybar_dir/scripts/mango-tags"
      ;;
    waybar/scripts/mango-title)
      destination="$waybar_dir/scripts/mango-title"
      ;;
    waybar/scripts/brightness-control)
      destination="$waybar_dir/scripts/brightness-control"
      ;;
    mango/config.conf)
      destination="$mango_config"
      ;;
    *)
      die "Unrecognized path in rollback manifest: $relative"
      ;;
  esac

  case "$existed" in
    present)
      original="$backup_dir/original/$relative"
      [[ -e "$original" ]] || die "Backup file is missing for $destination: $original"
      ;;
    absent)
      original=''
      ;;
    *)
      die "Invalid original-file state in rollback manifest for $relative."
      ;;
  esac

  if [[ -L "$destination" ]]; then
    warn "Keeping $destination because it has been replaced with a symlink."
    ((skip_count += 1))
    continue
  elif [[ ! -e "$destination" ]]; then
    if [[ "$existed" == present ]]; then
      warn "The managed file $destination is missing; rollback can restore its pre-install backup."
    else
      info "Installer-created file is already absent: $destination"
      continue
    fi
  elif [[ ! -f "$destination" ]]; then
    warn "Keeping $destination because it is no longer a regular file."
    ((skip_count += 1))
    continue
  elif [[ "$(hash_file "$destination")" != "$expected_hash" ]]; then
    warn "Keeping $destination because it changed after installation."
    ((skip_count += 1))
    continue
  fi

  restore_relative+=("$relative")
  restore_destinations+=("$destination")
  restore_originals+=("$original")
  restore_existed+=("$existed")
done <"$manifest"

if ((${#restore_relative[@]} == 0)); then
  info 'No unchanged managed files are eligible for automatic rollback; user-modified files were left untouched.'
  exit 0
fi

if (( dry_run )); then
  info 'Dry run: would restore/remove these unchanged managed files:'
  printf '  %s\n' "${restore_destinations[@]}"
  (( skip_count )) && warn "$skip_count changed or replaced file(s) would be kept." || true
  exit 0
fi

printf '%s\n' 'The following files will be restored from backup or removed if they were newly created by this installer:'
printf '  %s\n' "${restore_destinations[@]}"
(( skip_count )) && warn "$skip_count changed or replaced file(s) will be preserved."
confirm 'Proceed with rollback?' || die 'Rollback was declined.'

for index in "${!restore_relative[@]}"; do
  destination="${restore_destinations[$index]}"
  if [[ "${restore_existed[$index]}" == present ]]; then
    mkdir -p "$(dirname -- "$destination")"
    cp -a -- "${restore_originals[$index]}" "$destination"
    info "Restored $destination"
  else
    rm -- "$destination"
    info "Removed installer-created file $destination"
  fi
done

if [[ -r "$backup_dir/previous" ]]; then
  IFS= read -r previous_dir <"$backup_dir/previous" || previous_dir=''
  case "$previous_dir" in
    "$state_dir"/backups/*)
      if [[ -r "$previous_dir/manifest.tsv" ]]; then
        printf '%s\n' "$previous_dir" >"$current_file"
        chmod 0600 "$current_file"
      else
        rm -f -- "$current_file"
      fi
      ;;
    *)
      rm -f -- "$current_file"
      ;;
  esac
else
  rm -f -- "$current_file"
fi

info "Rollback complete. Backups remain available at $backup_dir."
