# latitude-fingerprint

> **This project is finished. Use
> [`ppa:medicalwei/dell-cv3-cv3plus`](https://launchpad.net/~medicalwei/+archive/ubuntu/dell-cv3-cv3plus)
> instead.**
>
> It is maintained by the Canonical engineer who packages this driver, and since
> 7 July 2026 it covers 24.04 and 26.04 with driver 5.15.377, which is newer than
> the 5.15.285 this project installs. Tested on a Latitude 7420 running 26.04 on
> 31 July 2026: it installed over a hand-laid copy of this project's files
> without conflict, updated the sensor firmware, and the existing enrolment still
> verified.
>
> ```sh
> sudo add-apt-repository ppa:medicalwei/dell-cv3-cv3plus
> sudo apt update
> sudo apt install libfprint-2-tod1-broadcom
> ```
>
> This repository stays up for reference and will be archived. Everything below
> describes what it did while it was needed.

Fingerprint login for Dell Latitude and Precision laptops on Ubuntu 24.04 and
26.04 LTS.

Dell's Broadcom fingerprint sensor (ControlVault 3, USB `0a5c:5843`) has a
working Linux driver, but Canonical packages it only for the 22.04 OEM channel.
There is no copy in the normal Ubuntu archive for any release, so on a current
LTS you cannot simply `apt install` it. This project makes it a one-command
install on 24.04 and 26.04.

## First, check this is for your laptop

```sh
lsusb | grep 0a5c:5843
```

If that prints nothing, your laptop has a different fingerprint reader and this
project will not help. Dell fits several, and the others need different drivers.

## Install

```sh
sudo add-apt-repository ppa:elementmerc/latitude-fingerprint
sudo apt update
sudo apt install libfprint-2-tod1-broadcom-installer
```

Then enrol a finger and check it works:

```sh
fprintd-enroll "$USER"     # touch the sensor a few times
fprintd-verify
```

Expect this on a new machine: the first install updates the sensor's firmware, so
it resets on the USB bus and that first `fprintd-enroll` often reports "No such
device". Reboot once and run it again. It will not re-flash, and enrolment then
works normally.

If you would rather not add a PPA, run the script straight from a clone:

```sh
git clone https://github.com/elementmerc/latitude-fingerprint
cd latitude-fingerprint
sudo ./install.sh
```

Both routes install the same driver. The apt route also pulls in the fingerprint
packages you need; with the script, make sure `fprintd` and `libpam-fprintd` are
installed too, or there will be nothing to enrol a finger with.

Prebuilt packages are on the
[Releases page](https://github.com/elementmerc/latitude-fingerprint/releases)
as well. They are built for Ubuntu and depend on `libfprint-2-tod1`, which is
Canonical's patched libfprint, so they are not expected to install on Debian.
Linux Mint is Ubuntu-based and can add the PPA in the normal way.

To unlock with your finger at login and for `sudo`, enable the PAM module:

```sh
sudo pam-auth-update        # tick "Fingerprint authentication"
```

## How it works

The driver is a closed plugin that Canonical builds for Broadcom. This project
never ships it. `install.sh` downloads it, checks it against a pinned SHA256, and
installs it, from one of two places: Canonical's archive by default, or
Broadcom's own download if Canonical's copy cannot be reached. The two are the
same driver version built separately, and the installer says on screen which one
it used. That is the same approach the Arch, Fedora, and Gentoo packages use.
Details in [docs/LICENSING.md](docs/LICENSING.md).

One change is not reversible: the first install updates the firmware inside the
sensor itself. Uninstalling does not undo that.

## Uninstall

```sh
sudo apt remove libfprint-2-tod1-broadcom-installer     # if you used the PPA
sudo ./uninstall.sh                                     # if you used the script
```

Either way the driver this project installed comes back out and anything it
displaced is put back.

If a different driver is in place by then, because you have already installed
the maintained package above, removal says so and leaves it alone rather than
deleting somebody else's file. That is the normal thing to see if you switched
over first, and it is not an error.

Three things stay behind. Your enrolled fingerprints are kept, under
`/var/lib/fprint/<your username>/`; delete them with
`fprintd-delete "$USER"` if you want them gone. Copies of anything the install
displaced are kept under `/var/backups/latitude-fingerprint/`, and
`sudo apt purge` tells you where they are instead of deleting them for you. And
the sensor firmware stays at the version the first install flashed, which cannot
be reverted.

If you turned on fingerprint login, turn it off again:

```sh
sudo pam-auth-update        # untick "Fingerprint authentication"
```

Leaving it ticked means login and `sudo` wait for a sensor that no longer
works.

## Background

Yao Wei, a Canonical engineer, has been packaging this driver since February
2025, tracked in
[Launchpad bug #2099655](https://bugs.launchpad.net/ubuntu/+bug/2099655), with
builds in `ppa:medicalwei/dell-cv3-cv3plus`.

When this project started, that PPA had no ControlVault 3 build for 26.04, which
is the gap it was written to fill. **That gap closed on 7 July 2026**, when
builds of driver 5.15.377 were published for 22.04, 24.04 and 26.04. His build
is newer than the 5.15.285 this project pins, so there is no longer a reason to
use this one. That is why the project is finished.

One part is still unfinished, and it is the part that would help everyone: the
package is in a PPA, not in the Ubuntu archive. Checked on 31 July 2026, the
primary archive has no `libfprint-2-tod1-broadcom` for noble, plucky, questing
or resolute. Anyone able to help with archive inclusion would be doing the
useful work here.

The two packages cannot be installed together, and they use the same paths. If
you still have this one, `sudo apt remove libfprint-2-tod1-broadcom-installer`
first, then install his.

## Licence

AGPL-3.0-or-later for this project's scripts and docs (see [LICENSE](LICENSE)).
The Broadcom driver keeps its own proprietary licence and is never bundled here.
