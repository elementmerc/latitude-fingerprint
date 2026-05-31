#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Build a source package for one Ubuntu suite, ready to upload to the PPA.
#
# The install logic lives once, at the repository root (install.sh, uninstall.sh,
# SHA256SUMS, SOURCES). This script copies that single source of truth into a
# clean build tree alongside debian/, stamps the changelog for the chosen suite,
# and builds an unsigned source package. Sign it afterwards with debsign, then
# upload with dput. Nothing here ever touches the proprietary driver.

set -euo pipefail

readonly SHAPE_B_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
readonly REPO_ROOT="$(cd -- "${SHAPE_B_DIR}/.." >/dev/null 2>&1 && pwd)"
readonly PKG="libfprint-2-tod1-broadcom-installer"
readonly BASE_VERSION="0.1.0"

# Files single-sourced from the repository root into the build tree.
readonly PAYLOAD=(install.sh uninstall.sh SHA256SUMS SOURCES)

die() { printf 'build-source: error: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $0 <suite>

  <suite>   noble (24.04 LTS) or resolute (26.04 LTS)

Produces an unsigned source package under ${SHAPE_B_DIR}/build/<suite>/.
Next steps after this script:
  debsign -k <KEYID> build/<suite>/${PKG}_<version>_source.changes
  dput ppa:elementmerc/latitude-fingerprint build/<suite>/${PKG}_<version>_source.changes
EOF
}

[[ $# -eq 1 ]] || { usage; exit 1; }
case "$1" in -h|--help) usage; exit 0 ;; esac
readonly SUITE="$1"

# Map each supported suite to its Ubuntu release number for the version string.
case "$SUITE" in
    noble)    readonly SERIES="24.04" ;;
    resolute) readonly SERIES="26.04" ;;
    *) die "unsupported suite '$SUITE' (supported: noble, resolute)" ;;
esac
readonly VERSION="${BASE_VERSION}~${SERIES}.1"

# Pre-flight: the single-source files and the packaging must be present.
for f in "${PAYLOAD[@]}"; do
    [[ -r "${REPO_ROOT}/${f}" ]] || die "missing source file: ${REPO_ROOT}/${f}"
done
[[ -d "${SHAPE_B_DIR}/debian" ]] || die "missing debian/ tree in ${SHAPE_B_DIR}"
command -v dpkg-buildpackage >/dev/null 2>&1 || die "dpkg-buildpackage not found (apt install dpkg-dev)"

readonly BUILD_DIR="${SHAPE_B_DIR}/build/${SUITE}"
readonly SRC_DIR="${BUILD_DIR}/${PKG}-${BASE_VERSION}"
rm -rf -- "$BUILD_DIR"
mkdir -p -- "$SRC_DIR"

cp -a -- "${SHAPE_B_DIR}/debian" "${SRC_DIR}/debian"
for f in "${PAYLOAD[@]}"; do
    cp -a -- "${REPO_ROOT}/${f}" "${SRC_DIR}/${f}"
done

# Stamp the top changelog entry for this suite. Only the first line changes
# (version and distribution); the body and trailer are left untouched.
sed -i "1s|.*|${PKG} (${VERSION}) ${SUITE}; urgency=medium|" "${SRC_DIR}/debian/changelog"

printf 'build-source: building %s %s (%s)\n' "$PKG" "$VERSION" "$SUITE"
( cd -- "$SRC_DIR" && dpkg-buildpackage -S -sa -us -uc -d )

printf '\nbuild-source: done. Artefacts in %s\n' "$BUILD_DIR"
printf 'Sign and upload:\n'
printf '  debsign -k <KEYID> %s/%s_%s_source.changes\n' "$BUILD_DIR" "$PKG" "$VERSION"
printf '  dput ppa:elementmerc/latitude-fingerprint %s/%s_%s_source.changes\n' "$BUILD_DIR" "$PKG" "$VERSION"
