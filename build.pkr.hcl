
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
      # Pre-provision during template build so clones don't download on first boot.
      "sudo mkdir -p /opt/capstone-userstack-src /opt/capstone-scripts",
      "sudo cp -a /tmp/capstone-userstack-src/. /opt/capstone-userstack-src/",
      "sudo cp -a /tmp/capstone-scripts/. /opt/capstone-scripts/",
      "sudo chmod +x /opt/capstone-scripts/*.sh",
      "sudo -E /opt/capstone-scripts/provision-kali-userstack.sh",
      # Finalize template (SSH hardening + generalization).
      "sudo -E /tmp/capstone-scripts/provision-kali-userstack.sh --prepare"
    ]
  }
}
