include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "vpc" {
  config_path = "../vpc"
}
dependency "route53" {
  config_path = "../route53"
}
dependency "certificate" {
  config_path = "../certificate"
}

inputs = {
  server_vpc_id                = dependency.vpc.outputs.vpc.vpc.id
  server_vpc_name              = dependency.vpc.outputs.vpc.vpc.tags["Name"]
  private_subnet_ids           = dependency.vpc.outputs.vpc.private_subnet[*].id
  route53_public_hostedzone_id = dependency.route53.outputs.domain.hosted_zone_id
  server_certificate_arn       = dependency.certificate.outputs.arn
}
