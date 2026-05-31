# latitude-fingerprint

Fingerprint login for Dell Latitude and Precision laptops on Ubuntu 24.04 and
26.04 LTS.

Dell's Broadcom fingerprint sensor (ControlVault 3, USB `0a5c:5843`) has a
working Linux driver, but Canonical packages it only for the 22.04 OEM channel.
There is no copy in the normal Ubuntu archive for any release, so on a current
LTS you cannot simply `apt install` it. This project makes it a one command
install on 24.04 and 26.04.

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

## Background

Canonical has an in progress effort to package this driver, tracked in
[Launchpad bug #2099655](https://bugs.launchpad.net/ubuntu/+bug/2099655), with
builds in a personal PPA (`ppa:medicalwei/dell-cv3-cv3plus`) covering 22.04,
24.04, 25.04, and 25.10. That work has been quiet since early 2025 and has not
reached the Ubuntu archive, and it does not cover 26.04. This project is an
independent, maintained alternative: tested on real hardware, covering both
current LTS releases, and built so it never redistributes the proprietary
driver. If those packages reach the Ubuntu archive, that becomes the natural
home; until then, this covers current LTS users.

## Licence

AGPL-3.0-or-later for this project's scripts and docs (see [LICENSE](LICENSE)).
The Broadcom driver keeps its own proprietary licence and is never bundled here.
