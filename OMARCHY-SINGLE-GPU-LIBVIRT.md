# Omarchy single-GPU macOS VM

This setup uses system libvirt to hand the only physical GPU to macOS and
return it to Omarchy when the VM shuts down.

Host devices:

- RX 5600: `0000:09:00.0`
- HDMI audio: `0000:09:00.1`

The two devices are detached and reattached by libvirt hooks. SDDM is stopped
before the handoff and restarted after the VM exits. Linux is expected to be
headless while macOS owns the physical GPU.

## One-time setup

Run as the normal user:

```bash
prepare-osx-kvm
install-osx-kvm-libvirt
```

The installer defines the `osx-kvm` domain but does not start it.

## Start and stop

```bash
start-osx-kvm-libvirt
```

Starting from the desktop asks for confirmation, then runs the libvirt client
outside the graphical session so it survives SDDM stopping. Shut down macOS
normally. The release hook reattaches both PCI functions and starts SDDM.

Useful checks:

```bash
check-osx-vm
sudo virsh -c qemu:///system domstate osx-kvm
sudo journalctl -u libvirtd -b --no-pager
```

Do not add `vfio-pci.ids` to the kernel command line on this single-GPU host;
the host needs `amdgpu` until the VM starts. Do not run the old direct
passthrough helpers; libvirt is the canonical launch path.
