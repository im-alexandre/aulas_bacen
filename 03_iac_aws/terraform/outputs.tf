output "maquinas" {
  value = {
    for nome, vm in aws_instance.lab : nome => {
      id         = vm.id
      ip_publico = vm.public_ip
      ip_privado = vm.private_ip
    }
  }
}

output "inventario_ansible" {
  value = join("\n", concat(
    ["[gerenciados]"],
    [for nome, vm in aws_instance.lab : "${nome} ansible_host=${vm.private_ip} ansible_user=ubuntu" if local.maquinas[nome].perfil == "gerenciado"],
    [""],
  ))
}
