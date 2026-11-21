locals {
  puppet_server_name = "puppet-server.bacen.test"
  puppet_server_ip   = cidrhost(aws_subnet.lab.cidr_block, 10)

  maquinas = {
    puppet-server = { perfil = "puppet-server", tipo = "t3.medium" }
    gerenciado-01 = { perfil = "gerenciado", tipo = "t3.micro" }
    gerenciado-02 = { perfil = "gerenciado", tipo = "t3.micro" }
    gerenciado-03 = { perfil = "gerenciado", tipo = "t3.micro" }
  }
}

resource "aws_instance" "lab" {
  for_each = local.maquinas

  ami                         = var.ami_id
  instance_type               = each.value.tipo
  subnet_id                   = aws_subnet.lab.id
  vpc_security_group_ids      = [aws_security_group.perfil[each.value.perfil].id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.lab.key_name
  private_ip                  = each.key == "puppet-server" ? local.puppet_server_ip : null
  user_data_replace_on_change = true
  user_data = replace(templatefile("${path.module}/../cloud-init/${each.value.perfil}.yaml", {
    server_name = local.puppet_server_name
    server_ip   = local.puppet_server_ip
    certname    = "${each.key}.bacen.test"
    manifest    = file("${path.module}/../puppet/site.pp")
    puppet_server_name = local.puppet_server_name
  }), "\r\n", "\n")

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = each.key
    Lab  = "bacen-iac-aws"
  }

  # O cloud-init precisa chegar aos repositórios no primeiro boot.
  depends_on = [aws_route_table_association.lab, aws_vpc_security_group_egress_rule.ipv4]
}

resource "aws_key_pair" "lab" {
  key_name_prefix = "bacen-iac-aws-"
  public_key      = trimspace(file(pathexpand(var.ssh_public_key_path)))
}
