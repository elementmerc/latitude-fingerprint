# Changelog

All notable changes to latitude-fingerprint are recorded here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses date-stamped, codenamed releases.

## v0.1.0 — Problem Solved (2026-05-30)

First release: the Shape A personal installer.

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
