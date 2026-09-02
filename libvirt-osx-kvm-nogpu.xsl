<?xml version="1.0" encoding="UTF-8"?>
<!-- Produce a diagnostic-only virtual-display domain from the normal XML.
     It deliberately has no PCI or USB host devices, so it cannot detach the
     RX 5600 or any host peripheral. -->
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

  <xsl:output method="xml" indent="yes"/>
  <xsl:param name="nogpu_vars"/>

  <xsl:template match="@*|node()">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="domain/name">
    <name>osx-kvm-nogpu</name>
  </xsl:template>

  <xsl:template match="domain/title">
    <title>macOS diagnostic virtual display (no GPU passthrough)</title>
  </xsl:template>

  <!-- Do not reuse the passthrough VM's NVRAM: it may remember the RX 5600
       as its only firmware console and therefore leave VNC completely black. -->
  <xsl:template match="domain/os/nvram">
    <nvram><xsl:value-of select="$nogpu_vars"/></nvram>
  </xsl:template>

  <!-- Keep no host devices in the diagnostic domain. -->
  <xsl:template match="devices/hostdev"/>

  <!-- The real VM passes its only host USB controller. The diagnostic VM
       needs its own emulated USB bus for the VNC keyboard and tablet. -->
  <xsl:template match="devices/controller[@type='usb']">
    <controller type="usb" index="0" model="ich9-ehci1">
      <address type="pci" domain="0x0000" bus="0x00" slot="0x1d" function="0x7" multifunction="on"/>
    </controller>
    <controller type="usb" index="0" model="ich9-uhci1">
      <master startport="0"/>
      <address type="pci" domain="0x0000" bus="0x00" slot="0x1d" function="0x0" multifunction="on"/>
    </controller>
    <controller type="usb" index="0" model="ich9-uhci2">
      <master startport="2"/>
      <address type="pci" domain="0x0000" bus="0x00" slot="0x1d" function="0x1"/>
    </controller>
    <controller type="usb" index="0" model="ich9-uhci3">
      <master startport="4"/>
      <address type="pci" domain="0x0000" bus="0x00" slot="0x1d" function="0x2"/>
    </controller>
  </xsl:template>

  <!-- A VNC-visible VGA device is sufficient to observe OVMF, OpenCore, and
       verbose boot. macOS acceleration is not expected in this test. -->
  <xsl:template match="devices/video">
    <video>
      <model type="vga" vram="16384" heads="1" primary="yes"/>
    </video>
    <graphics type="vnc" port="5901" autoport="no" listen="127.0.0.1">
      <listen type="address" address="127.0.0.1"/>
    </graphics>
    <!-- The normal VM receives physical USB hostdevs. This test intentionally
         has none, so give the VNC client explicit virtual input devices. -->
    <input type="keyboard" bus="usb"/>
    <input type="tablet" bus="usb"/>
  </xsl:template>
</xsl:stylesheet>
