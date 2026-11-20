variable "vms" {
  type = map(object({
    host_number = number
    vcpu        = number
    memory_mb   = number
    disk_gb     = number
  }))

  validation {
    condition = (
      contains(keys(var.vms), "puppet-server") &&
      contains(keys(var.vms), "ansible-controller") &&
      length(distinct([for vm in values(var.vms) : vm.host_number])) == length(var.vms) &&
      alltrue([for vm in values(var.vms) : vm.host_number >= 2 && vm.host_number <= 254 && floor(vm.host_number) == vm.host_number])
    )
    error_message = "Inclua puppet-server e ansible-controller e use números de host inteiros e únicos entre 2 e 254."
  }
}

variable "lab_cidr" {
  description = "Sub-rede IPv4 /24 exclusiva do laboratório."
  type        = string
  default     = "192.168.177.0/24"

  validation {
    condition     = can(cidrnetmask(var.lab_cidr)) && endswith(var.lab_cidr, "/24")
    error_message = "Informe uma sub-rede IPv4 com prefixo /24."
  }
}

variable "base_image" {
  description = "Imagem cloud Ubuntu 24.04, com cloud-init, acessível pelo libvirt."
  type        = string
  default     = "/var/lib/libvirt/images/ubuntu-24.04-base.qcow2"
}

variable "ssh_public_key_path" {
  description = "Chave pública do host para SSH direto nos servidores e via ansible-controller nos agentes."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
