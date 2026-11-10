variable "ssh_public_key" {
  type = string
}

# from ../vpc
variable "vpc_id" {
  type        = string
  description = "ID of the VPC"
}
variable "private_subnet_ids" {
  type        = list(string)
  description = "List of Subnet Ids of a private subnet"
}

# from ../route53
variable "route53_public_hostedzone_id" {
  type        = string
  description = "Route 53 Hosted Zone ID"
}

variable "kai1_aws_instance_id" {}
variable "aws_region" {}
variable "aws_account_id" {}
