# Changelog

All notable changes to latitude-fingerprint are recorded here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses date-stamped, codenamed releases.

## v0.3.0 — Endgame (2026-07-31)

The last release. This project is finished; use
`ppa:medicalwei/dell-cv3-cv3plus` instead.

### Deprecation

- The Broadcom ControlVault 3 driver is now packaged for 24.04 and 26.04, in a
  newer version (5.15.377), by the Canonical engineer who maintains it upstream.
  Install from `ppa:medicalwei/dell-cv3-cv3plus` and remove this package.
- Tested on a Latitude 7420 running 26.04 on 2026-07-31: that package installs
  over this project's files without a conflict, updates the sensor firmware, and
  an existing enrolment still verifies afterwards.

### Removal

- **If you installed an earlier version and ran the installer more than once,
  `apt remove` told you it had removed the driver while leaving it on your
  machine.** Upgrade to this version first and removal will work properly.
- Removal now leaves alone any driver this package did not install, so it cannot
  delete a driver that came from somewhere else.
- Removal now reports a failure only when the driver is genuinely still present,
  rather than stopping at the first file it cannot delete.
- A missing or unreadable install record no longer reports a clean removal while
  restoring nothing.
- Removing the package clears the downloaded driver from the cache. Purging also
  clears the install record; backups of displaced files are kept and announced.

### Installer

- Re-running the installer repairs a partly installed driver instead of
  reporting that there is nothing to do, and it no longer downloads anything
  when the driver is already fully in place.
- Broadcom's own download is used as a second source when Canonical's copy
  cannot be reached, pinned and checked the same way, and the installer says
  which one it used.
- The proprietary licence is installed alongside the driver, on both routes.

### Docs

- The README and the write-up now point at the maintained package and describe
  what this project did while it was needed.

### Other

- Bug fixes and improvements.

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
