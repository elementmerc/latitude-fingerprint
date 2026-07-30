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
readonly STATE_DIR="/var/lib/latitude-fingerprint"
readonly STATE_FILE="${STATE_DIR}/install-state"

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
    if [[ -z "$BACKUP_DIR" ]]; then
        # Which backup holds the machine's ORIGINAL files, as opposed to a
        # snapshot of a driver this tool had already installed.
        if [[ -f "$STATE_FILE" ]]; then
            # The marker names it outright. "none" means the first install found
            # nothing to displace, so there is nothing to put back.
            recorded="$(grep -m1 '^backup_dir=' "$STATE_FILE" 2>/dev/null | cut -d= -f2- || true)"
            if [[ "$recorded" == "none" ]]; then
                log "Clean install recorded; nothing to restore."
            elif [[ -n "$recorded" ]]; then
                BACKUP_DIR="$recorded"
            fi
        elif [[ -d "$BACKUP_ROOT" ]]; then
            # No marker: an install from before the marker existed. The OLDEST
            # backup is the only one that can hold the user's own files, because
            # every later one was taken with our driver already in place. Taking
            # the most recent instead is what used to restore our own driver and
            # leave it installed after a removal.
            BACKUP_DIR="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -n1)"
            if [[ -n "$BACKUP_DIR" ]]; then
                warn "No install marker (installed by an older version); restoring the oldest backup, ${BACKUP_DIR}."
            fi
        fi
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

# Cleared last, and only once the trees are gone, so an uninstall that dies
# half way leaves the marker in place and a re-run still knows the backup this
# machine belongs to.
if [[ -f "$STATE_FILE" ]]; then
    rm -f -- "$STATE_FILE"
    rmdir -- "$STATE_DIR" 2>/dev/null || true
fi

log "Reloading udev rules..."
udevadm control --reload && udevadm trigger || warn "udev reload reported a problem; a reboot will also apply."

log "Restarting fprintd..."
systemctl restart fprintd 2>/dev/null || warn "could not restart fprintd; it is D-Bus activated and will start on demand."

ok "Uninstall complete."
