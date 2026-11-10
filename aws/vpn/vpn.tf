module "vpn" {
  source = "../modules/vpn"

  vpc_id = var.server_vpc_id
  subnet_id = var.private_subnet_ids[0]
  name = "vpn"
  server_certificate_arn = var.server_certificate_arn
  saml_provider_arn = aws_iam_saml_provider.client_vpn.arn
  vpc_cidr = var.server_vpc_cidr
  transport_protocol = "tcp"
  vpn_client_cidr = var.vpn_vpc_cidr
}
