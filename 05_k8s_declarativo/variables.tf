variable "vms" {
  type = map(object({
    vcpu      = number
    memory_mb = number
    disk_gb   = number
    mac       = string
  }))
}
