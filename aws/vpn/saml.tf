resource "aws_iam_saml_provider" "client_vpn" {
  name                   = "client-vpn"
  saml_metadata_document = file("${path.module}/saml-metadata.xml")

  tags = {
    Name = "client-vpn"
  }
}
