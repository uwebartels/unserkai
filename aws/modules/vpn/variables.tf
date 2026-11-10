provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "name" {
  description = "variable for several components"
  default = "client-vpn"
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  description = "Private Subnetz-ID für die Client-VPN-Zuordnung"
  type        = string
}

variable "server_certificate_arn" {
  description = "ARN des Serverzertifikats in ACM"
  type        = string
}

variable "saml_provider_arn" {
  description = "ARN des bestehenden IAM-SAML-Providers"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR des VPC-Netzes, auf das VPN-Nutzer zugreifen dürfen"
  type        = string
}

variable "vpn_client_cidr" {
  description = "Adressbereich für VPN-Clients; darf sich nicht mit VPC-/On-Prem-Netzen überschneiden"
  type        = string
  default     = "10.250.0.0/22"
}

variable "transport_protocol" {
  description = "transport protocol: udp or tcp"
  default     = "tcp"
}
