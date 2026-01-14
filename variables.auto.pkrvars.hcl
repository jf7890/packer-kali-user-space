proxmox_skip_tls_verify = true

vm_storage      = "local-lvm"
proxmox_storage = "local-lvm"

template_vm_id       = 0
template_name        = "tpl-kali-xfce"
template_description = "Kali XFCE (Capstone)"

cores              = 4
memory             = 6144
ballooning_minimum = 0
disk_size          = "40G"

# Kali ISO (Installer amd64) + checksum
kali_iso_url             = "https://kali.download/base-images/current/kali-linux-2025.4-installer-amd64.iso"
kali_iso_checksum        = "sha256:3b4a3a9f5fb6532635800d3eda94414fb69a44165af6db6fa39c0bdae750c266"
# If the ISO already exists on Proxmox storage, point to it to skip downloads
kali_iso_file            = "hdd-data:iso/kali-linux-2025.4-installer-amd64.iso"

lan_vlan_tag = 10
task_timeout = "2h"

# Let Packer download the ISO and upload it to Proxmox (avoids relying on node Internet access)
iso_download_pve = false
