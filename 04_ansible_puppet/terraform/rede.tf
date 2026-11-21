resource "azurerm_virtual_network" "lab" {
  name                = "bacen-aula47-vnet"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.47.0.0/16"]
}

resource "azurerm_subnet" "lab" {
  name                            = "monitoramento"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.lab.name
  address_prefixes                = ["10.47.1.0/24"]
  default_outbound_access_enabled = false
}

resource "azurerm_application_security_group" "coletor" {
  name                = local.coletor
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
}

resource "azurerm_network_security_group" "lab" {
  name                = "bacen-aula47-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  security_rule {
    name                       = "ssh-instrutor"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.instructor_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                                  = "node-exporter-do-coletor"
    priority                              = 110
    direction                             = "Inbound"
    access                                = "Allow"
    protocol                              = "Tcp"
    source_port_range                     = "*"
    destination_port_range                = "9100"
    source_application_security_group_ids = [azurerm_application_security_group.coletor.id]
    destination_address_prefix            = "*"
  }

  # Sobrescreve as permissões de entrada padrão da rede virtual.
  security_rule {
    name                       = "bloquear-demais-entradas"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "lab" {
  subnet_id                 = azurerm_subnet.lab.id
  network_security_group_id = azurerm_network_security_group.lab.id
}

resource "azurerm_public_ip" "lab" {
  for_each = toset(local.nomes)

  name                = "${each.key}-ip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "lab" {
  for_each = toset(local.nomes)

  name                = "${each.key}-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "principal"
    subnet_id                     = azurerm_subnet.lab.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.lab[each.key].id
  }

  depends_on = [azurerm_subnet_network_security_group_association.lab]
}

resource "azurerm_network_interface_application_security_group_association" "coletor" {
  network_interface_id          = azurerm_network_interface.lab[local.coletor].id
  application_security_group_id = azurerm_application_security_group.coletor.id
}
