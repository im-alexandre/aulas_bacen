resource "libvirt_network" "lab" {
  name      = "puppet-ansible-lab"
  autostart = true

  forward = {
    mode = "nat"
  }

  domain = {
    name       = "lab.test"
    local_only = "yes"
  }

  dns = {
    host = [
      for name, ip in local.addresses : {
        ip        = ip
        hostnames = [{ hostname = name }, { hostname = "${name}.lab.test" }]
      }
    ]
  }

  ips = [{
    address = cidrhost(var.lab_cidr, 1)
    prefix  = 24

    dhcp = {
      hosts = [
        for name, ip in local.addresses : {
          name = name
          mac  = local.macs[name]
          ip   = ip
        }
      ]
    }
  }]
}
