variable "proxmox_url" {
  type = string
  default = env("PROXMOX_URL")
}

variable "proxmox_username" {
  type = string
  default = env("PROXMOX_USERNAME")
}

variable "proxmox_token" {
  type      = string
  sensitive = true
  default = env("PROXMOX_TOKEN")
}

variable "proxmox_node" {
  type = string
  default = env("PROXMOX_NODE")
}

variable "proxmox_skip_tls_verify" {
  type    = bool
  default = true
}

variable "iso_storage" {
  type = string
  # Prefer ISO_STORAGE (matches note.txt), fall back to legacy PACKER_ISO_STORAGE
  default = env("ISO_STORAGE") != "" ? env("ISO_STORAGE") : env("PACKER_ISO_STORAGE")
}

variable "vm_storage" {
  type = string
}

variable "proxmox_storage" {
  type = string
}

variable "bridge_lan" {
  type    = string
  # Prefer BRIDGE_LAN (matches note.txt), fall back to legacy PACKER_BRIDGE_LAN
  default = env("BRIDGE_LAN") != "" ? env("BRIDGE_LAN") : env("PACKER_BRIDGE_LAN")
}

variable "lan_vlan_tag" {
  type    = number
  default = 0
}

variable "ssh_public_key" {
  type    = string
  default = env("PACKER_SSH_PUBLIC_KEY")
}

variable "ssh_private_key_file" {
  type    = string
  default = env("PACKER_SSH_PRIVATE_KEY")
}

variable "template_vm_id" {
  type = number
}

variable "template_name" {
  type = string
}

variable "template_description" {
  type    = string
  default = "Kali XFCE (Capstone)"
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 4096
}

variable "ballooning_minimum" {
  type    = number
  default = 0
}

variable "disk_size" {
  type    = string
  default = "30G"
}

variable "kali_iso_url" {
  type = string
}

variable "kali_iso_file" {
  type    = string
  default = ""
}

variable "kali_iso_checksum" {
  type    = string
  default = "none"
}

variable "iso_download_pve" {
  type    = bool
  default = true
}

variable "task_timeout" {
  type    = string
  default = "2h"
}
