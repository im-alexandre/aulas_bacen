variable "quantidade_nos" {
  type        = number
  description = "Total de VMs da frota, incluindo coletor-prometheus."

  validation {
    condition     = var.quantidade_nos >= 5 && var.quantidade_nos == floor(var.quantidade_nos)
    error_message = "Use um número inteiro a partir de 5 para incluir coletor-prometheus."
  }
}

variable "azure_location" {
  type        = string
  description = "Região Azure do grupo de recursos, da rede e das VMs."
  default     = "eastus"
}

variable "azure_subscription_id" {
  type        = string
  description = "ID da assinatura Azure autorizada para o laboratório."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$", var.azure_subscription_id))
    error_message = "Informe o UUID da assinatura retornado por az account show."
  }
}

variable "vm_size" {
  type        = string
  description = "Tamanho das VMs da frota no catálogo Azure."
  default     = "Standard_F1als_v7"
}

variable "ubuntu_image_version" {
  type        = string
  description = "Versão da imagem Canonical:ubuntu-24_04-lts:server para toda a frota."
}

variable "instructor_cidr" {
  type        = string
  description = "Endereço IPv4 público atual do instrutor, com sufixo /32."

  validation {
    condition     = can(cidrnetmask(var.instructor_cidr)) && endswith(var.instructor_cidr, "/32")
    error_message = "Informe um único IPv4 público no formato x.x.x.x/32."
  }
}

variable "ssh_public_key_path" {
  type        = string
  description = "Caminho para a chave pública SSH usada no laboratório."
  default     = "~/.ssh/bacen-iac-azure.pub"
}
