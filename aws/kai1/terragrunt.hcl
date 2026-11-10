include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "vpc" {
  config_path = "../vpc"
}
dependency "route53" {
  config_path = "../route53"
}

inputs = {
  vpc_id              = dependency.vpc.outputs.vpc.vpc.id
  private_subnet_ids  = dependency.vpc.outputs.vpc.private_subnet[*].id
  route53_public_hostedzone_id = dependency.route53.outputs.domain.hosted_zone_id
}

terraform {
  after_hook "trigger_downstream" {
    commands     = ["apply"]
    execute      = ["bash", "-c", "export PATH=$PATH:/opt/homebrew/bin && cd ../ec2-autosleep && terragrunt apply"]
    run_on_error = false
  }
}
