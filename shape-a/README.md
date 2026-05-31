# Shape A: personal install

Get the Dell Latitude 7420 fingerprint sensor working on Ubuntu newer than
22.04 (tested on 26.04 LTS), in one command.

## What this is

Canonical already ships a working driver for the Broadcom BCM58200 ControlVault
3 sensor (USB ID `0a5c:5843`) as a libfprint TOD ("Touch On Demand") plugin. A
TOD plugin is a closed driver that slots into libfprint the way a cartridge
slots into a console. The catch: Canonical pins that package to the 22.04 OEM
apt pocket, so `apt install` refuses it on 24.04 and 26.04.

`install.sh` fetches that same package from Canonical's archive, checks it
against a pinned SHA256, and lays its files into the right places by hand. The
proprietary driver is never shipped by this project; you fetch it from
Canonical, the same way the AUR, Fedora, and Gentoo packages do (see
[../docs/LICENSING.md](../docs/LICENSING.md)).

## Prerequisites

- A Dell machine with the Broadcom `0a5c:5843` sensor (check with `lsusb`).
- Ubuntu (amd64), newer than 22.04.
- `python3-gi` installed (`sudo apt install python3-gi`). The installer warns if
  it is missing.

## Quick start

```sh
sudo ./install.sh          # fetch, verify, install
fprintd-enroll "$USER"     # touch the sensor five times
fprintd-verify             # confirm it recognises your finger
```

To log in and unlock with your finger, enable the PAM module:

```sh
sudo pam-auth-update       # tick "Fingerprint authentication"
```

If you already downloaded the deb, skip the fetch:

```sh
sudo ./install.sh --deb /path/to/libfprint-2-tod1-broadcom_*.deb
```

## What it installs

The installer lays four trees into the system, matching the deb exactly:

| What | Where |
|---|---|
| Driver plugin | `/usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/libfprint-2-tod-1-broadcom.so` |
| udev rule | `/usr/lib/udev/rules.d/60-libfprint-2-device-broadcom.rules` |
| Firmware updater | `/usr/libexec/libfprint-2-tod1-broadcom/update-fw.py` |
| Firmware | `/var/lib/fprint/fw/` |

It then reloads udev, restarts `fprintd`, and runs the firmware-settle step that
the deb runs on install. Anything it overwrites is backed up under
`/var/backups/latitude-fingerprint/`.

## Undo

```sh
sudo ./uninstall.sh        # remove the driver, restore any backup
```

Your enrolled fingerprints are kept (they live separately, under
`/var/lib/fprint/<user>/`).

## If it does not work

```sh
sudo journalctl -u fprintd -b      # daemon log for this boot
dmesg | tail                       # kernel/USB messages
```

**First install flashes the sensor firmware.** On a machine that has never run
this driver, the install upgrades the Citadel firmware on the sensor, which
makes it reset and re-enumerate on the USB bus several times. If the very first
`fprintd-enroll` reports `Open failed ... No such device`, that is the sensor
still settling after the flash. Reboot once and enrol again; the firmware is
already up to date, so it will not re-flash and enrolment works normally.

Other failures are usually a stale udev cache (re-run the installer, or reboot)
or the sensor not being visible in `lsusb`. The version pin is recorded in
[SOURCES](SOURCES); the checksum is in [SHA256SUMS](SHA256SUMS).

## Proof

<!-- Screenshot of a successful enrol and verify on Chronos goes here once the
     hardware gate (M2) is green. -->
_(success screenshot added after the hardware gate.)_
