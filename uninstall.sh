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

# The two driver builds this tool installs (see install.sh). A backup entry
# matching either is a snapshot of our own driver rather than anything the user
# had, and restoring it would leave the driver installed after a removal.
readonly KNOWN_DRIVER_SHA256=(
    "e26efcd654b9773f7403bc3b386fa65e80124111d15dbdfc55e15e8e0deddd09"  # Canonical OEM build
    "ab34713aa338c162d20dcc01ef8ba847a3635e3517e0aa22185c29facb9d7c00"  # Broadcom upstream build
)

is_known_driver() {
    [[ -f "$1" ]] || return 1
    local actual known
    actual="$(sha256sum -- "$1" | awk '{print $1}')"
    for known in "${KNOWN_DRIVER_SHA256[@]}"; do
        [[ "$actual" == "$known" ]] && return 0
    done
    return 1
}

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

  --backup DIR   Restore from this backup dir (default: the one recorded when
                 the driver was first installed, under ${BACKUP_ROOT}).
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
            # Only ever restore to a path this tool installs. --backup takes a
            # caller-supplied directory, so the manifest is untrusted input, and
            # an entry like "../etc/shadow" would otherwise be written as root.
            known=0
            for t in "${TREES[@]}"; do [[ "$tree" == "$t" ]] && known=1; done
            if [[ $known -eq 0 ]]; then
                warn "ignoring unexpected backup entry: ${tree}"
                continue
            fi
            src="${BACKUP_DIR}/${tree}"
            [[ -e "$src" ]] || { warn "backup entry missing: $src"; continue; }
            # A backup written before the ownership marker existed can hold our
            # own driver. Putting that back would undo the removal the user just
            # asked for, so it is skipped however the backup came to be recorded.
            if is_known_driver "$src"; then
                warn "skipping ${tree}: that backup holds this tool's own driver, not a file of yours."
                continue
            fi
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
# shellcheck disable=SC2015  # warn on either failing is the intent, not if-then-else
udevadm control --reload && udevadm trigger || warn "udev reload reported a problem; a reboot will also apply."

log "Restarting fprintd..."
systemctl restart fprintd 2>/dev/null || warn "could not restart fprintd; it is D-Bus activated and will start on demand."

ok "Uninstall complete."
