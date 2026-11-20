resource "aws_vpc" "lab" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "bacen-iac-aws"
  }
}

resource "aws_subnet" "lab" {
  vpc_id     = aws_vpc.lab.id
  cidr_block = "10.42.1.0/24"

  tags = {
    Name = "bacen-iac-aws-publica"
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
}

resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }
}

resource "aws_route_table_association" "lab" {
  subnet_id      = aws_subnet.lab.id
  route_table_id = aws_route_table.publica.id
}

resource "aws_security_group" "perfil" {
  for_each = toset(["puppet-server", "gerenciado"])

  name_prefix = "bacen-iac-aws-${each.key}-"
  vpc_id      = aws_vpc.lab.id
}

resource "aws_vpc_security_group_ingress_rule" "instrutor" {
  for_each = aws_security_group.perfil

  security_group_id = each.value.id
  cidr_ipv4         = var.instructor_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "puppet" {
  security_group_id            = aws_security_group.perfil["puppet-server"].id
  referenced_security_group_id = aws_security_group.perfil["gerenciado"].id
  ip_protocol                  = "tcp"
  from_port                    = 8140
  to_port                      = 8140
}

resource "aws_vpc_security_group_egress_rule" "ipv4" {
  for_each = aws_security_group.perfil

  security_group_id = each.value.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
