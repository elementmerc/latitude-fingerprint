# Contributing to fingerprint-driver

Thanks for your interest. At the moment fingerprint-driver is a solo
project and **external contributions are not being accepted**. This
keeps the codebase small, the review quality high, and the release
cadence tight during the early milestones.

## What is welcome

- **Bug reports.** Open an issue with a clear reproduction, the version
  you are on, and your platform.
- **Security disclosures.** See [SECURITY.md](SECURITY.md) for the
  responsible disclosure process. Please do not open public issues for
  security bugs.
- **Feature requests and ideas.** Open an issue labelled "discussion".

## What is not accepted right now

- Pull requests for code, documentation, or translation changes.
- Drive-by patches.
- Refactor proposals.

When external contributions do open, guidance will be published here
and announced in the release notes. Until then, any PR will be closed
with a pointer to this file.

## Local CI preflight (when contributions open)

Before opening any PR, run the local equivalents of what CI runs:

```bash
# Project-specific commands — replace with the actual gates.
{{PREFLIGHT_COMMANDS}}
```

A `scripts/preflight.sh` runner wraps these and optionally replays the
full Linux CI matrix locally via [nektos/act](https://github.com/nektos/act).

## Licence

fingerprint-driver is **{{LICENCE_DESCRIPTION}}**. See [LICENSE](LICENSE)
and (if dual-licensed) [COMMERCIAL.md](COMMERCIAL.md).

Contributions are accepted under the AGPL-3.0-or-later licence of the project.
By submitting a contribution you confirm you have the right to license
your contribution to fingerprint-driver under those terms, and that we may
relicense the combined work under future versions of the licence or
under any commercial-licence arrangement offered alongside.

Contact: `daniel@themalwarefiles.com`
