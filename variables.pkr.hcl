// variables.pkr.hcl
// Use PKR_VAR_* environment variables (Packer built-in). No custom parsing functions needed.

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

variable "iso_storage" {
  type = string
  default = env("PACKER_ISO_STORAGE")
}

variable "vm_storage" {
  type = string
}

variable "proxmox_storage" {
  type = string
}

variable "bridge_lan" {
  type    = string
  default = env("PACKER_BRIDGE_LAN")
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
  default = env("PACKER_SSH_PRIVATE_KEY_FILE")
}


variable "task_timeout" {
  type    = string
  default = "2h"
}
