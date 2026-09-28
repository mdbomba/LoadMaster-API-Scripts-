---
name: loadmaster-install-media
description: Use when the user asks to deploy, install, import, locate, or select Kemp/Progress LoadMaster or ECS Connection Manager KVM/Xen install media on this host.
---

# Local LoadMaster Install Media

Use this inventory for KVM/libvirt deployment requests. The files are QCOW2
images with a 16 GiB virtual disk. Do not modify these source images; create
a full copy for each VM. Do not use qcow2 backing files or overlays.

## Required deployment order

For every new LoadMaster VLM, generate the management certificate before
creating the VM. Collect the VM name, management FQDN, short hostname,
management IP address, data IP address, and certificate password first. The
certificate must include the FQDN, short hostname, and both IP addresses as
subject alternative names.

Use the existing certificate generator; do not add another generator to this
repository. Run it as a regular user from `/home/mbomba/certs`; it invokes sudo
itself only to access the CA private key:

```bash
cd /home/mbomba/certs
bash ./gen-crt-and-key.sh
```

The script prompts for certificate details. Use the VM name as the file prefix,
the management FQDN as CN, the short hostname as CN2, the management IP as IP1,
and the data-network IP as IP2. Choose a strong temporary PFX/archive password;
do not reuse an account password. The script prints this password to the
terminal, so do not capture or share its output. It creates the key, CSR,
certificate, intermediate/root CA certificates, PFX, and ZIP archive in
`/home/mbomba/certs`. Protect the generated private key and archives, and remove
temporary PFX/ZIP material after the certificate has been installed and
verified.

Do not create the VM if certificate generation fails. After provisioning,
activation, and network setup, upload the generated private key, leaf
certificate, and intermediate chain using the LoadMaster APIv2 `addcert`
workflow. Assign the certificate to the management WUI/API. Verify all DNS/IP
SANs and the presented fingerprint; follow
`/home/chef/repos/LoadMaster/loadmaster-documents/TEST-LOADMASTER-RUNBOOK.md`
for the validated upload and TLS verification steps on this host.

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
