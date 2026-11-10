
resource "aws_security_group" "client_vpn" {
  name        = "${var.name}-sg"
  description = "Security Group for AWS Client VPN"
  vpc_id      = var.vpc_id

  # Beispiel: Zugriff aus dem VPN-Client-Netz in die VPC.
  # Bei Bedarf auf tatsächlich benötigte Ports/Protokolle einschränken.
  ingress {
    description = "VPN-Clients in die VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpn_client_cidr]
  }

  egress {
    description = "Ausgehender Verkehr"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-sg"
  }
}

resource "aws_cloudwatch_log_group" "client_vpn" {
  name              = "/aws/${var.name}/access"
  retention_in_days = 90
}

resource "aws_ec2_client_vpn_endpoint" "main" {
  description            = "${var.name}"
  server_certificate_arn = var.server_certificate_arn
  client_cidr_block      = var.vpn_client_cidr
  vpc_id                 = var.vpc_id
  split_tunnel           = true
  transport_protocol     = var.transport_protocol
  security_group_ids     = [aws_security_group.client_vpn.id]

  authentication_options {
    type              = "federated-authentication"
    saml_provider_arn = var.saml_provider_arn
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.client_vpn.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.client_vpn.name
  }

  tags = {
    Name = "${var.name}"
  }
}

resource "aws_cloudwatch_log_stream" "client_vpn" {
  name           = "${var.name}"
  log_group_name = aws_cloudwatch_log_group.client_vpn.name
}

resource "aws_ec2_client_vpn_network_association" "subnet" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  subnet_id              = var.subnet_id
}

import {
  to = aws_ec2_client_vpn_route.vpc
  id = "${aws_ec2_client_vpn_endpoint.main.id},${var.subnet_id},${var.vpc_cidr}"
}

resource "aws_ec2_client_vpn_route" "vpc" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  destination_cidr_block = var.vpc_cidr
  target_vpc_subnet_id   = var.subnet_id
  description            = "Default Route"

  depends_on = [aws_ec2_client_vpn_network_association.subnet]
}

resource "aws_ec2_client_vpn_authorization_rule" "vpc" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  target_network_cidr    = var.vpc_cidr
  authorize_all_groups   = true
  description            = "Zugriff auf das VPC-Netz"
}

output "client_vpn_endpoint_id" {
  value = aws_ec2_client_vpn_endpoint.main.id
}

output "client_vpn_dns_name" {
  value = aws_ec2_client_vpn_endpoint.main.dns_name
}
