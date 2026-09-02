#!/usr/bin/env bash
set -Eeuo pipefail

# Define the macOS VM in system libvirt and install its lifecycle hooks.
# This script does not start the VM, detach the GPU, stop SDDM, or reboot.

readonly REPO_DIR=${OSX_KVM_REPO:-"$HOME/OSX-KVM"}
readonly XML_FILE="$REPO_DIR/libvirt-osx-kvm.xml"
readonly PREPARE_HOOK="$REPO_DIR/libvirt-osx-kvm-prepare-hook"
readonly RELEASE_HOOK="$REPO_DIR/libvirt-osx-kvm-release-hook"
readonly QEMU_HOOK_DISPATCHER="$REPO_DIR/libvirt-qemu-hook-dispatcher"
readonly DOMAIN_NAME=osx-kvm
readonly HOOK_DIR=/etc/libvirt/hooks/qemu.d
readonly QEMU_HOOK_PATH=/etc/libvirt/hooks/qemu
readonly PREPARE_HOOK_PATH="$HOOK_DIR/$DOMAIN_NAME/prepare/begin/10-osx-kvm-prepare"
readonly RELEASE_HOOK_PATH="$HOOK_DIR/$DOMAIN_NAME/release/end/10-osx-kvm-release"
readonly QEMU_CONFIG=/etc/libvirt/qemu.conf
TEMP_XML=
QEMU_UID=

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${TEMP_XML:-}" && -e "$TEMP_XML" ]]; then
    rm -f -- "$TEMP_XML"
  fi
}
trap cleanup EXIT

[[ ${EUID} -ne 0 ]] || die 'run this as your normal user; it invokes sudo'
[[ -d "$REPO_DIR/.git" ]] || die "repository not found at $REPO_DIR"
[[ -r "$XML_FILE" ]] || die "missing $XML_FILE"
[[ -x "$PREPARE_HOOK" ]] || die "missing executable $PREPARE_HOOK"
[[ -x "$RELEASE_HOOK" ]] || die "missing executable $RELEASE_HOOK"
[[ -x "$QEMU_HOOK_DISPATCHER" ]] || die "missing executable $QEMU_HOOK_DISPATCHER"
command -v sudo >/dev/null || die 'sudo is required'
command -v virsh >/dev/null || die 'libvirt/virsh is required'
command -v setfacl >/dev/null || die 'setfacl is required; install the Arch acl package first with: omarchy pkg add acl'

# Resolve the identity used by the system libvirt QEMU driver. Arch systems
# commonly use libvirt-qemu, while some installations use qemu instead.
configured_qemu_user=
if [[ -r "$QEMU_CONFIG" ]]; then
  configured_qemu_user=$(sed -nE \
    's/^[[:space:]]*user[[:space:]]*=[[:space:]]*["'"'"']([^"'"'"']+)["'"'"'][[:space:]]*$/\1/p' \
    "$QEMU_CONFIG" | head -n1)
fi
if [[ "$configured_qemu_user" =~ ^\+[0-9]+$ ]]; then
  QEMU_UID=${configured_qemu_user#+}
elif [[ -n "$configured_qemu_user" ]] && QEMU_UID=$(id -u "$configured_qemu_user" 2>/dev/null); then
  :
else
  for candidate in libvirt-qemu qemu; do
    if QEMU_UID=$(id -u "$candidate" 2>/dev/null); then
      break
    fi
  done
fi
[[ -n "$QEMU_UID" ]] || die 'could not determine the system libvirt QEMU user'

sudo -v

# Libvirt invokes /etc/libvirt/hooks/qemu. This dispatcher selects the
# per-domain operation/state scripts from qemu.d.
sudo install -d -m755 "$HOOK_DIR"
sudo install -Dm755 "$QEMU_HOOK_DISPATCHER" "$QEMU_HOOK_PATH"
sudo install -Dm755 "$PREPARE_HOOK" "$PREPARE_HOOK_PATH"
sudo install -Dm755 "$RELEASE_HOOK" "$RELEASE_HOOK_PATH"
# Remove the previous unsupported flat hook files, if present.
sudo rm -f -- "$HOOK_DIR/90-osx-kvm-prepare" "$HOOK_DIR/91-osx-kvm-release"

if sudo systemctl is-active --quiet libvirtd.service; then
  # libvirt reads qemu.d only when its daemon starts.
  sudo systemctl restart libvirtd.service
else
  sudo systemctl enable --now libvirtd.service
fi

sudo virsh -c qemu:///system net-info default >/dev/null 2>&1 ||
  die "libvirt network 'default' is not defined"
sudo virsh -c qemu:///system net-autostart default >/dev/null
if ! sudo virsh -c qemu:///system net-list --name | grep -Fxq default; then
  sudo virsh -c qemu:///system net-start default
fi

# System libvirt runs QEMU as qemu. Grant it only the traversal/read/write
# access needed for these existing VM files; no files are copied or removed.
sudo setfacl -m "u:$QEMU_UID:--x" "$HOME"
sudo setfacl -m "u:$QEMU_UID:r-x" "$REPO_DIR" "$REPO_DIR/OpenCore"
sudo setfacl -m "u:$QEMU_UID:r--" "$REPO_DIR/OVMF_CODE_4M.fd" \
  "$REPO_DIR/OpenCore/OpenCore.qcow2"
sudo setfacl -m "u:$QEMU_UID:rw-" "$REPO_DIR/OVMF_VARS-1920x1080.fd" \
  "$REPO_DIR/mac_hdd_ng.img"

sudo -u "#$QEMU_UID" -- test -r "$REPO_DIR/OVMF_CODE_4M.fd" ||
  die "libvirt QEMU UID $QEMU_UID cannot read OVMF_CODE_4M.fd"
sudo -u "#$QEMU_UID" -- test -r "$REPO_DIR/OpenCore/OpenCore.qcow2" ||
  die "libvirt QEMU UID $QEMU_UID cannot read OpenCore.qcow2"
sudo -u "#$QEMU_UID" -- test -r "$REPO_DIR/mac_hdd_ng.img" ||
  die "libvirt QEMU UID $QEMU_UID cannot read mac_hdd_ng.img"
sudo -u "#$QEMU_UID" -- test -w "$REPO_DIR/mac_hdd_ng.img" ||
  die "libvirt QEMU UID $QEMU_UID cannot write mac_hdd_ng.img"

# A first define gives libvirt a UUID. Preserve it when redefining the
# existing domain, otherwise libvirt interprets the XML as a second domain
# with the same name and rejects it. The source XML remains portable and is
# not modified.
existing_uuid=$(sudo virsh -c qemu:///system domuuid "$DOMAIN_NAME" 2>/dev/null || true)
if [[ -n "$existing_uuid" ]]; then
  existing_state=$(sudo virsh -c qemu:///system domstate "$DOMAIN_NAME" 2>/dev/null || true)
  [[ "$existing_state" == 'shut off' ]] ||
    die "domain $DOMAIN_NAME is not shut off; shut it down before updating its definition"
  TEMP_XML=$(mktemp)
  sed "/<name>${DOMAIN_NAME}<\/name>/a\\  <uuid>${existing_uuid}<\/uuid>" \
    "$XML_FILE" > "$TEMP_XML"
  sudo virsh -c qemu:///system define "$TEMP_XML"
else
  sudo virsh -c qemu:///system define "$XML_FILE"
fi

printf 'Defined libvirt domain: %s\n' "$DOMAIN_NAME"
printf 'It is not running. Its hooks will stop SDDM before handoff and restart it after shutdown.\n'
printf 'Start later with: start-osx-kvm-libvirt\n'
printf 'The physical RX 5600 output is the macOS display; Linux will be headless while it runs.\n'
