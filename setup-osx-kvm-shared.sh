#!/usr/bin/env bash
set -Eeuo pipefail

# Export ~/Shared to macOS as an authenticated SMB volume. macOS does not
# provide a native virtiofs/9p client, so an SMB share is the reliable way to
# make a host directory available from this KVM guest.

readonly SHARE_USER=${SUDO_USER:-$USER}
readonly SHARE_DIR="/home/$SHARE_USER/Shared"
readonly SHARE_NAME='osx-kvm-shared'
readonly SAMBA_CONF='/etc/samba/smb.conf'
readonly MARKER="# Managed by $SHARE_NAME"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[[ ${EUID} -ne 0 ]] || die 'run this as your normal user; it will request sudo when needed'
[[ -d "$SHARE_DIR" ]] || die "$SHARE_DIR does not exist"

if ! command -v smbd >/dev/null 2>&1; then
  printf 'Samba is not installed. Installing it now requires sudo.\n'
  sudo pacman -S --needed samba
fi

if [[ ! -f "$SAMBA_CONF" ]]; then
  if [[ -f /etc/samba/smb.conf.default ]]; then
    sudo install -m 0644 /etc/samba/smb.conf.default "$SAMBA_CONF"
  else
    die "$SAMBA_CONF is missing and no Samba default configuration was found"
  fi
fi

if ! sudo grep -Fqx "$MARKER" "$SAMBA_CONF"; then
  sudo tee -a "$SAMBA_CONF" >/dev/null <<EOF

$MARKER
[$SHARE_NAME]
   path = $SHARE_DIR
   browseable = yes
   read only = no
   guest ok = no
   valid users = $SHARE_USER
   force user = $SHARE_USER
   create mask = 0644
   directory mask = 0755
EOF
fi

printf 'Set or update the Samba password for %s when prompted.\n' "$SHARE_USER"
sudo smbpasswd -a "$SHARE_USER"
sudo testparm -s "$SAMBA_CONF" >/dev/null
sudo systemctl enable --now smb.service

host_ip=$(ip -4 -o addr show dev virbr0 2>/dev/null | awk '{split($4, a, "/"); print a[1]; exit}')
[[ -n "$host_ip" ]] || host_ip='192.168.122.1'

printf '\nShared folder is ready. In macOS Finder, choose Go → Connect to Server and enter:\n'
printf '  smb://%s/%s\n' "$host_ip" "$SHARE_NAME"
printf 'Sign in as %s using the Samba password you just set.\n' "$SHARE_USER"
