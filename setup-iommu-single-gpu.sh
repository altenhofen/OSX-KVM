#!/usr/bin/env bash
set -Eeuo pipefail

# First-stage host preparation for single-GPU passthrough on Omarchy/Arch.
#
# This enables Intel IOMMU and makes VFIO available in the initramfs. It does
# NOT add vfio-pci.ids: binding the only display GPU at boot would normally
# make the host's local graphical session unusable.

readonly IOMMU_DROPIN=/etc/limine-entry-tool.d/zz-iommu-single-gpu.conf
readonly VFIO_DROPIN=/etc/mkinitcpio.conf.d/zz-vfio-single-gpu.conf
readonly BACKUP_DIR=/var/backups/iommu-single-gpu-$(date +%Y%m%d-%H%M%S)

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[[ ${EUID} -eq 0 ]] || die "run this script with sudo: sudo $0"

command -v lspci >/dev/null || die "pciutils is required (install it with pacman -S pciutils)"
command -v limine-mkinitcpio >/dev/null || die "limine-mkinitcpio is not installed"

mapfile -t display_bdfs < <(
  lspci -Dn | awk '$2 ~ /^030[02]:$/ { print $1 }'
)
(( ${#display_bdfs[@]} == 1 )) || die "expected exactly one display controller; found ${#display_bdfs[@]}"

readonly GPU_BDF=${display_bdfs[0]}
readonly GPU_SLOT=${GPU_BDF%.*}
readonly GPU_INFO=$(lspci -s "$GPU_BDF" -nn)

mapfile -t gpu_ids < <(
  lspci -Dn |
    awk -v slot="$GPU_SLOT" '$1 ~ ("^" slot "\\.") { for (i = 1; i <= NF; i++) if ($i ~ /^[[:xdigit:]]{4}:[[:xdigit:]]{4}$/) print $i }'
)
(( ${#gpu_ids[@]} > 0 )) || die "could not determine PCI IDs for $GPU_BDF"

printf 'Detected single display controller:\n  %s\n' "$GPU_INFO"
printf 'PCI functions in the GPU slot:\n'
for id in "${gpu_ids[@]}"; do
  printf '  %s\n' "$id"
done

if [[ -e /sys/kernel/iommu_groups ]]; then
  if compgen -G '/sys/kernel/iommu_groups/*/devices/*' >/dev/null; then
    printf 'IOMMU groups are already present; preserving the existing setup.\n'
  else
    printf 'IOMMU groups are not active in the running kernel; the boot change will take effect after reboot.\n'
  fi
fi

mkdir -p "$BACKUP_DIR" "$(dirname "$IOMMU_DROPIN")" "$(dirname "$VFIO_DROPIN")"

backup_if_present() {
  local path=$1
  if [[ -e "$path" ]]; then
    cp -a -- "$path" "$BACKUP_DIR/$(basename "$path")"
    printf 'Backed up %s to %s/%s\n' "$path" "$BACKUP_DIR" "$(basename "$path")"
  fi
}

write_managed_file() {
  local path=$1
  local content=$2
  local tmp

  if [[ -e "$path" ]] && cmp -s <(printf '%s\n' "$content") "$path"; then
    printf 'Already configured: %s\n' "$path"
    return
  fi

  backup_if_present "$path"
  tmp=$(mktemp)
  printf '%s\n' "$content" > "$tmp"
  install -m 0644 "$tmp" "$path"
  rm -f -- "$tmp"
  printf 'Wrote %s\n' "$path"
}

write_managed_file "$IOMMU_DROPIN" "$(printf '%s\n' \
  '# Managed by setup-iommu-single-gpu.sh' \
  'KERNEL_CMDLINE[default]+=" intel_iommu=on iommu=pt"')"

write_managed_file "$VFIO_DROPIN" "$(printf '%s\n' \
  '# Managed by setup-iommu-single-gpu.sh' \
  '# Deliberately no vfio-pci.ids: this host has only one GPU.' \
  'MODULES+=(vfio_pci vfio vfio_iommu_type1)')"

printf 'Rebuilding Limine/mkinitcpio images...\n'
limine-mkinitcpio

printf '\nDone. Backup: %s\n' "$BACKUP_DIR"
printf 'Reboot, then run:\n'
printf '  sudo %q/verify-iommu-single-gpu.sh\n' "$(dirname "$0")"
printf '\nThe GPU was not bound to VFIO at boot; that is intentional for a single-GPU host.\n'
