variable "publicdomain" { type = string }             # from ..*/common.hcl

module "domain" {
  source = "../modules/dnsdomain"
  domain       = var.publicdomain
}

output "domain" {
  value = module.domain
}
