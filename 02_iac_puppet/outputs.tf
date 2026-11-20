output "vms" {
  description = "Máquinas virtuais provisionadas e seus endereços DHCP reservados."

  value = {
    for name, vm in libvirt_domain.vm :
    name => {
      vcpu      = vm.vcpu
      memory_mb = var.vms[name].memory_mb
      disk_gb   = var.vms[name].disk_gb
      ip        = local.addresses[name]
    }
  }
}

output "ansible_inventory" {
  description = "Inventário dos agentes para uso no ansible-controller."
  value       = local.inventory
}
