locals {
  maquinas = {
    puppet-server      = { perfil = "puppet-server", tipo = "t3.medium" }
    ansible-controller = { perfil = "ansible-controller", tipo = "t3.micro" }
    gerenciado-01      = { perfil = "gerenciado", tipo = "t3.micro" }
    gerenciado-02      = { perfil = "gerenciado", tipo = "t3.micro" }
    gerenciado-03      = { perfil = "gerenciado", tipo = "t3.micro" }
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
  user_data                   = file("${path.module}/../bootstrap/${each.value.perfil}.sh")

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
