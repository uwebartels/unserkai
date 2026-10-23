variable "aws_region" { type = string }             # from ..*/common.hcl
variable "server_vpc_cidr" { type = string }             # from ..*/common.hcl

module "vpc" {
  source = "../modules/vpc"

  region                 = var.aws_region
  cidr                   = var.server_vpc_cidr
}
