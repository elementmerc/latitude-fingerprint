# Licensing

This project ships two kinds of thing under two different licences. Keeping
them separate is what lets the project stay open source while the hardware
driver itself is closed.

## What we license, and how

| Part | What it is | Licence |
|---|---|---|
| This project | Install scripts, Debian packaging metadata, docs, write-ups | AGPL-3.0-or-later |
| The Broadcom driver | The `.so` plugin, its firmware blobs, and `key.pem` | Proprietary; shipped by Canonical, owned by Broadcom |

We never bundle, mirror, or redistribute the proprietary driver. Our packaging
fetches it on the user's own machine, at install time, and verifies it against a
pinned SHA256. The binary only ever travels from its owner to the end user. It
never passes through us, the PPA, or the GitHub Releases mirror.

There are two places it can come from, and they are not interchangeable:

| Source | When it is used | Whose terms you accept |
|---|---|---|
| Canonical's archive (`dell.archive.canonical.com`) | The default, and whenever `--source oem` is given | Broadcom's, via the build Canonical packages and ships |
| Broadcom's own download (`packages.broadcom.com`) | When Canonical's copy cannot be downloaded, or whenever `--source upstream` is given | Broadcom's, accepted directly from Broadcom |

Both carry the same driver version, `5.15.285-5.15.010.0`, and each has its own
pinned SHA256 in `SHA256SUMS`. They are not the same bytes: Canonical rebuilds
and repackages the driver, and that Canonical build is the one this project has
tested on real hardware. The fallback exists so that a moved or withdrawn file
does not leave you with a fingerprint reader that cannot work at all. When it is
used, the installer says so on screen rather than quietly swapping one build for
another.

## Why this is allowed

Two separate questions hide behind that heading, and they have different answers
from different people. The first is whether our own freely licensed packaging is
dragged under the proprietary licence, or the blob under ours, by sitting next to
each other. The second is whether Broadcom permits what actually happens. Both
are answered below. Neither is legal advice: this is the reasoning the project
works from, and a solicitor's reading would govern over ours.

### Our licence, and theirs (mere aggregation)

Think of it like a recipe that tells you which tin to buy and how to open it.
The recipe is ours and is freely licensed. The tin is the shop's, sealed, and
we never open it for you or hand you a copy. We only tell you where to get it
and how to fit it.

In licence terms this is "mere aggregation": our freely licensed packaging sits
alongside the proprietary blob without combining into one derived work. The
blob is loaded at runtime by libfprint through its stable plugin interface, the
same way a browser loads an extension. Our scripts orchestrate the fetch; they
do not link against, modify, or contain the blob.

Other distributions package this driver the same way: the AUR `PKGBUILD`, a
Fedora spec and a Gentoo ebuild each ship a freely licensed recipe that fetches
the vendor binary on the user's own machine. Checked 2026-07-30. We followed that
precedent deliberately, though we have not re-verified those three since.

## What this means for you

- **Installing:** you fetch the proprietary driver yourself (our script does it
  for you, on your machine, from whichever of the two sources above is reachable).
  You accept Broadcom's licence by using it, exactly as you would installing it
  from Canonical directly.
- **Redistributing our work:** the scripts, packaging, and docs are
  AGPL-3.0-or-later. You may share and modify them under those terms.
- **Redistributing the driver:** that is governed solely by Broadcom's licence,
  not ours. For the record, that licence does permit it, complete and unmodified,
  with a copy of the agreement alongside and for use with the Broadcom hardware
  the driver was written for. This project simply does not take those conditions
  on: we never redistribute it, and our tools never do it for you.
- **Worth knowing before you install:** the agreement forbids attempts to modify,
  reverse engineer, decompile or disassemble the driver, and provides for
  automatic termination if you breach it. It also carries export restrictions.
  The condition about Broadcom's own silicon attaches to *distributing* the
  driver, not to using it. The full terms are installed on your machine alongside
  the driver, at `/usr/share/doc/libfprint-2-tod1-broadcom/copyright`; read those
  rather than this summary if it matters to you.

## Provenance

Every fetch is pinned to a known URL and verified against a recorded SHA256
(see `SOURCES`). Nothing unverified is ever installed: if the bytes do not match
the pinned hash, the install stops there and does not try anywhere else, because
a mismatch is a tampering or corruption signal rather than a reason to shop
around. Being unable to download is the different case, and the only one that
moves to the second source above.

The transport is not the guarantee. Canonical's host currently times out over
https, so the installer tries https first and falls back to plain http; the
pinned hash is what makes that safe, and a file that arrives over http with the
wrong hash is refused exactly like any other.
