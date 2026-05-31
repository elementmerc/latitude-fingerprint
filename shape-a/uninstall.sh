#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Removes the Broadcom TOD fingerprint driver laid down by install.sh and
# restores whatever install.sh backed up. Re-runnable. Does NOT touch enrolled
# fingerprints (those live under /var/lib/fprint/<user>/, not the fw/ subtree).

set -euo pipefail

readonly TREES=(
    "usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/libfprint-2-tod-1-broadcom.so"
    "usr/lib/udev/rules.d/60-libfprint-2-device-broadcom.rules"
    "usr/libexec/libfprint-2-tod1-broadcom"
    "var/lib/fprint/fw"
)
readonly BACKUP_ROOT="/var/backups/latitude-fingerprint"

if [[ -t 1 ]]; then
    readonly C_BOLD=$'\033[1m' C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YEL=$'\033[33m' C_OFF=$'\033[0m'
else
    readonly C_BOLD='' C_RED='' C_GREEN='' C_YEL='' C_OFF=''
fi
log()  { printf '%s[fp]%s %s\n' "$C_BOLD" "$C_OFF" "$*"; }
ok()   { printf '%s[fp]%s %s%s%s\n' "$C_BOLD" "$C_OFF" "$C_GREEN" "$*" "$C_OFF"; }
warn() { printf '%s[fp]%s %s%s%s\n' "$C_BOLD" "$C_OFF" "$C_YEL" "$*" "$C_OFF" >&2; }
die()  { printf '%s[fp] error:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: sudo $0 [--backup DIR] [--no-restore] [-h|--help]

  --backup DIR   Restore from this backup dir (default: most recent under
                 ${BACKUP_ROOT}).
  --no-restore   Just remove the driver; do not restore any backup.
  -h, --help     Show this help.
EOF
}

BACKUP_DIR=""
RESTORE=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --backup)     BACKUP_DIR="${2:-}"; [[ -n "$BACKUP_DIR" ]] || die "--backup needs a path"; shift 2 ;;
        --backup=*)   BACKUP_DIR="${1#*=}"; shift ;;
        --no-restore) RESTORE=0; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            die "unknown argument: $1 (try --help)" ;;
    esac
done

[[ $EUID -eq 0 ]] || die "must run as root (use sudo)."

log "Removing installed driver trees..."
for tree in "${TREES[@]}"; do
    target="/${tree}"
    if [[ -e "$target" ]]; then
        rm -rf -- "$target"
        log "removed $target"
    fi
done

if [[ $RESTORE -eq 1 ]]; then
    if [[ -z "$BACKUP_DIR" && -d "$BACKUP_ROOT" ]]; then
        # Most recent timestamped backup, if any.
        BACKUP_DIR="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n1)"
    fi
    if [[ -n "$BACKUP_DIR" && -f "${BACKUP_DIR}/manifest.txt" ]]; then
        log "Restoring originals from ${BACKUP_DIR}..."
        while IFS= read -r tree; do
            [[ -n "$tree" ]] || continue
            src="${BACKUP_DIR}/${tree}"
            [[ -e "$src" ]] || { warn "backup entry missing: $src"; continue; }
            mkdir -p -- "$(dirname -- "/${tree}")"
            cp -a -- "$src" "/${tree}"
            log "restored /${tree}"
        done < "${BACKUP_DIR}/manifest.txt"
        ok "Restore complete."
    else
        log "No backup to restore (clean removal)."
    fi
fi

log "Reloading udev rules..."
udevadm control --reload && udevadm trigger || warn "udev reload reported a problem; a reboot will also apply."

log "Restarting fprintd..."
systemctl restart fprintd 2>/dev/null || warn "could not restart fprintd; it is D-Bus activated and will start on demand."

ok "Uninstall complete."
