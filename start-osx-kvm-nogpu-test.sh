#!/usr/bin/env bash
set -Eeuo pipefail

# Start a diagnostic copy of osx-kvm with virtual VGA/VNC instead of every
# passthrough device.  This is not a usable macOS desktop; it exists solely
# to observe OVMF/OpenCore/verbose boot while Linux keeps the RX 5600.

readonly REPO_DIR=${OSX_KVM_REPO:-"$HOME/OSX-KVM"}
readonly SOURCE_XML="$REPO_DIR/libvirt-osx-kvm.xml"
readonly TRANSFORM="$REPO_DIR/libvirt-osx-kvm-nogpu.xsl"
readonly VARS_TEMPLATE="$REPO_DIR/OVMF_VARS.fd"
readonly NOGPU_VARS="$REPO_DIR/OVMF_VARS-nogpu.fd"
readonly PASSTHROUGH_DOMAIN=osx-kvm
readonly TEST_DOMAIN=osx-kvm-nogpu
TEMP_XML=

cleanup() {
  [[ -z "${TEMP_XML:-}" || ! -e "$TEMP_XML" ]] || rm -f -- "$TEMP_XML"
}
trap cleanup EXIT

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

ensure_default_network() {
  sudo virsh -c qemu:///system net-info default >/dev/null 2>&1 ||
    die "libvirt network 'default' is not defined; run install-osx-kvm-libvirt"

  sudo virsh -c qemu:///system net-autostart default >/dev/null
  if ! sudo virsh -c qemu:///system net-list --name | grep -Fxq default; then
    printf 'Starting libvirt default NAT network.\n'
    sudo virsh -c qemu:///system net-start default
  fi
}

[[ ${EUID} -ne 0 ]] || die 'run this as your normal user; it invokes sudo'
command -v xsltproc >/dev/null || die 'xsltproc is required'
command -v virt-xml-validate >/dev/null || die 'virt-xml-validate is required'
command -v gvncviewer >/dev/null || die 'gvncviewer is required'
[[ -r "$SOURCE_XML" && -r "$TRANSFORM" && -r "$VARS_TEMPLATE" ]] ||
  die 'missing no-GPU test files'

ensure_default_network

state=$(sudo virsh -c qemu:///system domstate "$PASSTHROUGH_DOMAIN" 2>/dev/null || true)
[[ "$state" == 'shut off' ]] ||
  die "$PASSTHROUGH_DOMAIN must be shut off before using its disk images"

TEMP_XML=$(mktemp)
# Create a separate, fresh firmware-variable store once. It preserves the
# normal VM's boot/display settings and gives OVMF a chance to pick VGA.
[[ -e "$NOGPU_VARS" ]] || cp --reflink=auto -- "$VARS_TEMPLATE" "$NOGPU_VARS"
xsltproc --stringparam nogpu_vars "$NOGPU_VARS" "$TRANSFORM" "$SOURCE_XML" > "$TEMP_XML"
virt-xml-validate "$TEMP_XML" domain >/dev/null

# A previously defined test domain has a libvirt-assigned UUID.  Preserve it
# on redefinition instead of treating the transformed XML as a second domain.
existing_uuid=$(sudo virsh -c qemu:///system domuuid "$TEST_DOMAIN" 2>/dev/null || true)
test_state=$(sudo virsh -c qemu:///system domstate "$TEST_DOMAIN" 2>/dev/null || true)
if [[ "$test_state" != 'running' ]]; then
  if [[ -n "$existing_uuid" ]]; then
    sed -i "/<name>${TEST_DOMAIN}<\\/name>/a\\  <uuid>${existing_uuid}<\\/uuid>" "$TEMP_XML"
  fi
  sudo virsh -c qemu:///system define "$TEMP_XML"
  sudo virsh -c qemu:///system start "$TEST_DOMAIN"
fi

for _ in {1..40}; do
  if ss -ltnH | grep -Eq '127\.0\.0\.1:5901|\[::1\]:5901'; then
    printf 'No-GPU diagnostic VM is running. Opening VNC display 1.\n'
    # gvncviewer expects a VNC display number, not a TCP port: display 1
    # corresponds to the VNC listener on TCP 5901.
    exec gvncviewer 127.0.0.1:1
  fi
  sleep 0.25
done

sudo virsh -c qemu:///system domstate "$TEST_DOMAIN" >&2 || true
die 'VNC listener 127.0.0.1:5901 did not appear; inspect /var/log/libvirt/qemu/osx-kvm-nogpu.log'
