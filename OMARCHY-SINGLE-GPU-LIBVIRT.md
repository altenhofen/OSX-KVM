# Omarchy single-GPU macOS VM

This setup uses system libvirt to hand the only physical GPU to macOS and
return it to Omarchy when the VM shuts down.

Host devices:

- RX 5600: `0000:09:00.0`
- HDMI audio: `0000:09:00.1`
- USB 3 controller: `0000:00:14.0` (IOMMU group 42)

The three host devices are detached and reattached by libvirt. SDDM is stopped
before the handoff and restarted after the VM exits. Linux is expected to be
headless while macOS owns the physical GPU. The physical USB 3 controller is
also assigned, so its attached keyboard, mouse, wireless receiver, USB audio,
and microphone devices belong to macOS while the VM runs.

Linux will not have access to those USB ports during the VM run. Use SSH for
host control and recovery.

## Performance choices

The VM uses 16 pinned vCPUs across eight physical cores with their SMT
siblings paired correctly. QEMU stays on the remaining physical core. Its 24
GiB are allocated immediately, and the persistent disk uses `cache='none'` and
native I/O.

The macOS disks remain SATA devices for OSX-KVM compatibility. This
libvirt/QEMU combination does not support IOThreads or virtio storage
multi-queue on those SATA targets, so those options are intentionally not
enabled. The host has one NUMA node, so vNUMA configuration would not add
anything. Hugepages are also left out until they are explicitly reserved on
the host.

Hyper-V enlightenments such as `hv-no-nonarch-coresharing` are not enabled;
they target Windows guests and are not appropriate tuning for this macOS VM.

## One-time setup

Run as the normal user:

```bash
prepare-osx-kvm
install-osx-kvm-libvirt
```

The installer detects the system libvirt QEMU identity, grants it access to
the VM files, enables and starts libvirt's `default` NAT network, then defines
the `osx-kvm` domain but does not start the VM.

## Start and stop

```bash
start-osx-kvm-libvirt
```

Starting from the desktop asks for confirmation, then runs the libvirt client
outside the graphical session so it survives SDDM stopping. Shut down macOS
normally. Libvirt reattaches the managed devices, then the release hook starts
SDDM.

Useful checks:

```bash
check-osx-vm
sudo virsh -c qemu:///system domstate osx-kvm
sudo journalctl -u libvirtd -b --no-pager
```

Do not add `vfio-pci.ids` to the kernel command line on this single-GPU host;
the host needs `amdgpu` until the VM starts. Do not run the old direct
passthrough helpers; libvirt is the canonical launch path.
