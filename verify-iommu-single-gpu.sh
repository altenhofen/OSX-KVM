#!/usr/bin/env bash
set -Eeuo pipefail

command -v lspci >/dev/null || { printf 'error: install pciutils first\n' >&2; exit 1; }

printf '%s\n' 'Kernel command line:'
cat /proc/cmdline
printf '\n%s\n' 'IOMMU-related kernel messages:'
sudo journalctl -k -b --no-pager | grep -iE 'DMAR|IOMMU|VT-d|remapping' || true

mapfile -t display_bdfs < <(
  lspci -Dn | awk '$2 ~ /^030[02]:$/ { print $1 }'
)
if (( ${#display_bdfs[@]} != 1 )); then
  printf '\nerror: expected one display controller, found %s\n' "${#display_bdfs[@]}" >&2
  exit 1
fi

gpu_bdf=${display_bdfs[0]}
gpu_slot=${gpu_bdf%.*}
printf '\nGPU: %s\n' "$(lspci -s "$gpu_bdf" -nn)"

if ! grep -qw 'intel_iommu=on' /proc/cmdline; then
  printf '%s\n' 'FAIL: intel_iommu=on is missing from the running kernel command line.'
  exit 1
fi
if ! grep -qw 'iommu=pt' /proc/cmdline; then
  printf '%s\n' 'WARN: iommu=pt is missing from the running kernel command line.'
fi

group_link=/sys/bus/pci/devices/$gpu_bdf/iommu_group
if [[ ! -e "$group_link" ]]; then
  printf '%s\n' 'FAIL: no IOMMU group exists for the GPU. Enable Intel VT-d in firmware and check the kernel log.'
  exit 1
fi

group=$(basename "$(readlink -f "$group_link")")
printf '\nIOMMU group %s members:\n' "$group"
for device in /sys/kernel/iommu_groups/"$group"/devices/*; do
  bdf=$(basename "$device")
  printf '  %s  %s\n' "$bdf" "$(lspci -s "$bdf" -nn | sed 's/^[^ ]* //')"
done

printf '\nDriver ownership:\n'
for device in /sys/kernel/iommu_groups/"$group"/devices/*; do
  bdf=$(basename "$device")
  driver=$(readlink -f "$device/driver" 2>/dev/null || true)
  driver_name=${driver##*/}
  [[ -n "$driver_name" ]] || driver_name=unbound
  printf '  %s: %s\n' "$bdf" "$driver_name"
done

printf '\nPASS: IOMMU is active. All devices in group %s must be assigned together, and the host display will disappear while this single GPU is assigned to a VM.\n' "$group"
