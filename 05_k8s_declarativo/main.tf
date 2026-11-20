locals {
  base_image = "/var/lib/libvirt/images/ubuntu-24.04-base.qcow2"
  ssh_key    = trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))
}

# ============================================================
# DISCOS DAS VMs
# ============================================================

resource "libvirt_volume" "disk" {
  for_each = var.vms

  name     = "${each.key}.qcow2"
  pool     = "default"
  capacity = each.value.disk_gb * 1024 * 1024 * 1024

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = local.base_image

    format = {
      type = "qcow2"
    }
  }
}

# ============================================================
# CLOUD-INIT
# ============================================================

resource "libvirt_cloudinit_disk" "init" {
  for_each = var.vms

  name = "${each.key}-cloudinit.iso"

  meta_data = yamlencode({
    "instance-id"    = each.key
    "local-hostname" = each.key
  })

  user_data = "#cloud-config\n${yamlencode({
    hostname         = each.key
    manage_etc_hosts = true
    ssh_pwauth       = false
    disable_root     = true

    users = [
      {
        name        = "ubuntu"
        groups      = ["sudo"]
        shell       = "/bin/bash"
        sudo        = "ALL=(ALL) NOPASSWD:ALL"
        lock_passwd = true

        ssh_authorized_keys = [
          local.ssh_key
        ]
      }
    ]

    packages = [
      "qemu-guest-agent"
    ]

    runcmd = [
      ["systemctl", "enable", "--now", "qemu-guest-agent"]
    ]
  })}"
}

# ============================================================
# VOLUMES CLOUD-INIT
# ============================================================

resource "libvirt_volume" "cloudinit" {
  for_each = var.vms

  name = "${each.key}-cloudinit.iso"
  pool = "default"

  create = {
    content = {
      url = libvirt_cloudinit_disk.init[each.key].path
    }
  }
}

# ============================================================
# MÁQUINAS VIRTUAIS
# ============================================================

resource "libvirt_domain" "vm" {
  for_each = var.vms

  name        = each.key
  type        = "kvm"
  memory      = each.value.memory_mb
  memory_unit = "MiB"
  vcpu        = each.value.vcpu
  running     = true

  os = {
    type = "hvm"
  }

  devices = {

    # --------------------------------------------------------
    # DISCO PRINCIPAL + CLOUD-INIT
    # --------------------------------------------------------

    disks = [
      {
        driver = {
          name = "qemu"
          type = "qcow2"
        }

        source = {
          volume = {
            pool   = libvirt_volume.disk[each.key].pool
            volume = libvirt_volume.disk[each.key].name
          }
        }

        target = {
          dev = "vda"
          bus = "virtio"
        }
      },

      {
        device = "cdrom"

        source = {
          volume = {
            pool   = libvirt_volume.cloudinit[each.key].pool
            volume = libvirt_volume.cloudinit[each.key].name
          }
        }

        target = {
          dev = "sda"
          bus = "sata"
        }
      }
    ]

    # --------------------------------------------------------
    # REDE NAT
    # --------------------------------------------------------

    interfaces = [
      {
        mac = {
          address = each.value.mac
        }

        model = {
          type = "virtio"
        }

        source = {
          network = {
            network = "default"
          }
        }
      }
    ]

    # --------------------------------------------------------
    # QEMU GUEST AGENT
    # --------------------------------------------------------

    channels = [
      {
        source = {
          unix = {
            mode = "bind"
          }
        }

        target = {
          virt_io = {
            name = "org.qemu.guest_agent.0"
          }
        }
      }
    ]
  }
}

# ============================================================
# OUTPUTS
# ============================================================

data "libvirt_domain_interface_addresses" "vm" {
  for_each = var.vms

  domain = libvirt_domain.vm[each.key].name
  source = "lease"

  depends_on = [
    libvirt_domain.vm
  ]
}

output "vms" {
  description = "Máquinas virtuais provisionadas"

  value = {
    for name, vm in libvirt_domain.vm :
    name => {
      vcpu      = var.vms[name].vcpu
      memory_mb = var.vms[name].memory_mb
      disk_gb   = var.vms[name].disk_gb
      ip = try(
        data.libvirt_domain_interface_addresses.vm[name].interfaces[0].addrs[0].addr,
        null
      )
    }
  }
}
