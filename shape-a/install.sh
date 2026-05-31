#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Shape A personal installer for the Broadcom BCM58200 ControlVault 3
# fingerprint driver (USB 0a5c:5843) on Ubuntu releases newer than 22.04.
#
# Canonical ships this driver as a libfprint TOD plugin but pins it to the
# 22.04 OEM apt pocket, so `apt install` refuses it on 24.04/26.04. This
# script fetches that proprietary deb from Canonical's archive, verifies it
# against a pinned SHA256, and lays its four payload trees into the running
# system the way the deb's own maintainer scripts would. The blob is never
# redistributed by this project; you fetch it from Canonical (see
# docs/LICENSING.md).
#
# Safe to re-run. Backs up anything it overwrites; uninstall.sh restores.

set -euo pipefail

# ── Pinned source (see SHA256SUMS and SOURCES) ──────────────────────────────
readonly DEB_NAME="libfprint-2-tod1-broadcom_5.15.285-5.15.010.0-0ubuntu2~22.04.1~oem1_amd64.deb"
readonly DEB_POOL="updates/pool/public/libf/libfprint-2-tod1-broadcom"
# https to the archive currently times out; http works. Integrity is enforced
# by the pinned SHA256 in SHA256SUMS, not by the transport. Try https first in
# case the operator's network allows it, then fall back to http.
readonly MIRRORS=(
    "https://dell.archive.canonical.com/${DEB_POOL}/${DEB_NAME}"
    "http://dell.archive.canonical.com/${DEB_POOL}/${DEB_NAME}"
)

# ── Payload trees the deb installs (confirmed against 5.15.285) ─────────────
# Each entry is a path relative to the extraction root; it is laid into / with
# structure and modes preserved. Files and directories are both handled.
readonly TREES=(
    "usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/libfprint-2-tod-1-broadcom.so"
    "usr/lib/udev/rules.d/60-libfprint-2-device-broadcom.rules"
    "usr/libexec/libfprint-2-tod1-broadcom"
    "var/lib/fprint/fw"
)
readonly DRIVER_SO="/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/libfprint-2-tod-1-broadcom.so"
readonly FW_UPDATER="/usr/libexec/libfprint-2-tod1-broadcom/update-fw.py"
readonly SENSOR_ID="0a5c:5843"
readonly BACKUP_ROOT="/var/backups/latitude-fingerprint"

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly SUMS_FILE="${SCRIPT_DIR}/SHA256SUMS"

# ── Output helpers ──────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    readonly C_BOLD=$'\033[1m' C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YEL=$'\033[33m' C_OFF=$'\033[0m'
else
    readonly C_BOLD='' C_RED='' C_GREEN='' C_YEL='' C_OFF=''
fi
log()  { printf '%s[fp]%s %s\n' "$C_BOLD" "$C_OFF" "$*"; }
ok()   { printf '%s[fp]%s %s%s%s\n' "$C_BOLD" "$C_OFF" "$C_GREEN" "$*" "$C_OFF"; }
warn() { printf '%s[fp]%s %s%s%s\n' "$C_BOLD" "$C_OFF" "$C_YEL" "$*" "$C_OFF" >&2; }
die() {
    printf '%s[fp] error:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2
    printf '%s[fp]%s diagnostics: %ssudo journalctl -u fprintd -b%s and %sdmesg | tail%s\n' \
        "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF" >&2
    exit 1
}

# ── Temp staging with guaranteed cleanup ────────────────────────────────────
STAGE=""
cleanup() { [[ -n "$STAGE" && -d "$STAGE" ]] && rm -rf -- "$STAGE"; }
trap cleanup EXIT INT TERM

usage() {
    cat <<EOF
Usage: sudo $0 [--deb PATH] [--force] [--keep-deb] [-h|--help]

  --deb PATH   Install from an already-downloaded deb instead of fetching.
  --force      Reinstall even if the matching driver is already in place.
  --keep-deb   Keep the downloaded deb in ${SCRIPT_DIR}/.cache instead of /tmp.
  -h, --help   Show this help.

Fetches ${DEB_NAME} from Canonical, verifies it against SHA256SUMS, and
installs the Broadcom TOD fingerprint driver. Re-runnable; see uninstall.sh.
EOF
}

# ── Argument parsing ────────────────────────────────────────────────────────
DEB_PATH=""
FORCE=0
KEEP_DEB=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --deb)      DEB_PATH="${2:-}"; [[ -n "$DEB_PATH" ]] || die "--deb needs a path"; shift 2 ;;
        --deb=*)    DEB_PATH="${1#*=}"; shift ;;
        --force)    FORCE=1; shift ;;
        --keep-deb) KEEP_DEB=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        *)          die "unknown argument: $1 (try --help)" ;;
    esac
done

# ── Step 1: preflight ───────────────────────────────────────────────────────
preflight() {
    log "Pre-flight checks..."
    [[ $EUID -eq 0 ]] || die "must run as root (use sudo)."

    local arch; arch="$(uname -m)"
    [[ "$arch" == "x86_64" ]] || die "this driver is amd64 only; got $arch."

    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        [[ "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" == *ubuntu* ]] \
            || warn "not Ubuntu (${ID:-unknown}); the TOD blob targets Ubuntu and may not load."
    else
        warn "/etc/os-release missing; cannot confirm distribution."
    fi

    local tool
    for tool in dpkg-deb udevadm systemctl python3 sha256sum install; do
        command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
    done
    if [[ -z "$DEB_PATH" ]]; then
        command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 \
            || die "need curl or wget to fetch the deb (or pass --deb PATH)."
    fi

    python3 -c 'import gi' 2>/dev/null \
        || warn "python3-gi not importable; the firmware-settle step needs it. Install: sudo apt install python3-gi"

    [[ -r "$SUMS_FILE" ]] || die "checksum file missing: $SUMS_FILE"

    # Sensor presence is advisory, not fatal (an external dock may be detached).
    if command -v lsusb >/dev/null 2>&1; then
        if lsusb 2>/dev/null | grep -qi "$SENSOR_ID"; then
            ok "Broadcom sensor $SENSOR_ID detected."
        else
            warn "Broadcom sensor $SENSOR_ID not seen in lsusb; enrolment will fail until it is present."
        fi
    fi
    ok "Pre-flight passed."
}

# ── Step 2: obtain the deb ──────────────────────────────────────────────────
fetch_deb() {
    if [[ -n "$DEB_PATH" ]]; then
        [[ -r "$DEB_PATH" ]] || die "deb not readable: $DEB_PATH"
        log "Using supplied deb: $DEB_PATH"
        return
    fi
    local dest_dir
    if [[ $KEEP_DEB -eq 1 ]]; then
        dest_dir="${SCRIPT_DIR}/.cache"; mkdir -p -- "$dest_dir"
    else
        dest_dir="$STAGE"
    fi
    DEB_PATH="${dest_dir}/${DEB_NAME}"

    if [[ -r "$DEB_PATH" ]] && verify_sum "$DEB_PATH" 2>/dev/null; then
        ok "Reusing already-downloaded, verified deb: $DEB_PATH"
        return
    fi

    local url
    for url in "${MIRRORS[@]}"; do
        log "Fetching ${url%%://*} ..."
        if command -v curl >/dev/null 2>&1; then
            curl -fSL --connect-timeout 15 --max-time 300 -o "$DEB_PATH" "$url" && return
        else
            wget -q --timeout=300 -O "$DEB_PATH" "$url" && return
        fi
        warn "fetch failed from ${url%%://*}; trying next mirror."
    done
    die "could not download $DEB_NAME from any mirror. See shape-a/SOURCES for manual options."
}

# ── Step 3: verify against the pinned checksum ──────────────────────────────
verify_sum() {
    local f="$1" expected actual
    expected="$(awk -v n="$DEB_NAME" '$2==n || $2=="*"n {print $1}' "$SUMS_FILE")"
    [[ -n "$expected" ]] || die "no pinned checksum for $DEB_NAME in $SUMS_FILE"
    actual="$(sha256sum -- "$f" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]]
}

# ── Step 4: idempotency short-circuit ───────────────────────────────────────
already_installed() {
    [[ -r "$DRIVER_SO" ]] || return 1
    local staged_so="${STAGE}/extract/${TREES[0]}"
    [[ -r "$staged_so" ]] || return 1
    local a b
    a="$(sha256sum -- "$DRIVER_SO" | awk '{print $1}')"
    b="$(sha256sum -- "$staged_so" | awk '{print $1}')"
    [[ "$a" == "$b" ]]
}

# ── Step 5: back up anything we are about to overwrite ──────────────────────
backup_existing() {
    local stamp backup_dir manifest tree target
    stamp="$(date +%Y%m%d-%H%M%S)"
    backup_dir="${BACKUP_ROOT}/${stamp}"
    manifest="${backup_dir}/manifest.txt"
    local any=0
    for tree in "${TREES[@]}"; do
        target="/${tree}"
        if [[ -e "$target" ]]; then
            if [[ $any -eq 0 ]]; then mkdir -p -- "$backup_dir"; : >"$manifest"; any=1; fi
            mkdir -p -- "$(dirname -- "${backup_dir}/${tree}")"
            cp -a -- "$target" "${backup_dir}/${tree}"
            printf '%s\n' "$tree" >>"$manifest"
        fi
    done
    if [[ $any -eq 1 ]]; then
        ok "Backed up existing files to ${backup_dir} (restore with uninstall.sh)."
    else
        log "No existing driver files to back up (clean install)."
    fi
}

# ── Step 6: lay the trees into / (atomic per-tree via tar) ──────────────────
install_trees() {
    log "Installing driver, udev rule, firmware updater, and firmware..."
    ( cd -- "${STAGE}/extract" && tar -cf - -- "${TREES[@]}" ) | tar -xf - -C / \
        || die "failed to lay payload into /"
    ok "Payload installed."
}

main() {
    preflight

    STAGE="$(mktemp -d -t latitude-fp.XXXXXX)" || die "cannot create staging dir"
    fetch_deb

    log "Verifying SHA256..."
    verify_sum "$DEB_PATH" || die "checksum mismatch for $DEB_PATH; refusing to install a deb that does not match the pinned hash."
    ok "Checksum verified."

    mkdir -p -- "${STAGE}/extract"
    dpkg-deb -x "$DEB_PATH" "${STAGE}/extract" || die "failed to extract $DEB_PATH"

    if already_installed && [[ $FORCE -eq 0 ]]; then
        ok "Matching driver already installed; nothing to do (use --force to reinstall)."
        exit 0
    fi

    backup_existing
    install_trees

    log "Reloading udev rules..."
    udevadm control --reload && udevadm trigger || warn "udev reload reported a problem; a reboot will also apply the rule."

    log "Restarting fprintd..."
    systemctl restart fprintd 2>/dev/null || warn "could not restart fprintd via systemctl; it is D-Bus activated and will start on demand."

    if [[ -x "$FW_UPDATER" ]]; then
        log "Settling sensor firmware (update-fw.py)..."
        python3 "$FW_UPDATER" || warn "firmware-settle step returned non-zero; the driver usually finishes this in the background."
    fi

    ok "Done. Enrol a finger with:  fprintd-enroll \"\$USER\""
    log "Then test with:  fprintd-verify"
    warn "First install on this machine flashes the sensor firmware. If enrol reports"
    warn "'No such device', reboot once (the sensor re-enumerates after a flash) and retry."
}

main "$@"
