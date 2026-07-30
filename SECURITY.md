# Security

## Reporting a vulnerability

If you find a security issue in latitude-fingerprint, please report it privately
rather than opening a public issue. Use GitHub's security advisory form on the
repository, or email daniel@themalwarefiles.com. Please allow time for an
assessment and a fix before any public disclosure.

## Supported versions

Security fixes target the latest released version.

## Scope

latitude-fingerprint installs a proprietary driver that Canonical builds and
hosts. Vulnerabilities in that driver itself are for Broadcom and Canonical to
fix. This project's surface is the installer: how it fetches the driver,
verifies it, and places it on the system. The installer checks the download
against a pinned SHA256 before installing anything, and refuses to proceed on a
mismatch.

Two details worth stating plainly, because they are the first things a reviewer
should want to know:

- **Integrity comes from the pinned hash, not from the transport.** Canonical's
  archive currently times out over https, so the installer tries https and falls
  back to plain http. Bytes that arrive with the wrong hash are refused whichever
  way they came.
- **A hash mismatch is never treated as a reason to try elsewhere.** It stops the
  install. Only an outright download failure moves to the second source described
  in [docs/LICENSING.md](docs/LICENSING.md).
