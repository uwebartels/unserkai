variable "publicdomain" {
  description = "public domain"
}

variable "route53_public_hostedzone_id" {
  description = "id of the route53 domain"
}

module "certificate" {
  source = "../modules/certificate"

  domain                       = var.publicdomain
  route53_public_hostedzone_id = var.route53_public_hostedzone_id
}

output "arn" {
  value = module.certificate.arn
}
