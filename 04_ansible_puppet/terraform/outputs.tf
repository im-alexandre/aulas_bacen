output "ips_publicos" {
  value = { for nome, ip in azurerm_public_ip.lab : nome => ip.ip_address }
}

output "ip_painel" {
  description = "IPv4 público de coletor-prometheus para abrir o túnel SSH."
  value       = azurerm_public_ip.lab[local.coletor].ip_address
}

output "inventario" {
  value = join("\n", concat(
    ["[monitor_lab]"],
    [for nome, vm in azurerm_linux_virtual_machine.lab : "${nome} ansible_host=${azurerm_public_ip.lab[nome].ip_address} monitor_ip_privado=${vm.private_ip_address} ansible_user=${local.usuario}"],
    [""],
    [<<-EOT
    [all:vars]
    ansible_user=ubuntu
    ansible_ssh_private_key_file=~/.ssh/id_ed25519
    ansible_python_interpreter=/usr/bin/python3
    EOT
    ]
  ))
}
