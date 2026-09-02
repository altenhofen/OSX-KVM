#!/usr/bin/env bash
set -Eeuo pipefail

# Start the already-defined libvirt VM. Its libvirt hooks stop SDDM before
# libvirt detaches the RX 5600 and restart SDDM after the VM exits.

readonly DOMAIN_NAME=osx-kvm

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

[[ ${EUID} -ne 0 ]] || die 'run this as your normal user'
command -v virsh >/dev/null || die 'libvirt/virsh is required'
command -v pgrep >/dev/null || die 'procps/pgrep is required'

readonly QEMU_HOOK=/etc/libvirt/hooks/qemu
readonly PREPARE_HOOK=/etc/libvirt/hooks/qemu.d/osx-kvm/prepare/begin/10-osx-kvm-prepare
readonly RELEASE_HOOK=/etc/libvirt/hooks/qemu.d/osx-kvm/release/end/10-osx-kvm-release
[[ -x "$QEMU_HOOK" && -x "$PREPARE_HOOK" && -x "$RELEASE_HOOK" ]] ||
  die 'automatic lifecycle hooks are not installed; run install-osx-kvm-libvirt first'

graphical_session=0
if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
  graphical_session=1
fi
for proc in Hyprland sddm sddm-helper start-hyprland; do
  if pgrep -x "$proc" >/dev/null 2>&1; then
    graphical_session=1
    break
  fi
done

if [[ $graphical_session -eq 1 ]]; then
  printf 'Starting macOS will stop the Linux graphical session and make the host display headless.\n'
  read -r -p 'Continue? [y/N] ' answer
  [[ "$answer" =~ ^[Yy]$ ]] || exit 0

  ensure_default_network

  # Run the client outside the graphical user session. The terminal may be
  # killed when SDDM stops, but this system unit continues starting the VM.
  exec sudo systemd-run --unit="osx-kvm-start-$(date +%s)" --collect --no-block \
    /usr/bin/virsh -c qemu:///system start "$DOMAIN_NAME"
fi

ensure_default_network
exec sudo virsh -c qemu:///system start "$DOMAIN_NAME"
