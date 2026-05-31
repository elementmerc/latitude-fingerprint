# latitude-fingerprint

**Status:** active, sprint 0, public from day one, AGPL-3.0-or-later

Make the Dell Latitude and Precision fingerprint sensor work on current Ubuntu.
Canonical already ships a working driver for the Broadcom BCM58200 ControlVault
3 sensor (USB ID `0a5c:5843`), but pins it to the 22.04 OEM apt pocket, so
`apt install` refuses it on 24.04 and 26.04. This project backports that same
driver so owners of newer Ubuntu can install it, and closes Launchpad bug
**#2099655**.

## Why this project exists

The libfprint TOD ABI (Touch On Demand: a plugin system that lets hardware
vendors ship closed drivers as `.so` files) has not changed since libfprint
1.90.1, and Canonical have said it will not. Broadcom's existing driver runs
unchanged on every Ubuntu release from 22.04 onward. The only reason
`apt install libfprint-2-tod1-broadcom` does not already work on 24.04 or 26.04
is that nobody cut a backport build. LP #2099655 has tracked that request for
over a year: open, needs packaging, no upload.

So the work is not protocol reverse engineering. It is a weekend of Debian
packaging plus a Launchpad PPA. The reverse-engineering route was considered
and rejected (see the research memos noted below).

## The two shapes

### Shape A: personal install

Fetch Canonical's deb, verify it against a pinned checksum, lay its four payload
trees into place, reload udev, restart `fprintd`, enrol a finger. Wrapped as
`install.sh` plus `SHA256SUMS` so a reimage survives. This is both the immediate
personal fix and the smoke test that the driver still works on the target
release before any packaging effort.

Lives under [`shape-a/`](shape-a/). Verified on hardware: enrol and verify
succeed on a Dell Latitude 7420 running Ubuntu 26.04 LTS.

### Shape B: public packaging and PPA

Backport the `debian/` packaging from the Launchpad upstream branch against the
two current LTSes, noble (24.04) and resolute (26.04). Build under `sbuild`,
host on `ppa:elementmerc/latitude-fingerprint`, mirror to GitHub Releases,
smoke-test on fresh VMs, and attach the result to LP #2099655. This is the
community deliverable; Shape A is the proof it works first.

Lives under [`shape-b/`](shape-b/).

## Project plan

See [`PLAN.md`](PLAN.md). It is written so an agent or the operator can execute
step by step. Background and the reasoning behind the packaging route live in
the dated research memos under `private/research/` (operator-local, gitignored).

## Licensing

- This project's code (install scripts, packaging metadata, write-ups):
  **AGPL-3.0-or-later**.
- The Broadcom driver itself: **proprietary** (the "Broadcom-tod" licence). We
  never bundle or redistribute it. Shape A fetches it from Canonical; Shape B
  ships only the wrapping packaging. End users fetch the driver themselves on
  install, the same way the AUR, Fedora, and Gentoo packages do. See
  [`docs/LICENSING.md`](docs/LICENSING.md).

## Working with this repo

Operator-private state lives under `private/` (gitignored): the decision queue,
the tech-debt ledger, the research memos, and the release-gate and retro notes.

## Maintainer

Daniel Iwugo, <daniel@themalwarefiles.com>
