#!/usr/bin/env bash
set -Eeuo pipefail

# Prepare an Omarchy/Arch host for kholia/OSX-KVM.
# Run as the normal desktop user so omarchy pkg add can use sudo normally.
# This does not download macOS, create a VM disk, or bind the single GPU at boot.

readonly REPO_DIR=${OSX_KVM_REPO:-"$HOME/OSX-KVM"}
readonly TARGET_USER=${SUDO_USER:-$(id -un)}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[[ ${EUID} -ne 0 ]] || die "run this as your desktop user, not with sudo: $0"
[[ -d "$REPO_DIR/.git" ]] || die "repository not found at $REPO_DIR"
command -v omarchy >/dev/null || die "omarchy command not found"
command -v sudo >/dev/null || die "sudo is required"

# Current Arch names. qemu-desktop provides qemu-system-x86_64 and qemu-img.
# 7zip/cdrtools replace older README package names such as p7zip/genisoimage.
readonly packages=(
  qemu-desktop
  libvirt
  virt-manager
  edk2-ovmf
  swtpm
  dnsmasq
  libguestfs
  acl
  7zip
  cdrtools
  net-tools
  screen
)

printf 'Installing OSX-KVM host packages...\n'
omarchy pkg add "${packages[@]}"

printf 'Installing the repository KVM settings...\n'
sudo install -D -m 0644 "$REPO_DIR/kvm.conf" /etc/modprobe.d/osx-kvm.conf
sudo install -D -m 0644 "$REPO_DIR/vfio-kvm.rules" /etc/udev/rules.d/70-osx-kvm-vfio.rules
sudo udevadm control --reload-rules

printf 'Enabling libvirt...\n'
sudo systemctl enable --now libvirtd.service

printf 'Loading Intel KVM and enabling ignored MSR handling...\n'
sudo modprobe kvm_intel
if [[ -e /sys/module/kvm/parameters/ignore_msrs ]]; then
  printf '1\n' | sudo tee /sys/module/kvm/parameters/ignore_msrs >/dev/null
fi

printf 'Adding %s to virtualization groups...\n' "$TARGET_USER"
sudo usermod -aG kvm "$TARGET_USER"
sudo usermod -aG libvirt "$TARGET_USER"
sudo usermod -aG input "$TARGET_USER"

printf '\nHost preparation complete.\n'
printf 'Repository: %s\n' "$REPO_DIR"
printf 'QEMU: '; qemu-system-x86_64 --version | head -n 1
printf 'KVM device: '; if [[ -e /dev/kvm ]]; then printf 'present\n'; else printf 'not visible yet\n'; fi
printf '\nLog out and back in so the new group membership takes effect.\n'
printf 'Then choose a macOS version and run:\n'
printf '  cd %q\n' "$REPO_DIR"
printf '  ./fetch-macOS-v2.py\n'
printf '  qemu-img create -f qcow2 mac_hdd_ng.img 256G\n'
printf '  ./OpenCore-Boot.sh\n'
printf '\nDo the initial installation without GPU passthrough. The physical GPU can be assigned later after macOS is installed.\n'
printf 'After macOS is installed, configure the automated libvirt handoff with:\n'
printf '  install-osx-kvm-libvirt\n'
