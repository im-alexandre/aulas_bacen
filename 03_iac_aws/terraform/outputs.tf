output "maquinas" {
  value = {
    for nome, vm in aws_instance.lab : nome => {
      id         = vm.id
      ip_publico = vm.public_ip
      ip_privado = vm.private_ip
    }
  }
}

output "ssh_config" {
  value = join("\n", concat(
    [
      "Host gerenciado-01 gerenciado-02 gerenciado-03 puppet-server",
      "  User ubuntu",
      "  IdentityFile ~/.ssh/bacen-iac-aws",
      "  IdentitiesOnly yes",
      "  StrictHostKeyChecking no",
    ],
    [
      for nome, vm in aws_instance.lab : join("\n", [
        " Host ${nome}",
        "   HostName ${vm.public_ip}",
      ])
    ],
  ))
}
