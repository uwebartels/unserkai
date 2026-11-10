include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "vpc" {
  config_path = "../vpc"
}
dependency "route53" {
  config_path = "../route53"
}
dependency "kai1" {
  config_path = "../kai1"
}

inputs = {
  vpc_id              = dependency.vpc.outputs.vpc.vpc.id
  private_subnet_1_id = dependency.vpc.outputs.vpc.private_subnet[0].id
  private_subnet_ids  = dependency.vpc.outputs.vpc.private_subnet[*].id
  route53_public_hostedzone_id = dependency.route53.outputs.domain.hosted_zone_id
  kai1_aws_instance_id = dependency.kai1.outputs.ec2.id
}
