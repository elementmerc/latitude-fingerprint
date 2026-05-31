# Licensing

This project ships two kinds of thing under two different licences. Keeping
them separate is what lets the project stay open source while the hardware
driver itself is closed.

## What we license, and how

| Part | What it is | Licence |
|---|---|---|
| This project | Install scripts, Debian packaging metadata, docs, write-ups | AGPL-3.0-or-later |
| The Broadcom driver | The `.so` plugin, its firmware blobs, and the PSK file | Proprietary ("Broadcom-tod"); shipped by Canonical, owned by Broadcom |

We never bundle, mirror, or redistribute the proprietary driver. Our packaging
fetches it from Canonical's archive (`dell.archive.canonical.com`) on the user's
own machine, at install time, and verifies it against a pinned SHA256. The
binary only ever travels from Canonical to the end user. It never passes
through us, the PPA, or the GitHub Releases mirror.

## Why this is allowed (mere aggregation)

Think of it like a recipe that tells you which tin to buy and how to open it.
The recipe is ours and is freely licensed. The tin is the shop's, sealed, and
we never open it for you or hand you a copy. We only tell you where to get it
and how to fit it.

In licence terms this is "mere aggregation": our freely licensed packaging sits
alongside the proprietary blob without combining into one derived work. The
blob is loaded at runtime by libfprint through its stable plugin interface, the
same way a browser loads an extension. Our scripts orchestrate the fetch; they
do not link against, modify, or contain the blob.

This is the established pattern. The AUR `PKGBUILD`, the Fedora spec, and the
Gentoo ebuild for the same driver all do exactly this: ship a freely licensed
recipe that downloads the vendor binary on the user's machine. We follow that
precedent deliberately.

## What this means for you

- **Installing:** you fetch the proprietary driver yourself (our script does it
  for you, on your machine, from Canonical). You accept Broadcom's licence by
  using it, exactly as you would installing it from Canonical directly.
- **Redistributing our work:** the scripts, packaging, and docs are
  AGPL-3.0-or-later. You may share and modify them under those terms.
- **Redistributing the driver:** that is governed solely by Broadcom's
  licence, not ours. We take no position beyond "we never do it, and our tools
  never do it for you".

## Provenance

Every fetch is pinned to a known URL and verified against a recorded SHA256
(see `shape-a/SOURCES`). If Canonical moves or removes the file, the fetch
fails loudly rather than installing something unverified. A documented list of
user-fetched fallback mirrors is tracked as deferred work.
