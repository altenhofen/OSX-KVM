#!/usr/bin/env bash
set -Eeuo pipefail

# Define the macOS VM in system libvirt and install its lifecycle hooks.
# This script does not start the VM, detach the GPU, stop SDDM, or reboot.

readonly REPO_DIR=${OSX_KVM_REPO:-"$HOME/OSX-KVM"}
readonly XML_FILE="$REPO_DIR/libvirt-osx-kvm.xml"
readonly PREPARE_HOOK="$REPO_DIR/libvirt-osx-kvm-prepare-hook"
readonly RELEASE_HOOK="$REPO_DIR/libvirt-osx-kvm-release-hook"
readonly DOMAIN_NAME=osx-kvm

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[[ ${EUID} -ne 0 ]] || die 'run this as your normal user; it invokes sudo'
[[ -d "$REPO_DIR/.git" ]] || die "repository not found at $REPO_DIR"
[[ -r "$XML_FILE" ]] || die "missing $XML_FILE"
[[ -x "$PREPARE_HOOK" ]] || die "missing executable $PREPARE_HOOK"
[[ -x "$RELEASE_HOOK" ]] || die "missing executable $RELEASE_HOOK"
command -v sudo >/dev/null || die 'sudo is required'
command -v virsh >/dev/null || die 'libvirt/virsh is required'
command -v setfacl >/dev/null || die 'setfacl is required; install the Arch acl package first with: omarchy pkg add acl'
getent passwd qemu >/dev/null || die 'the system libvirt qemu user is missing'

sudo -v
sudo systemctl enable --now libvirtd.service

# System libvirt runs QEMU as qemu. Grant it only the traversal/read/write
# access needed for these existing VM files; no files are copied or removed.
sudo setfacl -m u:qemu:--x "$HOME"
sudo setfacl -m u:qemu:r-x "$REPO_DIR" "$REPO_DIR/OpenCore"
sudo setfacl -m u:qemu:r-- "$REPO_DIR/OVMF_CODE_4M.fd" \
  "$REPO_DIR/OpenCore/OpenCore.qcow2"
sudo setfacl -m u:qemu:rw- "$REPO_DIR/OVMF_VARS-1920x1080.fd" \
  "$REPO_DIR/mac_hdd_ng.img"

sudo install -Dm755 "$PREPARE_HOOK" \
  /etc/libvirt/hooks/qemu.d/$DOMAIN_NAME/prepare/begin
sudo install -Dm755 "$RELEASE_HOOK" \
  /etc/libvirt/hooks/qemu.d/$DOMAIN_NAME/release/end
sudo virsh -c qemu:///system define "$XML_FILE"

printf 'Defined libvirt domain: %s\n' "$DOMAIN_NAME"
printf 'It is not running. Its hooks will stop SDDM before handoff and restart it after shutdown.\n'
printf 'Start later with: start-osx-kvm-libvirt\n'
printf 'The physical RX 5600 output is the macOS display; Linux will be headless while it runs.\n'
