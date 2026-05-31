# Plan — sprint 0: Shape A done + Shape B PPA live + LP bug closed

**Status:** active · sprint 0 · public from day 1 · AGPL-3.0-or-later
**Target window:** ~48 operator hours total, split across one weekend.
**Budget:** within 1 week elapsed time including PPA build-queue waits, LP bug
attachment, and the community write-up.

This is the executable brief to take the project from a freshly-scaffolded
repo to a public deliverable that closes Launchpad bug #2099655. Read the dated
research memos in `private/research/` (operator-local, gitignored:
`2026-05-23-idea.md` and `2026-05-23-research.md`) before starting:
they hold the *why*. This file is the *what + how + in which order*, written to
the engineering baseline in [`CLAUDE.md`](CLAUDE.md) (§3 planning discipline,
§4 review framework, §17 decision format).

Releases carry an annotated git v-tag with a codename (§22). The first tag is
cut only after the Sprint 0 hardware gate is green; the operator supplies the
codename at tag time.

## Operating principles

Before any code lands:

1. **Shape A must be verified working on Chronos (the operator's Latitude
   7420) before any Shape B work begins.** If the blob does not actually run on
   26.04, the whole project pivots; there is no point packaging a deb nobody
   can use. Run the install script, enrol a finger, `fprintd-verify`,
   screenshot the success. Only then start Shape B.
2. **Never bundle the proprietary blob.** Shape A's install script downloads
   from `dell.archive.canonical.com`. Shape B's PPA and GitHub mirror ship only
   the wrapping packaging metadata; users fetch the blob themselves on install.
   Same pattern as AUR, Fedora, and Gentoo. The aggregation stance is recorded
   in [`docs/LICENSING.md`](docs/LICENSING.md).
3. **Every shell script carries an SPDX header.** First 10 lines include
   `SPDX-License-Identifier: AGPL-3.0-or-later`; the CI `licence-check.yml` job
   fails the build without it.
4. **British English everywhere** (§14, hook-enforced via `BRE_ENABLED=1`).
   Prose stays clear of the em-dash habit (§19) and the LLM tells (§21) in any
   public doc.
5. **Commit hygiene** (§8): one commit per atomic change, why-not-what
   messages, no co-author or AI-attribution trailers (the `commit-msg` hook
   rejects them; author messages with `git commit -F /tmp/msg.txt`). Work lands
   on `dev` and reaches `main` by PR; the `pre-push` hook blocks direct pushes
   to `main`.

## Loophole hunt (§3.1)

Each loophole pairs with an explicit fix.

| ID | Loophole | Fix |
|---|---|---|
| L-1 | The blob URL or filename on `dell.archive.canonical.com` drifts (new point release, re-pooled path). | The fetch reads the directory listing and verifies size + SHA256 against a pinned value rather than hardcoding one filename. Fail loud with the listing URL on mismatch. |
| L-2 | The `~22.04~oem1` blob's libssl and dependency assumptions on 26.04 are unproven until `fprintd-verify` passes. Chronos runs 26.04 with libfprint `1.95.1+tod1` and fprintd `1.94.5`, a bigger ABI jump from the 22.04-built blob than the original survey assumed. | This is exactly why Sprint 0 is the hard gate. Nothing in Shape B starts until the gate is green on real hardware. |
| L-3 | The Launchpad packaging-vs-upstream branch split could be restructured, blurring the "never redistribute the blob" guarantee. | Re-verify the branch layout at clone time in Sprint 2 (checklist item). Vendor only the packaging branch; never the upstream blob branch. |
| L-4 | The PPA slug is load-bearing for discoverability and hard to rename after users copy `add-apt-repository` lines. | Lock `latitude-fingerprint` deliberately before Sprint 1.4. |
| L-5 | `install.sh` overwrites system files under `/usr`; a re-run or a bad blob could clobber a working state. | Back up any existing target files before overwrite (§3.7 data preservation); `uninstall.sh` restores them. The install is idempotent and re-run safe. |
| L-6 | Canonical pulls or moves the blob entirely, breaking every install. | Pin URL + SHA256 and fail loud now; a documented user-fetched fallback mirror list is tracked as a TD item. We never self-host the blob (licence). |

## Robustness per phase (§2, §3.2)

Shape A's `install.sh` and `uninstall.sh` must:

- `set -euo pipefail`; refuse to run on non-Ubuntu or non-x86_64 with a plain
  reason.
- Pre-flight before any change: disk space for the staging extract, network
  reachability to the archive, presence of `dpkg-deb`, `udevadm`, `systemctl`.
- Verify `SHA256SUMS` before extracting; refuse to proceed on mismatch.
- Install atomically: back up existing targets, copy, then reload udev and
  restart `fprintd`. Leave no `.part` or `.tmp` files behind.
- Be idempotent: a second run detects an already-correct install and is a
  no-op apart from a clear status line.
- Emit a diagnostic path on every failure (`journalctl -u fprintd -b`,
  `dmesg | tail`) so a user can self-serve or file a clean bug report.

## Remaining design dimensions (§3.3 to §3.8)

- **Quality bar.** Correct first (the gate proves it), then reproducible: two
  runs on the same blob produce the same installed state.
- **Scale-conscious.** This is packaging, not data-scale work, but the install
  path must work identically on any x86_64 Ubuntu host, not only Chronos. No
  host-specific assumptions baked into the script.
- **Cross-layer.** Each suite's `debian/changelog` version pins must match that
  release's actual `libfprint-2-2` and `fprintd` versions; confirm with
  `apt-cache policy` on a fresh container of each release.
- **Observability.** Each script logs entry, exit, and the step it is on.
- **Data preservation.** Covered by L-5: back up before overwrite, restore on
  uninstall.
- **Integration-first.** Shape A's `install.sh` is designed as the unit the
  `olympus` laptop-bring-up automation can reuse, not a standalone one-off.

## Sprint 0 — Shape A (one evening, ~3 hours including write-up)

Target: working fingerprint login on Chronos plus a reusable install script
committed to the repo.

| Step | Effort | Notes |
|---|---|---|
| 0.1 — Fetch the latest `5.15.x` deb from `dell.archive.canonical.com/updates/pool/public/libf/libfprint-2-tod1-broadcom/`. Latest known at survey: `libfprint-2-tod1-broadcom_5.15.285-5.15.010.0-0ubuntu2~22.04.1~oem1_amd64.deb`. | 5 min | `wget` or `curl -O`. Verify file size against the directory listing. Record the URL + SHA256 in `shape-a/SOURCES`. |
| 0.2 — Inspect with `dpkg-deb -c <deb>`. Confirm the FOUR functional trees (verified on 5.15.285): `usr/lib/x86_64-linux-gnu/libfprint-2/tod-1/libfprint-2-tod-1-broadcom.so`, `usr/lib/udev/rules.d/60-libfprint-2-device-broadcom.rules`, `usr/libexec/libfprint-2-tod1-broadcom/update-fw.py`, `var/lib/fprint/fw/` (firmware `.otp`/`.bin` + `key.pem`). | 5 min | The udev rule is `...-device-broadcom.rules` and the firmware lives under `var/lib/fprint/fw/`, not `usr/share/`. The deb's `postinst` runs `update-fw.py`. |
| 0.3 — Extract to staging: `dpkg-deb -x <deb> /tmp/bcm-fp/`. `file` the `.so` (expect ELF 64-bit LSB shared object x86-64). Firmware tree holds `.bin`/`.otp` blobs plus `key.pem`. | 5 min | Do not `dpkg -i`; 26.04's apt refuses the `~22.04~oem1` pin. |
| 0.4 — Build `shape-a/install.sh` (idempotent: steps 0.1 to 0.3 plus laying the four trees into `/`, `udevadm control --reload && udevadm trigger`, `systemctl restart fprintd`, then run `update-fw.py` to replicate the deb's postinst). SPDX header. Verify `SHA256SUMS` before extract. Back up existing targets. Ship a matching `shape-a/uninstall.sh`. | 60 to 90 min | `set -euo pipefail`. Refuse non-Ubuntu / non-x86_64. Diagnostic on every step. |
| 0.5 — Run `shape-a/install.sh` on Chronos. Then `fprintd-enroll $USER` (touch 5 times), `fprintd-list $USER`, `fprintd-verify`. On failure: `journalctl -u fprintd -b` + `dmesg | tail`. | 10 to 15 min | Most failures are stale udev (rerun reload) or libssl mismatch (should not fire on 5.14+). |
| 0.6 — Screenshot the successful enrolment + verify. Write `shape-a/README.md` with the recipe + screenshot. | 30 min | Operator-facing future-reference for a reimage; also seeds the blog post. |
| 0.7 — Commit Shape A. One commit: `shape-a: vendor + install script + SHA256SUMS + recipe`. | 5 min | Body explains why packaging-then-PPA beats the original RE plan. Cite LP #2099655. |

**Exit gate for Shape A:** `fprintd-verify` succeeds on Chronos. Screenshot in
`shape-a/README.md`. Operator unlocks GDM with their finger. A release-gate
sweep (§4) is written to `private/reviews/` and signed off. Nothing proceeds
until this gate is green.

## Sprint 1 — Shape B pre-conditions (operator-time, ~40 min total)

Operator-time blockers the agent cannot do. Pre-stage the `sbuild` schroots
here during slack so the build weekend is not eaten by first-time chroot setup.

| Step | Effort | Notes |
|---|---|---|
| 1.1 — Sign in at <https://launchpad.net/> under the `elementmerc` identity. Sign the Ubuntu Code of Conduct (required before uploading source packages). | 10 min | Without the signed CoC, Launchpad rejects the `dput` upload. |
| 1.2 — Register a GPG key. `gpg --full-generate-key` for `daniel@themalwarefiles.com` if none yet. Export public: `gpg --armor --export <keyid>`. Paste at `launchpad.net/~elementmerc/+editpgpkeys`. Complete the encrypted-email round-trip. The same key signs the annotated git v-tags (§13: one key for now; hardware-backing tracked as a TD item). | 10 min | The email confirmation is the slow gate (2 to 15 min). |
| 1.3 — Create the PPA at `launchpad.net/~elementmerc/+activate-ppa`. Name: **`latitude-fingerprint`** (descriptive over technical; users search "latitude 7420 fingerprint ubuntu", not "broadcom 0a5c:5843"). Description mentions LP #2099655 + the two target LTSes (24.04, 26.04). | 5 min | The slug becomes `ppa:elementmerc/latitude-fingerprint`. Locked per L-4. |
| 1.4 — Install tooling: `sudo apt install devscripts dput sbuild debmake`. Configure `~/.dput.cf` for the PPA. Run `mk-sbuild noble` and `mk-sbuild resolute` to pre-stage the schroots. | 20 min + chroot build time | `sbuild` is what Canonical use (Q-5); first-time schroot creation is the slow part, so do it here, not on the build weekend. |

**Exit gate for Sprint 1:** `dput ppa:elementmerc/latitude-fingerprint
test_1.0.dsc` from a throwaway hello-world source package uploads cleanly,
Launchpad builds it, and the binary appears in the PPA. This verifies the
credential chain end to end before the real upload.

## Sprint 2 — Shape B packaging (one weekend, ~16 to 20 hours)

Target: backported source packages for noble (24.04 LTS) and resolute
(26.04 LTS), uploaded to the PPA, building cleanly, installing cleanly on
each target, and mirrored to GitHub Releases.

| Step | Effort | Notes |
|---|---|---|
| 2.1 — `git clone https://git.launchpad.net/~oem-solutions-engineers/libfprint-2-tod1-broadcom`. Vendor the packaging branch (carries `debian/`) into `shape-b/upstream-packaging/` as a frozen baseline. Re-verify the branch split (L-3) before relying on it. | 15 min | The upstream blob branch is not redistributable by us; check it out for reference only. The packaging branch is redistributable. |
| 2.2 — Confirm the three schroots from Sprint 1.4 are present (`schroot -l`). Rebuild any that are missing. | 5 to 20 min | Pre-staging in Sprint 1 should make this a no-op. |
| 2.3 — For each suite (noble first, then resolute): copy `debian/` into `shape-b/<suite>/debian/`, bump `debian/changelog` (e.g. `libfprint-2-tod1-broadcom (5.15.285-5.15.010.0-0ubuntu2~24.04.1~elementmerc1) noble; urgency=medium`, and the `~26.04.1~elementmerc1) resolute` analogue), re-pin `Depends:` for that release's `libfprint-2-2` + `fprintd`. | 60 to 90 min per suite | `apt-cache policy libfprint-2-2 fprintd` on a fresh container of each release gives the current constraint. On 26.04 that is `libfprint-2-2 1:1.95.1+tod1` and `fprintd 1.94.5`. Document the pins in the changelog. |
| 2.4 — Build the source package: `cd shape-b/<suite> && dpkg-buildpackage -S -sa -k<keyid>`. Produces `.dsc` + `.tar.gz` + `.changes`. Inspect with `lintian -EvIL +pedantic`; fix findings that block upload. | 30 min per suite | Most lintian warnings are formatting; fix the blockers. |
| 2.5 — Local `sbuild` smoke build: `sbuild -d <suite> <name>_<ver>.dsc`. Confirms a clean-chroot build before consuming Launchpad's queue. | 15 to 30 min per suite | Catches missing build-depends before the round trip. |
| 2.6 — Upload: `dput ppa:elementmerc/latitude-fingerprint <name>_<ver>_source.changes`. Watch `launchpad.net/~elementmerc/+archive/ubuntu/latitude-fingerprint/+packages`. | 30 min per suite + queue (30 min to 4 h) | First-ever upload of a new package may sit longer. |
| 2.7 — Smoke-test the published PPA on a fresh VM of each target (`multipass launch <release>`): `add-apt-repository ppa:elementmerc/latitude-fingerprint && apt update && apt install libfprint-2-tod1-broadcom`. Verify the `.so` path, udev rule, and `fprintd` restart. Hardware-bound enrol only happens on Chronos. | 30 to 60 min per suite | Snapshot the VM after install for the LP screenshot. |
| 2.8 — Publish the built source packages to the GitHub Releases mirror (Q-4). Packaging only, never the blob. | 20 min | Widens reach to Debian/Mint users who cannot use a PPA; same user-fetched-blob model. |
| 2.9 — Attach to LP #2099655 (and #2099289 for context). Per bug: a specific comment ("tested on 7420 26.04, working enrol + verify, PPA at `ppa:elementmerc/latitude-fingerprint`, please consider for oem-archive upload"), the smoke-test screenshots, tag `confirmed`. | 30 min | Comment quality matters: be specific about what was tested and on what hardware. |
| 2.10 — Commit Sprint 2's outputs (one commit per suite + one for the LP write-up) and cut the first annotated git v-tag (operator supplies the codename, §22). | 30 min | Commits are the public artefact under AGPL; reviewers read them. |

**Exit gate for Sprint 2:** PPA has two published builds (noble + resolute),
each install-tested on a fresh VM, mirrored to GitHub Releases, and
attached to the LP bug with screenshots and a clear comment. A release-gate
sweep (§4) is written to `private/reviews/` and signed off before the tag.

## Sprint 3 — community write-up (one evening, ~2 to 3 hours)

Target: a ~1500-word write-up that closes the discoverability gap, so Latitude
and Precision owners searching "ubuntu 24.04 fingerprint dell" land here.

| Step | Effort | Notes |
|---|---|---|
| 3.1 — Draft a ~1500-word post. Structure: the problem (Dell sensor unsupported out of the box on 26.04), the solution (TOD plugin model + Canonical's blob locked in 22.04 OEM), the how (Shape A for personal, Shape B for the community PPA + mirror), the big idea (you do not have to write a driver from scratch when the plugin interface is already there). Plain prose, British English, no marketing fluff. Reference the LP bugs; link the PPA, the GitHub mirror, and the install recipe. | 2 to 3 h | Title candidate: *"How I fixed my Dell fingerprint sensor on Ubuntu, and how anyone can write their own partial computer drivers"*. |
| 3.2 — Publish to danieliwugo.com as canonical (Q-11); also commit the post under `docs/` so it survives independently and is reviewable under AGPL. Link it from the LP #2099655 comment as the bring-up reference. | 15 min | Cross-link from the post back to the LP bug, the PPA, and the mirror. |

**Exit gate for Sprint 3:** Post is published, committed under `docs/`, and
linked from the LP bug. Sprint retrospective (§4) written to
`private/reviews/`.

## Review framework (§4)

- **Release-gate sweep** at each sprint exit gate: a full pass across the four
  axes (integrity, general quality, security posture, extreme robustness) over
  the cumulative delta, written up with a sign-off line in `private/reviews/`.
  The tag does not land without it; a green CI run is necessary but not
  sufficient.
- **Retrospective** at each sprint close: short, captures what shipped, what
  slipped, what surprised, and what to fold into the next gate. Findings never
  block a release; they shape the next gate.
- **Finding handling.** Every gate finding is fixed in the same cycle unless it
  needs hardware, external coordination, or a full build, in which case it
  becomes a TD entry with a written reason and a concrete next step.

## Decisions

The live decision queue is `private/decisions.md` (Q-coded, §17 matrices). All
eleven are resolved. Load-bearing summary:

- **Q-1** release order: noble (24.04 LTS) then resolute (26.04 LTS). LOCKED
  2026-05-23, REVISED 2026-05-30 (see Q-12): Chronos runs 26.04, not 25.10;
  plucky 25.04 is EOL and questing 25.10 has months left, so the two supported
  LTSes are the targets.
- **Q-2** ship first, cross-PR to sibling distros after. LOCKED.
- **Q-3** CV3+ variant (LP #2099289): defer to stretch. LOCKED 2026-05-23.
- **Q-4** hosting: PPA + GitHub Releases mirror (packaging only). LOCKED.
- **Q-5** chroot builder: `sbuild` throughout. LOCKED.
- **Q-6** git-tag versioning: tooling semver from v0.1.0, first tag after the
  Sprint 0 gate, codename per §22. LOCKED.
- **Q-7** blob fetch: pin URL + SHA256, fail loud, documented fallback mirror
  list as a TD item, never self-host. LOCKED.
- **Q-8** repo name + home: `latitude-fingerprint`, GitHub canonical and
  public. LOCKED.
- **Q-9** signing key: one key for Sprint 0/1, hardware-backing as a TD item.
  LOCKED.
- **Q-10** licence: mere-aggregation stance, documented in `docs/LICENSING.md`.
  LOCKED.
- **Q-11** write-up hosting: danieliwugo.com canonical, also committed under
  `docs/`. LOCKED.

## Deferred work

Tracked in `private/tech-debt.md` (TD-coded):

- **TD-1** SRU request to get the package into the official Ubuntu archive
  (not just a PPA). Weeks-to-months, needs Ubuntu Developer sponsorship.
- **TD-2** CV3+ variant (`0a5c:5864-67`, LP #2099289). Same pattern, different
  hardware ID. Build on community request or when CV3+ hardware is acquired.
- **TD-3** Sibling-distro cross-PRs (AUR PKGBUILD, Fedora spec, Gentoo ebuild)
  adding a "you can also pull from the Ubuntu PPA" cross-reference.
- **TD-4** Documented user-fetched fallback mirror list for the blob (Q-7), for
  the day Canonical's archive URL moves.
- **TD-5** Hardware-backed signing key (Q-9) if this becomes a long-lived
  maintainer identity.
- **TD-6** Debian/Mint reach beyond the GitHub mirror (a proper `.deb` repo or
  packaging note) if non-Ubuntu users ask.

## What is specifically NOT in scope

Per the original idea spec: we are NOT writing a from-scratch native libfprint
driver. The sensor is a secure SoC running Citadel RTOS with code-signed
firmware over a TLS-PSK USB link; reverse engineering it is 8 to 16 weeks
full-time even with Talos's notes, and the output would still need the
Broadcom-signed firmware blob (so not 100% free software anyway). Skip the RE.
Ship the packaging.
