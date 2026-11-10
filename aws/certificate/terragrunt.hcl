include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "route53" {
  config_path = "../route53"
}

inputs = {
  route53_public_hostedzone_id = dependency.route53.outputs.domain.hosted_zone_id
}
