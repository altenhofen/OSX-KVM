#!/usr/bin/env bash
set -Eeuo pipefail

# Read-only OSX-KVM preflight. It does not start QEMU or touch PCI devices.

readonly REPO_DIR=${OSX_KVM_REPO:-"$HOME/OSX-KVM"}

printf '%s\n' 'Host resources:'
free -h
lscpu | grep -E 'Model name|CPU\(s\):|Thread\(s\) per core|Core\(s\) per socket|Socket\(s\):' || true

printf '\n%s\n' 'KVM/QEMU:'
printf '  /dev/kvm: '; [[ -e /dev/kvm ]] && printf 'present\n' || printf 'missing\n'
qemu-system-x86_64 --version 2>/dev/null | head -n 1 || true

printf '\n%s\n' 'OSX-KVM files:'
for file in OpenCore/OpenCore.qcow2 BaseSystem.dmg BaseSystem.img mac_hdd_ng.img; do
  if [[ -e "$REPO_DIR/$file" ]]; then
    ls -lh "$REPO_DIR/$file"
  else
    printf '  missing: %s\n' "$REPO_DIR/$file"
  fi
done

printf '\n%s\n' 'GPU ownership (read-only):'
for bdf in 0000:09:00.0 0000:09:00.1; do
  driver=$(readlink -f "/sys/bus/pci/devices/$bdf/driver" 2>/dev/null || true)
  driver_name=${driver##*/}
  [[ -n "$driver_name" ]] || driver_name=unbound
  printf '  %s: %s\n' "$bdf" "$driver_name"
done

printf '\nRecommended launcher: start-osx-kvm-libvirt\n'
