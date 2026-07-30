#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Personal installer for the Broadcom BCM58200 ControlVault 3
# fingerprint driver (USB 0a5c:5843) on Ubuntu releases newer than 22.04.
#
# Canonical ships this driver as a libfprint TOD plugin but pins it to the
# 22.04 OEM apt pocket, so `apt install` refuses it on 24.04/26.04. This
# script fetches the proprietary driver, verifies it against a pinned SHA256,
# and lays its payload trees into the running system the way the deb's own
# maintainer scripts would. The blob is never redistributed by this project;
# you fetch it yourself (see docs/LICENSING.md).
#
# Two sources, in order of preference:
#   1. Canonical's OEM deb (primary): the curated, hardware-verified build.
#   2. Broadcom's upstream tarball (fallback): the same version, a different
#      build, used only when the OEM source is unreachable. See SOURCES.
#
# Safe to re-run. Backs up anything it overwrites; uninstall.sh restores.

set -euo pipefail

# ── Primary source: Canonical OEM deb (see SHA256SUMS and SOURCES) ──────────
readonly DEB_NAME="libfprint-2-tod1-broadcom_5.15.285-5.15.010.0-0ubuntu2~22.04.1~oem1_amd64.deb"
readonly DEB_POOL="updates/pool/public/libf/libfprint-2-tod1-broadcom"
# https to the archive currently times out; http works. Integrity is enforced
# by the pinned SHA256 in SHA256SUMS, not by the transport. Try https first in
# case your network allows it, then fall back to http.
readonly DEB_MIRRORS=(
    "https://dell.archive.canonical.com/${DEB_POOL}/${DEB_NAME}"
    "http://dell.archive.canonical.com/${DEB_POOL}/${DEB_NAME}"
)

# ── Fallback source: Broadcom upstream tarball (see SOURCES) ────────────────
# Same driver version as the OEM deb but a different build, so it is the
# fallback rather than the default. Used only when the OEM source cannot be
# downloaded. It carries no firmware-settle helper; the driver settles its
# firmware on first sensor access.
readonly TGZ_NAME="brcm_linux_fp_5.15.285_5.15.010.0.tgz"
readonly TGZ_MIRRORS=(
    "https://packages.broadcom.com/artifactory/dell-controlvault-drivers/${TGZ_NAME}"
)

# ── Payload trees laid into / (install whichever the source provides) ───────
# Paths relative to the extraction root; laid into / with structure and modes
# preserved. The OEM deb provides all four; the upstream tarball provides the
# first, second, and fourth (no firmware-settle helper).
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

# Ownership marker. Written on the first install and cleared by uninstall.sh, it
# is how a later run tells "these files are the user's, back them up" from "these
# files are ours, leave the original backup alone". Without it, a second install
# snapshots our own driver as though it were the user's, and the uninstall then
# faithfully restores it, so removal silently leaves the driver in place.
readonly STATE_DIR="/var/lib/latitude-fingerprint"
readonly STATE_FILE="${STATE_DIR}/install-state"

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
# Must return 0 on the normal path. Under `set -e`, a trap whose last command
# fails overrides the script's own exit status, so the "&& rm" form made
# `install.sh --help` exit 1: STAGE is still empty that early, the test fails,
# and the trap's failure becomes the script's.
cleanup() { if [[ -n "$STAGE" && -d "$STAGE" ]]; then rm -rf -- "$STAGE"; fi; }
trap cleanup EXIT INT TERM

usage() {
    cat <<EOF
Usage: sudo $0 [--source auto|oem|upstream] [--deb PATH] [--tarball PATH]
               [--force] [--keep-deb] [-h|--help]

  --source MODE  Where to get the driver:
                   auto      OEM deb, falling back to the Broadcom tarball
                             if the OEM source is unreachable (default).
                   oem       OEM deb only.
                   upstream  Broadcom upstream tarball only.
  --deb PATH     Install from an already-downloaded OEM deb (implies --source oem).
  --tarball PATH Install from an already-downloaded Broadcom tarball
                 (implies --source upstream).
  --force        Reinstall even if the matching driver is already in place.
  --keep-deb     Keep the download in ${SCRIPT_DIR}/.cache instead of /tmp.
  -h, --help     Show this help.

Fetches the Broadcom TOD fingerprint driver, verifies it against SHA256SUMS,
and installs it. Re-runnable; see uninstall.sh.
EOF
}

# ── Argument parsing ────────────────────────────────────────────────────────
SOURCE="auto"
DEB_PATH=""
TGZ_PATH=""
FORCE=0
KEEP_DEB=0
valid_source() { [[ "$1" == "auto" || "$1" == "oem" || "$1" == "upstream" ]]; }
while [[ $# -gt 0 ]]; do
    case "$1" in
        --source)    SOURCE="${2:-}"; valid_source "$SOURCE" || die "--source must be auto, oem, or upstream"; shift 2 ;;
        --source=*)  SOURCE="${1#*=}"; valid_source "$SOURCE" || die "--source must be auto, oem, or upstream"; shift ;;
        --deb)       DEB_PATH="${2:-}"; [[ -n "$DEB_PATH" ]] || die "--deb needs a path"; shift 2 ;;
        --deb=*)     DEB_PATH="${1#*=}"; shift ;;
        --tarball)   TGZ_PATH="${2:-}"; [[ -n "$TGZ_PATH" ]] || die "--tarball needs a path"; shift 2 ;;
        --tarball=*) TGZ_PATH="${1#*=}"; shift ;;
        --force)     FORCE=1; shift ;;
        --keep-deb)  KEEP_DEB=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           die "unknown argument: $1 (try --help)" ;;
    esac
done

# A supplied local file pins the source.
[[ -n "$DEB_PATH" && -n "$TGZ_PATH" ]] && die "pass only one of --deb or --tarball."
if [[ -n "$DEB_PATH" ]]; then
    [[ "$SOURCE" == "auto" || "$SOURCE" == "oem" ]] || die "--deb conflicts with --source $SOURCE"
    SOURCE="oem"
fi
if [[ -n "$TGZ_PATH" ]]; then
    [[ "$SOURCE" == "auto" || "$SOURCE" == "upstream" ]] || die "--tarball conflicts with --source $SOURCE"
    SOURCE="upstream"
fi

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
    for tool in dpkg-deb tar udevadm systemctl sha256sum awk mktemp; do
        command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
    done
    # python3 only drives the firmware-settle helper, which the OEM payload
    # carries and the upstream tarball does not, so a missing interpreter
    # degrades that one step rather than blocking the install.
    command -v python3 >/dev/null 2>&1 \
        || warn "python3 not found; the firmware-settle step will be skipped (the driver settles on first sensor access)."
    if [[ -z "$DEB_PATH" && -z "$TGZ_PATH" ]]; then
        command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 \
            || die "need curl or wget to fetch the driver (or pass --deb/--tarball PATH)."
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

# ── Download helper: try each URL in turn; return 1 if none succeed ──────────
download() {
    local dest="$1"; shift
    local url
    for url in "$@"; do
        log "Fetching ${url%%://*} from ${url#*://}" >&2
        if command -v curl >/dev/null 2>&1; then
            curl -fSL --connect-timeout 15 --max-time 300 -o "$dest" "$url" && return 0
        else
            wget -q --timeout=300 -O "$dest" "$url" && return 0
        fi
        warn "fetch failed from ${url%%://*}; trying next."
    done
    return 1
}

# ── Verify a downloaded artefact against its pinned checksum ─────────────────
verify_file() {
    local f="$1" name="$2" expected actual
    expected="$(awk -v n="$name" '$2==n || $2=="*"n {print $1}' "$SUMS_FILE")"
    [[ -n "$expected" ]] || die "no pinned checksum for $name in $SUMS_FILE"
    actual="$(sha256sum -- "$f" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]]
}

download_dir() {
    if [[ $KEEP_DEB -eq 1 ]]; then printf '%s' "${SCRIPT_DIR}/.cache"; else printf '%s' "$STAGE"; fi
}

# ── Obtain from the OEM deb. Returns 1 only if it cannot be downloaded; a ────
#    checksum mismatch is fatal (a tamper/corruption signal, never a fallback).
get_oem() {
    local deb
    if [[ -n "$DEB_PATH" ]]; then
        [[ -r "$DEB_PATH" ]] || die "deb not readable: $DEB_PATH"
        deb="$DEB_PATH"; log "Using supplied deb: $deb"
    else
        local dir; dir="$(download_dir)"; mkdir -p -- "$dir"
        deb="${dir}/${DEB_NAME}"
        if [[ -r "$deb" ]] && verify_file "$deb" "$DEB_NAME" 2>/dev/null; then
            ok "Reusing verified deb: $deb"
        else
            download "$deb" "${DEB_MIRRORS[@]}" || return 1
        fi
    fi
    log "Verifying SHA256 (OEM deb)..."
    verify_file "$deb" "$DEB_NAME" || die "checksum mismatch for $deb; refusing the OEM deb."
    ok "OEM deb verified."
    dpkg-deb -x "$deb" "${STAGE}/extract" || die "failed to extract $deb"
    return 0
}

# ── Obtain from the Broadcom upstream tarball, normalised to the same layout ─
#    install_trees expects. Returns 1 only if it cannot be downloaded.
get_upstream() {
    local tgz
    if [[ -n "$TGZ_PATH" ]]; then
        [[ -r "$TGZ_PATH" ]] || die "tarball not readable: $TGZ_PATH"
        tgz="$TGZ_PATH"; log "Using supplied tarball: $tgz"
    else
        local dir; dir="$(download_dir)"; mkdir -p -- "$dir"
        tgz="${dir}/${TGZ_NAME}"
        if [[ -r "$tgz" ]] && verify_file "$tgz" "$TGZ_NAME" 2>/dev/null; then
            ok "Reusing verified tarball: $tgz"
        else
            download "$tgz" "${TGZ_MIRRORS[@]}" || return 1
        fi
    fi
    log "Verifying SHA256 (Broadcom upstream tarball)..."
    verify_file "$tgz" "$TGZ_NAME" || die "checksum mismatch for $tgz; refusing the upstream tarball."
    ok "Upstream tarball verified."

    mkdir -p -- "${STAGE}/tgz"
    tar -xzf "$tgz" -C "${STAGE}/tgz" || die "failed to extract $tgz"
    local root="${STAGE}/tgz/brcm_linux_fp"
    [[ -d "$root" ]] || die "unexpected tarball layout (no brcm_linux_fp/ root)."
    # Normalise into the canonical extraction layout. The tarball keeps the
    # udev rule under lib/udev; move it under usr/lib/udev so the installed
    # paths (and so backup/uninstall) match the OEM deb exactly.
    [[ -d "${root}/usr" ]] && cp -a -- "${root}/usr" "${STAGE}/extract/"
    [[ -d "${root}/var" ]] && cp -a -- "${root}/var" "${STAGE}/extract/"
    if [[ -d "${root}/lib/udev/rules.d" ]]; then
        mkdir -p -- "${STAGE}/extract/usr/lib/udev/rules.d"
        cp -a -- "${root}/lib/udev/rules.d/." "${STAGE}/extract/usr/lib/udev/rules.d/"
    fi
    [[ -r "${STAGE}/extract/${TREES[0]}" ]] || die "tarball did not yield the expected driver .so."
    return 0
}

# ── Choose a source and populate ${STAGE}/extract ───────────────────────────
#
# USED_SOURCE records which origin the payload actually came from, because the
# two are not interchangeable: they carry the same driver version built twice,
# and only the Canonical build has been verified on real hardware. A user who
# ends up on the fallback is told so rather than left to assume otherwise.
USED_SOURCE=""
obtain_payload() {
    mkdir -p -- "${STAGE}/extract"
    case "$SOURCE" in
        oem)      get_oem && USED_SOURCE="oem" || die "could not download the OEM deb. See SOURCES for manual options." ;;
        upstream) get_upstream && USED_SOURCE="upstream" || die "could not download the Broadcom upstream tarball. See SOURCES." ;;
        auto)
            if get_oem; then
                USED_SOURCE="oem"
            else
                warn "OEM source unreachable; falling back to the Broadcom upstream tarball (see SOURCES)."
                get_upstream || die "neither the OEM deb nor the Broadcom upstream is reachable. See SOURCES."
                USED_SOURCE="upstream"
            fi
            ;;
    esac
}

report_source() {
    case "$USED_SOURCE" in
        oem)
            ok "Driver source: Canonical's OEM build (the one verified on real hardware)."
            ;;
        upstream)
            warn "Driver source: Broadcom's upstream tarball, not Canonical's OEM build."
            warn "Same driver version, built separately, and it is not the build this"
            warn "project tested on hardware. Using it means accepting Broadcom's own"
            warn "licence terms directly. See SOURCES and docs/LICENSING.md."
            ;;
    esac
}

# ── Idempotency short-circuit: is the staged .so already installed? ──────────
already_installed() {
    [[ -r "$DRIVER_SO" ]] || return 1
    local staged_so="${STAGE}/extract/${TREES[0]}"
    [[ -r "$staged_so" ]] || return 1
    local a b
    a="$(sha256sum -- "$DRIVER_SO" | awk '{print $1}')"
    b="$(sha256sum -- "$staged_so" | awk '{print $1}')"
    [[ "$a" == "$b" ]]
}

# ── Back up anything we are about to overwrite ──────────────────────────────
#
# Only the FIRST install can find files that belong to the user; on every run
# after that the files at these paths are the ones we laid down ourselves. The
# ownership marker records which of the two situations we are in, so a re-run
# (a retry after a failed fetch, an apt reinstall, a switch between --source
# oem and --source upstream, a suite upgrade) never overwrites the record of
# what was on the machine before we touched it.
backup_existing() {
    if [[ -f "$STATE_FILE" ]]; then
        log "Already installed by this tool; keeping the original backup record."
        return 0
    fi

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
        backup_dir="none"
    fi

    write_state "$backup_dir"
}

# The marker is written only after the backup succeeded, so an install that dies
# mid-backup leaves no marker and the next run redoes the backup rather than
# assuming one exists. Written via a temp file and renamed, so a marker is never
# half-written. Plain key=value, and it is PARSED rather than sourced: a state
# file that gets executed is a root-owned code-execution path.
write_state() {
    local backup_dir="$1" tmp
    mkdir -p -- "$STATE_DIR"
    tmp="$(mktemp -- "${STATE_FILE}.XXXXXX")" || die "cannot write install state to ${STATE_DIR}"
    {
        printf '# latitude-fingerprint install state. Managed by install.sh; do not edit.\n'
        printf 'owned_since=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'backup_dir=%s\n' "$backup_dir"
    } >"$tmp"
    chmod 644 -- "$tmp"
    mv -f -- "$tmp" "$STATE_FILE"
}

# ── Lay the trees the source provided into / ────────────────────────────────
# tar-to-tar preserves modes and ownership in one pass. It is NOT atomic: a
# failure part way leaves some trees laid and others not, which is why the
# backup taken just above is the recovery path rather than any rollback here.
install_trees() {
    log "Installing driver payload..."
    local present=() tree
    for tree in "${TREES[@]}"; do
        [[ -e "${STAGE}/extract/${tree}" ]] && present+=("$tree")
    done
    [[ ${#present[@]} -gt 0 ]] || die "extraction produced no known payload to install."
    ( cd -- "${STAGE}/extract" && tar -cf - -- "${present[@]}" ) | tar -xf - -C / \
        || die "failed to lay payload into /"
    ok "Payload installed (${#present[@]} trees)."
}

main() {
    preflight

    STAGE="$(mktemp -d -t latitude-fp.XXXXXX)" || die "cannot create staging dir"
    obtain_payload

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

    if [[ -x "$FW_UPDATER" ]] && command -v python3 >/dev/null 2>&1; then
        log "Settling sensor firmware (update-fw.py)..."
        python3 "$FW_UPDATER" || warn "firmware-settle step returned non-zero; the driver usually finishes this in the background."
    else
        log "No firmware-settle helper for this source; the driver settles firmware on first sensor access."
    fi

    # Last, not mid-run: the udev, fprintd and firmware steps print enough to
    # scroll a mid-run notice off the screen, and which build you just installed
    # is something the reader should still be able to see when it stops.
    report_source

    ok "Done. Enrol a finger with:  fprintd-enroll \"\$USER\""
    log "Then test with:  fprintd-verify"
    warn "First install on this machine flashes the sensor firmware. If enrol reports"
    warn "'No such device', reboot once (the sensor re-enumerates after a flash) and retry."
}

main "$@"
