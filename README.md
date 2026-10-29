# ni-daqmx-arch

Install National Instruments NI-DAQmx natively on Arch Linux and Arch-based
distributions (Omarchy, EndeavourOS, Manjaro, ...), on whatever kernel you run.

NI ships NI-DAQmx only for RHEL, openSUSE and Ubuntu LTS, and tests its kernel
modules against those distributions' kernels. This repackages NI's official,
signed Ubuntu 24.04 packages as pacman packages, and has DKMS (the system that
recompiles out-of-tree kernel modules) build NI's modules for every kernel you
have installed, again after every kernel update.

```
NI's apt repository (Ubuntu 24.04)           your Arch machine
----------------------------------           -----------------
142 signed .deb packages  ── download, ───►  ni-daqmx        (NI's files, pacman-owned)
pinned by SHA-256            repackage       ni-daqmx-arch   (helper command + hook)
                                                  │
                                             DKMS: 48 kernel modules, built per kernel
                                                  │
                                             nidaqmx (Python), C API, NI hardware
```

Verified on Omarchy with NI-DAQmx 26.5.0 (2026 Q3): all 48 modules build for
kernels 7.2.8 and 7.2.11, NI's core modules load on 7.2.8, NI's services run,
and the Python `nidaqmx` package talks to the driver. Acquisition with real hardware has not been tested
yet.

## Why this works

Almost all of NI's kernel code is closed: each module is a precompiled object
plus a little glue. Those objects never call the kernel directly. They go
through `nikal`, NI's kernel abstraction layer, which NI ships as plain C
source. So when a new kernel changes something, only `nikal.c` can break, and
the fix is a small patch to one open file. Kernel 7.x needed exactly one: it no
longer exports `strncpy`.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/klemengit/ni-daqmx-arch/main/install.sh | bash
```

It asks for your sudo password once, then runs unattended for about ten
minutes:

1. installs `base-devel`, `git`, `dkms` and the headers for every installed kernel;
2. clones this repository to `~/.local/share/ni-daqmx-arch`;
3. takes a snapper snapshot if snapper is installed, as a rollback point;
4. downloads NI's packages (~280 MB, cached in `~/.cache/ni-daqmx-arch`),
   checks them against the pinned SHA-256 sums, builds both packages and
   installs them;
5. starts NI's services and runs `ni-daqmx-arch doctor`.

Requires an x86_64 Arch-based system. By installing you accept NI's license
terms for NI-DAQmx (<https://www.ni.com/linux/>).

## Use

```bash
ni-daqmx-arch doctor     # is everything working?
ni-daqmx-arch test       # list NI devices through Python's nidaqmx
```

| Command | What it does |
|---|---|
| `doctor` | Checks each layer: kernel headers, module builds, loaded modules, `/dev/nipalk`, NI services, USB devices. Writes a full report to `~/ni-daqmx-report.txt`. |
| `test` | Lists the driver version and every NI device with its channels, using `nidaqmx` through `uv`. |
| `update` | Pulls this repository, rebuilds only the packages whose version changed, installs them in one transaction, restarts NI's services and runs `doctor`. Asks for sudo once. |
| `start` | Loads the kernel modules and starts NI's services without a reboot. |
| `build-modules` | Builds any NI modules still missing, for every installed kernel. |
| `rebuild` | Force-rebuilds all NI modules for the running kernel. |
| `mode native` / `mode vm` | Switches NI USB hardware between this machine and the [ni-daq-vm](https://github.com/klemengit/ni-daq-vm) virtual machine, if you also use that. |
| `uninstall` | Removes both packages and the state they created. |

Python code uses the standard `nidaqmx` package; nothing here changes its API.

## Kernel updates

Nothing to do. When pacman installs a new kernel, DKMS rebuilds the NI modules
for it, and a hook then checks the result. If a module fails to build, the
update prints a warning naming the kernel, and your other kernels keep working.
Run `ni-daqmx-arch doctor` after rebooting; the report contains the compiler
error.

## When something breaks

Run `ni-daqmx-arch doctor` and look at `~/ni-daqmx-report.txt`. It collects
the versions, DKMS state, failed build logs, service status and NI-related
kernel messages, which is everything needed to diagnose a problem. Attach it
to an issue.

A build failure after a kernel update almost always means `nikal.c` needs a
patch for a changed kernel interface. Patches live in `ni-daqmx/`. DKMS builds
them for every installed kernel, so a patch must not break older kernels: guard
interface changes with `#if LINUX_VERSION_CODE >= KERNEL_VERSION(...)`, as
`nikal.c` itself does.

## Repository layout

| Path | What it is |
|---|---|
| `install.sh` | The one-line installer. |
| `ni-daqmx/` | The driver package: PKGBUILD, the `nikal` patch, and the steps NI's Debian install scripts perform, redone for pacman (`ni-daqmx.install`, sysusers, tmpfiles). |
| `ni-daqmx-arch/` | The helper command and the pacman hook. A separate package, so changing it never rebuilds the kernel modules. |
| `tools/update-sources` | Pins an NI release into `ni-daqmx/PKGBUILD`. |
| `keys/` | NI's public package-signing key. |

### Moving to a newer NI release

```bash
tools/update-sources 2027/Q1
```

This downloads NI's signed package index for that release, verifies it with
NI's key, works out every package `ni-daqmx` needs, and rewrites the pinned
list and checksums in `ni-daqmx/PKGBUILD`. Bump `pkgrel`, commit, and run
`ni-daqmx-arch update`.

## How it differs from NI's Ubuntu install

- **Same files.** The packages are NI's, unpacked unchanged, except for these
  differences:
- **`nikal` is patched** so it builds on current kernels.
- **Module build order is fixed.** Arch's DKMS hook checks only the first
  entry of a module's `BUILD_DEPENDS` list, so NI's modules would be built
  before their dependencies. The PKGBUILD reorders those lists into a single
  build sequence.
- **NI's Debian install scripts are replaced** by `ni-daqmx.install`, which
  performs the steps that matter: object-broker registrations, the CA bundle
  link, and enabling NI's services. NI's originals are kept in
  `/usr/share/ni-daqmx-arch/debian/` for reference.
- **NI's `sudoers.d` entry is left out.** It gives NI Linux RT's `webserv`
  user passwordless root for a firmware updater.

Not affiliated with or endorsed by National Instruments. NI-DAQmx is NI's
software under NI's license; this repository contains none of it.

## AI disclosure

Most of the code and documentation in this repository was written with an AI
coding assistant, under the author's direction. The author ran and
checked each step on their own machine, but has not reviewed every line. The
installer loads proprietary kernel modules as root, so read the scripts before
you run them, and use it at your own risk.

## License

MIT for the files in this repository; see [LICENSE](LICENSE) for the parts it
does not cover.
