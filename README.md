# latitude-fingerprint

Fingerprint login for Dell Latitude and Precision laptops on Ubuntu 24.04 and
26.04 LTS.

Dell's Broadcom fingerprint sensor (ControlVault 3, USB `0a5c:5843`) has a
working Linux driver, but Canonical only ships it for Ubuntu 22.04. This puts it
on the current LTS releases.

## Install

```sh
git clone https://github.com/elementmerc/latitude-fingerprint
cd latitude-fingerprint
sudo ./install.sh
fprintd-enroll "$USER"     # touch the sensor a few times
fprintd-verify
```

The first install updates the sensor's firmware, which makes it reset on the USB
bus. If that first `fprintd-enroll` reports "No such device", reboot once and run
it again; it will not re-flash, and enrolment then works normally.

To unlock with your finger at login and for `sudo`, enable the PAM module:

```sh
sudo pam-auth-update        # tick "Fingerprint authentication"
```

## How it works

The driver is a closed plugin that Canonical builds for Broadcom. This project
never ships it: `install.sh` downloads it from Canonical, checks it against a
pinned SHA256, and installs it. That is the same approach the Arch, Fedora, and
Gentoo packages use. Details in [docs/LICENSING.md](docs/LICENSING.md).

## Uninstall

```sh
sudo ./uninstall.sh
```

Your enrolled fingerprints are kept.

## Licence

AGPL-3.0-or-later for this project's scripts and docs (see [LICENSE](LICENSE)).
The Broadcom driver keeps its own proprietary licence and is never bundled here.
