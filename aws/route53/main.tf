variable "publicdomain" { type = string }             # from ..*/common.hcl

module "domain" {
  source = "../modules/dnsdomain"
  domain       = var.publicdomain
}

resource "aws_route53domains_domain" "this" {
  domain_name = var.publicdomain
  auto_renew  = true

  admin_contact {
    first_name        = "Uwe"
    last_name         = "Bartels"
    phone_number      = "+49.15164316810"
    city              = "Berlin"
    zip_code          = "12589"
    address_line_1    = "Wiesenstr. 9"
    email             = "uwe.bartels@posteo.de"
    contact_type      = "PERSON"
    country_code      = "DE"
  }

  registrant_contact {
    first_name        = "Uwe"
    last_name         = "Bartels"
    phone_number      = "+49.15164316810"
    city              = "Berlin"
    zip_code          = "12589"
    address_line_1    = "Wiesenstr. 9"
    email             = "uwe.bartels@posteo.de"
    contact_type      = "PERSON"
    country_code      = "DE"
  }

  tech_contact {
    first_name        = "Uwe"
    last_name         = "Bartels"
    phone_number      = "+49.15164316810"
    city              = "Berlin"
    zip_code          = "12589"
    address_line_1    = "Wiesenstr. 9"
    email             = "uwe.bartels@posteo.de"
    contact_type      = "PERSON"
    country_code      = "DE"
  }

}

output "domain" {
  value = module.domain
}
