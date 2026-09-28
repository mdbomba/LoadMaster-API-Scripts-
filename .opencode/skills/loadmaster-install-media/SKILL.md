---
name: loadmaster-install-media
description: Use when the user asks to deploy, install, import, locate, or select Kemp/Progress LoadMaster or ECS Connection Manager KVM/Xen install media on this host.
---

# Local LoadMaster Install Media

Use this inventory for KVM/libvirt deployment requests. The files are QCOW2
images with a 16 GiB virtual disk. Do not modify these source images; create
a separate QCOW2 overlay or copy for each VM.

## Required deployment order

For every new LoadMaster VLM, generate the management certificate before
creating a QCOW2 overlay or libvirt domain. Collect the VM name, management
FQDN, short hostname, management IP address, and certificate output directory
first. The certificate must include the FQDN, short hostname, and management
IP as subject alternative names.

Run the repository generator through sudo:

```bash
sudo /home/mbomba/repos/LoadMaster-API-Scripts-/scripts/generate-loadmaster-cert.sh \
  --name <vm-name> \
  --output-dir /home/mbomba/certs/loadmaster/<vm-name> \
  --dns <management-fqdn> \
  --dns <short-hostname> \
  --ip <management-ip>
```

The generator creates root-protected CA-signed PEM artifacts and fails if the
output directory already exists. Do not create the VM when certificate
generation fails. After VM provisioning, activation, and network setup,
import `server.key`, `server.crt`, and `intermediate-chain.crt` from the
generated output directory into the LoadMaster, assign the certificate to its
management WUI/API, and verify the resulting TLS certificate fingerprint
against `manifest.txt`.

| Product and license | Version | Source image |
| --- | --- | --- |
| LoadMaster VLM BYOL | 7.2.63.1 | `/home/mbomba/install/loadmaster/LoadMaster-VLM-KVM-XEN-BYOL/LoadMaster-VLM-7.2.63.1.d5f6edd.RELEASE-Linux-KVM-XEN.qcow2` |
| LoadMaster VLM Free | 7.2.63.2 | `/home/mbomba/install/loadmaster/LoadMaster-VLM-KVM-XEN-Free/LoadMaster-VLM-7.2.63.2.bc23afa.RELEASE-Linux-KVM-XEN-FREE.qcow2` |
| LoadMaster VLM SPLA | 7.2.54.17 | `/home/mbomba/install/loadmaster/LoadMaster-VLM-KVM-XEN-SPLA/LoadMaster-VLM-7.2.54.17.0b0b61a.RELEASE-Linux-KVM-XEN-SPLA.qcow2` |
| ECS Connection Manager | 7.2.62.0 | `/home/mbomba/install/loadmaster/ECS-Connection-Manager-KVM-XEN/ECS-Connection-Manager-7.2.62.0.22915.RELEASE-Linux-KVM-XEN.qcow2` |

## Existing KVM context

- Libvirt system connection: `qemu:///system`.
- Existing LoadMaster domains: `11_vlm11` and `12_vlm12`.
- The existing VLM domains use 2 vCPUs, 4 GiB RAM, a VirtIO QCOW2 disk, and
  VirtIO NICs attached to the `default` and `trustA` libvirt networks.
- Select BYOL for an independently licensed deployment; select Free for a lab
  or evaluation deployment; select SPLA only where its licensing applies.
