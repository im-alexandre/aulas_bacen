output "maquinas" {
  value = {
    for nome, vm in aws_instance.lab : nome => {
      id         = vm.id
      ip_publico = vm.public_ip
      ip_privado = vm.private_ip
    }
  }
}
