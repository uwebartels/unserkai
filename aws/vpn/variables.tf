# from dependency
variable "server_vpc_name" {
  type = string
  description = "server vpc name to peer to"
}
variable "private_subnet_ids" { type = list }
variable "server_vpc_id" {}
variable "server_certificate_arn" {} # from dependency
variable "server_vpc_cidr" {} # from ..*/common.hcl
variable "aws_region" { type = string }             # from ..*/common.hcl
variable "vpn_vpc_cidr" { type = string }             # from ..*/common.hcl

locals {
  vpn_vpc_name = "vpn"
}
