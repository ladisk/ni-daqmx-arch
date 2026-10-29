#!/bin/bash
# Install NI-DAQmx on Arch Linux, with any kernel.
#
#   curl -fsSL https://raw.githubusercontent.com/klemengit/ni-daqmx-arch/main/install.sh | bash
#
# Set NI_DAQMX_ARCH_URL=/path/to/checkout to install from a local git repo instead of GitHub.

set -eEo pipefail

REPO_URL=${NI_DAQMX_ARCH_URL:-https://github.com/klemengit/ni-daqmx-arch.git}
REPO=${NI_DAQMX_ARCH_REPO:-$HOME/.local/share/ni-daqmx-arch}
VM_RULE=/etc/udev/rules.d/90-ni-daq-vm.rules

step() { printf '\n\e[1;34m==>\e[0m \e[1m%s\e[0m\n' "$*"; }
die()  { printf '\e[31mError:\e[0m %s\n' "$*" >&2; exit 1; }
trap 'die "install failed at line $LINENO. Run: ni-daqmx-arch doctor (if installed) or re-run this script."' ERR

[[ $EUID -ne 0 ]] || die "run as your normal user, not root (sudo is used where needed)"
command -v pacman >/dev/null || die "this installer is for Arch Linux and Arch-based distros"
[[ $(uname -m) == x86_64 ]] || die "NI-DAQmx only exists for x86_64"

# Ask for the sudo password once, then keep sudo's cached login fresh until this
# script exits: the DKMS module builds take longer than sudo's 5-minute timeout.
sudo_keepalive() {
  sudo -v || exit 1
  while sleep 60; do sudo -n true 2>/dev/null || exit; kill -0 $$ 2>/dev/null || exit; done &
  trap "kill $! 2>/dev/null" EXIT
}

step "Asking for your sudo password once (the rest runs unattended, ~10 minutes)"
sudo_keepalive

step "Installing build tools and kernel headers"
# DKMS needs the headers for every installed kernel, not just the running one.
headers=()
for vmlinuz in /usr/lib/modules/*/vmlinuz; do
  kpkg=$(pacman -Qqo "$vmlinuz" 2>/dev/null) || continue
  headers+=("$kpkg-headers")
done
sudo pacman -S --needed --noconfirm base-devel git dkms "${headers[@]}"

step "Fetching the installer into $REPO"
if [[ -d $REPO/.git ]]; then
  git -C "$REPO" pull --ff-only
else
  git clone "$REPO_URL" "$REPO"
fi

if command -v snapper >/dev/null; then
  step "Taking a snapper snapshot (rollback point, selectable from the boot menu)"
  sudo snapper -c root create -c number -d "before ni-daqmx-arch" || true
fi

step "Building and installing NI-DAQmx (downloads ~280 MB from ni.com, compiles 48 kernel modules)"
"$REPO/ni-daqmx-arch/ni-daqmx-arch" update || true   # update ends with doctor, which explains any failure

if [[ -f $VM_RULE ]]; then
  step "The ni-daq VM is set up to take NI USB devices"
  echo "Leaving that as is. To use the hardware natively: ni-daqmx-arch mode native"
fi
