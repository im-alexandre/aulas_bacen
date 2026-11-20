locals {
  base_image = pathexpand(var.base_image)
  ssh_key    = trimspace(file(pathexpand(var.ssh_public_key_path)))

  agents = {
    for name, vm in var.vms : name => vm
    if !contains(["puppet-server", "ansible-controller"], name)
  }

  addresses     = { for name, vm in var.vms : name => cidrhost(var.lab_cidr, vm.host_number) }
  macs          = { for name, vm in var.vms : name => format("52:54:00:bc:02:%02x", vm.host_number) }
  controller_ip = local.addresses["ansible-controller"]

  inventory = join("\n", concat(
    ["[agents]"],
    [for name in keys(local.agents) : "${name} ansible_host=${local.addresses[name]}"],
    ["", "[agents:vars]", "ansible_user=ubuntu", ""]
  ))
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
          contains(keys(local.agents), each.key) ? "from=\"${local.controller_ip}\" ${local.ssh_key}" : local.ssh_key
        ]
      }
    ]

    package_update = true

    packages = concat(["qemu-guest-agent"], lookup({
      "puppet-server"      = ["puppetserver"]
      "ansible-controller" = ["ansible"]
    }, each.key, ["puppet-agent", "nftables"]))

    write_files = concat(
      each.key == "puppet-server" ? [
        {
          path        = "/etc/puppet/puppet.conf"
          owner       = "root:root"
          permissions = "0644"
          content     = "[main]\ncertname = puppet-server\nserver = puppet-server\n"
        },
        {
          path        = "/etc/puppet/code/environments/production/manifests/site.pp"
          owner       = "root:root"
          permissions = "0644"
          content     = file("${path.module}/puppet/manifests/nginx.pp")
        }
      ] : [],
      each.key == "ansible-controller" ? [
        {
          path        = "/home/ubuntu/inventory.ini"
          owner       = "ubuntu:ubuntu"
          permissions = "0644"
          defer       = true
          content     = local.inventory
        }
      ] : [],
      contains(keys(local.agents), each.key) ? [
        {
          path        = "/usr/local/sbin/restringir-agente"
          owner       = "root:root"
          permissions = "0755"
          content     = file("${path.module}/scripts/restringir-agente.sh")
        },
        {
          path        = "/etc/puppet/code/environments/production/manifests/nginx.pp"
          owner       = "root:root"
          permissions = "0644"
          content     = file("${path.module}/puppet/manifests/nginx.pp")
        }
      ] : []
    )

    runcmd = concat(
      [["systemctl", "enable", "--now", "qemu-guest-agent"]],
      each.key == "puppet-server" ? [["systemctl", "enable", "--now", "puppetserver"]] : [],
      contains(keys(local.agents), each.key) ? [
        ["/usr/local/sbin/restringir-agente", local.controller_ip],
        ["puppet", "config", "set", "server", "puppet-server", "--section", "main"],
        ["systemctl", "disable", "--now", "puppet.service"]
      ] : []
    )
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
        type = "network"

        source = {
          network = {
            network = libvirt_network.lab.name
          }
        }

        mac = {
          address = local.macs[each.key]
        }

        model = {
          type = "virtio"
        }

        wait_for_ip = {
          timeout = 120
          source  = "lease"
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

