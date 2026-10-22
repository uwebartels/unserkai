locals {
  secret_vars         = yamldecode(sops_decrypt_file("${get_terragrunt_dir()}/secrets.yaml"))
}
inputs = merge(
  local.secret_vars,
  {
    aws_account_id  = "400295622374"
    aws_region      = "eu-central-1"
    account_profile = "unserkai-terraform"
    publicdomain    = "unserkai.de"
    server_vpc_cidr = "10.0.0.0/16"
  }
)
