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
    "usr/share/doc/libfprint-2-tod1-broadcom"
)
readonly DRIVER_SO="/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/libfprint-2-tod-1-broadcom.so"
readonly BACKUP_ROOT="/var/backups/latitude-fingerprint"
readonly LOCK_FILE="/run/latitude-fingerprint.lock"
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

# Does this backup hold OUR install rather than anything of the user's?
#
# Deciding entry by entry could only ever work for the driver .so: the udev rule
# hashes to something else and the other two trees are directories, so a
# per-entry check skipped one tree out of four and restored the firmware blobs,
# key.pem and the helper. The driver decides for the whole snapshot, because the
# other three trees are only ever on disk because a driver install put them there.
backup_is_ours() {
    is_known_driver "${1}/${TREES[0]}"
}

# Is the driver currently on disk one this tool installed?
driver_is_ours() { is_known_driver "$DRIVER_SO"; }

# Cleared when there was nothing of ours to take out, so the restore and the
# marker handling below can tell "we removed our install" from "we found
# somebody else's and left it".
REMOVED=1
FAILED_TREES=()

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

# The same lock install.sh takes. Without it a concurrent install could lay the
# payload back between the removal below and the marker being cleared, leaving
# the driver on disk with no record of it and dpkg reporting a clean removal.
{ exec 9>"$LOCK_FILE"; } 2>/dev/null || true
if ! flock -n 9 2>/dev/null; then
    log "An install or uninstall is already running; waiting up to 5 minutes..."
    if ! flock -w 300 9 2>/dev/null; then
        die "could not start: another run may still be in progress, or the lock file ${LOCK_FILE} could not be opened."
    fi
fi

# Only ever delete a driver this tool installed.
#
# Two defects lived in an unconditional delete. A second uninstall wiped the
# file the first one had just restored, because the trees were removed before
# anything asked whose they were and the backup had already been consumed. And
# on a machine carrying somebody else's driver (the genuine Broadcom package, or
# a hand-laid one) a removal took their files with it.
#
# The driver .so decides, as it does everywhere else: the other trees are only
# on disk because some driver install put them there.
if driver_is_ours; then
    log "Removing installed driver trees..."
    for tree in "${TREES[@]}"; do
        target="/${tree}"
        if [[ -e "$target" ]]; then
            if rm -rf -- "$target"; then
                log "removed $target"
            else
                warn "could not remove ${target}; continuing."
                FAILED_TREES+=("$target")
            fi
        fi
    done
elif [[ -e "$DRIVER_SO" ]]; then
    warn "The driver at ${DRIVER_SO} was not installed by this tool, so it has been left alone."
    warn "If it came from a package, remove that package instead. Nothing was deleted."
    REMOVED=0
else
    log "No driver installed by this tool was found; nothing to remove."
    REMOVED=0
fi

if [[ $RESTORE -eq 1 && $REMOVED -eq 1 ]]; then
    if [[ -z "$BACKUP_DIR" ]]; then
        # Which backup holds the machine's ORIGINAL files, as opposed to a
        # snapshot of a driver this tool had already installed.
        recorded=""
        if [[ -f "$STATE_FILE" ]]; then
            recorded="$(grep -m1 '^backup_dir=' "$STATE_FILE" 2>/dev/null | cut -d= -f2- || true)"
        fi

        if [[ "$recorded" == "none" ]]; then
            log "Clean install recorded; nothing to restore."
        elif [[ -n "$recorded" ]]; then
            BACKUP_DIR="$recorded"
        else
            # Either there is no marker (installed by a version that never wrote
            # one) or the marker is unreadable, truncated or hand-edited. Both
            # used to end here in silence, which read exactly like a successful
            # restore. Fall back to searching, and say that is what happened.
            if [[ -f "$STATE_FILE" ]]; then
                warn "the install record at ${STATE_FILE} does not name a backup; searching ${BACKUP_ROOT} instead."
            fi
            if [[ -d "$BACKUP_ROOT" ]]; then
                # The NEWEST backup that is not a snapshot of our own driver.
                # "Oldest" was a workaround from before ownership could be
                # detected by content: it restored the first snapshot even when a
                # later one held what was actually displaced last, and an
                # interrupted early run could leave a partial directory that won.
                while IFS= read -r cand; do
                    [[ -n "$cand" ]] || continue
                    [[ -f "${cand}/manifest.txt" ]] || continue
                    backup_is_ours "$cand" && continue
                    BACKUP_DIR="$cand"
                    break
                done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -not -name '*.restored' 2>/dev/null | sort -r)
                if [[ -n "$BACKUP_DIR" ]]; then
                    warn "No usable install record; restoring the most recent backup that holds your files, ${BACKUP_DIR}."
                fi
            fi
        fi
    fi
    if [[ -n "$BACKUP_DIR" && ! -f "${BACKUP_DIR}/manifest.txt" ]]; then
        # Silence here read as "clean removal", which is indistinguishable from
        # having restored the user's files. If a recorded backup has gone, say so.
        warn "the recorded backup at ${BACKUP_DIR} is missing or unreadable, so nothing was put back."
        warn "If you had files at those paths before installing, look for them under ${BACKUP_ROOT}."
        BACKUP_DIR=""
    fi
    if [[ -n "$BACKUP_DIR" ]] && backup_is_ours "$BACKUP_DIR"; then
        log "That backup is a snapshot of this tool's own driver, not your files; leaving it alone."
        BACKUP_DIR=""
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
        # Consumed. Without this, a later uninstall on a machine with no marker
        # (which is what a completed uninstall leaves behind) finds this same
        # snapshot again and puts stale files back over whatever is there now.
        mv -- "$BACKUP_DIR" "${BACKUP_DIR}.restored" 2>/dev/null \
            || warn "could not mark ${BACKUP_DIR} as restored; it may be applied again by a later uninstall."
    else
        log "No backup to restore (clean removal)."
    fi
fi

# Cleared last, and only once the trees are gone, so an uninstall that dies
# half way leaves the marker in place and a re-run still knows the backup this
# machine belongs to.
if [[ -f "$STATE_FILE" ]]; then
    if [[ $REMOVED -eq 0 ]]; then
        # Nothing of ours was taken out, so nothing about our record has become
        # untrue. Clearing it here would discard the pointer to the user's
        # original files while leaving the machine exactly as it was found.
        log "Nothing was removed, so the install record at ${STATE_FILE} is left as it is."
    elif [[ $RESTORE -eq 0 ]]; then
        # --no-restore leaves the backup in place, so clearing the marker would
        # discard the only record of which backup holds the user's originals.
        warn "keeping the install record at ${STATE_FILE} because --no-restore was used;"
        warn "run this again without --no-restore to put your original files back."
    else
        rm -f -- "$STATE_FILE" "$STATE_FILE".*
        rmdir -- "$STATE_DIR" 2>/dev/null || true
    fi
fi

log "Reloading udev rules..."
# shellcheck disable=SC2015  # warn on either failing is the intent, not if-then-else
udevadm control --reload && udevadm trigger || warn "udev reload reported a problem; a reboot will also apply."

log "Restarting fprintd..."
systemctl restart fprintd 2>/dev/null || warn "could not restart fprintd; it is D-Bus activated and will start on demand."

if [[ -e "$DRIVER_SO" ]] && driver_is_ours; then
    warn "the driver is STILL INSTALLED at ${DRIVER_SO}."
    if [[ ${#FAILED_TREES[@]} -gt 0 ]]; then
        warn "these could not be removed: ${FAILED_TREES[*]}"
    fi
    warn "Check for a read-only filesystem, or an immutable flag (lsattr)."
    die "removal did not complete; the proprietary driver is still on this machine."
fi
if [[ ${#FAILED_TREES[@]} -gt 0 ]]; then
    warn "The driver is gone, but these were left behind: ${FAILED_TREES[*]}"
    warn "They are harmless without the driver; remove them by hand if you want them gone."
fi
ok "Uninstall complete."
if command -v pam-auth-update >/dev/null 2>&1; then
    log "If you turned on fingerprint login, turn it off now with:  sudo pam-auth-update"
    log "(untick 'Fingerprint authentication', or logging in will wait for a sensor that no longer works)"
fi
log "Your enrolled fingerprints are still on this machine. To delete them:  fprintd-delete \"\$USER\""
