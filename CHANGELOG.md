# Changelog

All notable changes to latitude-fingerprint are recorded here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses date-stamped, codenamed releases.

## v0.2.0 — Ghost of Yotei (2026-05-31)

Adds an `apt install` route for the two current LTS releases.

### Packaging
- New apt install path for Ubuntu 24.04 (noble) and 26.04 (resolute) LTS, via
  the PPA `ppa:elementmerc/latitude-fingerprint` and this GitHub Releases
  mirror. The package downloads the driver from Canonical, verifies a pinned
  SHA256, and installs it; it never bundles the proprietary driver. It also
  refuses to co-install with the genuine Broadcom package so the two cannot
  clash over the same files.

### Docs
- The README now credits the official, in-progress packaging effort (Launchpad
  #2099655) and explains how this project relates to it.

### Other
- Bug fixes and improvements.

## v0.1.0 — Problem Solved (2026-05-30)

First release: the personal install script.

- Install the Broadcom BCM58200 ControlVault 3 fingerprint driver (USB
  `0a5c:5843`) on Ubuntu newer than 22.04, where `apt install` refuses
  Canonical's 22.04-pinned build.
- `install.sh` fetches Canonical's driver, verifies it against a pinned SHA256,
  lays down the four payload trees, reloads udev, restarts fprintd, and runs the
  firmware-settle step the deb performs on install. It is idempotent, backs up
  anything it overwrites, and ships an `uninstall.sh` that restores.
- Verified on hardware: enrol and verify succeed on a Dell Latitude 7420 running
  Ubuntu 26.04 LTS. The first install flashes the sensor firmware, which needs
  one reboot before the first enrol; the installer and README say so.
