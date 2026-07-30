# shape-b: the apt-installable package

This directory holds the Debian packaging for
`libfprint-2-tod1-broadcom-installer`, the package published to the PPA so the
driver can be installed with `apt` instead of running a script by hand.

## What the package does

The published `.deb` is tiny. It contains no driver, only the install scripts
from the repository root. When you install it, its post-install step downloads
the driver from Canonical's archive, checks it against the pinned SHA256, and
installs it. If Canonical's copy cannot be downloaded it falls back to
Broadcom's own download, pinned and checked the same way, and says on screen
that it did. If neither can be reached, the install fails and nothing is
changed. See `docs/LICENSING.md` for what each source means.

This is the same fetch-and-verify approach used by other packages that install
third-party files they are not allowed to redistribute, such as the Microsoft
core fonts package. The proprietary driver is never redistributed here.

```
apt install libfprint-2-tod1-broadcom-installer
        |
        v
  postinst runs install.sh
        |
        +--> download driver from Canonical
        +--> verify pinned SHA256   (mismatch or failure => install aborts)
        +--> lay driver, udev rule, firmware updater, firmware into the system
```

Removing the package (`apt remove`) runs `uninstall.sh`, which takes the driver
back out and restores anything that was backed up. Enrolled fingerprints are
left untouched.

## Layout

```
shape-b/
  debian/           packaging metadata (control, rules, changelog, maintainer scripts)
  build-source.sh   builds a source package for one suite
  README.md         this file
```

The install logic itself is not duplicated here. It lives once at the
repository root (`install.sh`, `uninstall.sh`, `SHA256SUMS`, `SOURCES`).
`build-source.sh` copies that single source of truth into the build tree at
build time, so the package and the standalone script can never drift apart.

## Building

```
./build-source.sh noble       # 24.04 LTS
./build-source.sh resolute    # 26.04 LTS
```

Each run produces an unsigned source package under `build/<suite>/`. Sign and
upload it with the two commands the script prints when it finishes.

## Supported suites

| Suite | Ubuntu release | Package version |
|---|---|---|
| noble | 24.04 LTS | `<release>~24.04.1` |
| resolute | 26.04 LTS | `<release>~26.04.1` |

`<release>` is the project's current release, which `build-source.sh` reads from
the newest CHANGELOG heading. It is not written down here, because a version
copied into prose goes stale the first time one ships.
