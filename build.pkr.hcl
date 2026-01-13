
build {
  name    = "kali"
  sources = ["source.proxmox-iso.kali-xfce"]

  # Proxmox cloud-init tweaks
  provisioner "file" {
    source      = "files/99-pve.cfg"
    destination = "/tmp/99-pve.cfg"
  }

  # User stack + provision script
  provisioner "shell" {
    inline = [
      "mkdir -p /tmp/capstone-userstack-src",
      "mkdir -p /tmp/capstone-scripts"
    ]
  }

  provisioner "file" {
    source      = "files/userstack/"
    destination = "/tmp/capstone-userstack-src"
  }

  provisioner "file" {
    source      = "scripts/"
    destination = "/tmp/capstone-scripts/"
  }

  provisioner "shell" {
    environment_vars = [
      "PACKER_SSH_PUBLIC_KEY=${var.ssh_public_key}"
    ]
    inline = [
      "chmod +x /tmp/capstone-scripts/provision-kali-userstack.sh",
      "sudo -E /tmp/capstone-scripts/provision-kali-userstack.sh --prepare"
    ]
  }
}
