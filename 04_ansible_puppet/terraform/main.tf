locals {
  coletor = "coletor-prometheus"
  usuario = "ubuntu"
  nomes = [
    for numero in range(1, var.quantidade_nos + 1) :
    numero == 1 ? local.coletor : format("monitor-%02d", numero)
  ]
}

resource "azurerm_resource_group" "lab" {
  name     = "bacen-aula47"
  location = var.azure_location
}

resource "azurerm_linux_virtual_machine" "lab" {
  for_each = toset(local.nomes)

  name                            = each.key
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.vm_size
  admin_username                  = local.usuario
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.lab[each.key].id]

  admin_ssh_key {
    username   = local.usuario
    public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = var.ubuntu_image_version
  }

  depends_on = [azurerm_network_interface_application_security_group_association.coletor]
}
