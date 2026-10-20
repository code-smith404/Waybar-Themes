#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
dry_run=()

case "${1:-}" in
  "")
    ;;
  --dry-run)
    dry_run=(--dry-run)
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

if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
  printf 'An interactive terminal is required to choose a theme version.\n' >&2
  exit 1
fi

printf '%s\n' 'Waybar Themes — choose a version' \
  '  1) V2.0 — MangoWM reference theme (app icon + focused title)' \
  '  2) V1.1 — MangoWM charcoal theme'
printf 'Select [1]: ' >/dev/tty
IFS= read -r choice </dev/tty || exit 1
choice="${choice:-1}"

case "$choice" in
  1) version='V2.0' ;;
  2) version='V1.1' ;;
  *)
    printf 'Invalid selection: %s\n' "$choice" >&2
    exit 2
    ;;
esac

exec bash "$script_dir/$version/install.sh" "${dry_run[@]}"
