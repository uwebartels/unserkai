locals {
  common       = read_terragrunt_config(find_in_parent_folders("common.hcl"))
}

remote_state {
  backend = "s3"
  generate = {
    path      = "generated-backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "unserkai-terraform-state-${local.common.inputs.aws_account_id}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "${local.common.inputs.aws_region}"
    encrypt        = true
    use_lockfile   = true
    #dynamodb_table = "unserkai-terraform-state-lock"
  }
}

# generate provider configuration
## to prevent code duplication in every terragrunt layer
generate "providers" {
  path      = "generated-providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
# provider which will be used as default aws provider
provider "aws" {
  region  = "${local.common.inputs.aws_region}"
  profile = "${local.common.inputs.account_profile}"
  assume_role {
    role_arn = "arn:aws:iam::${local.common.inputs.aws_account_id}:role/unserkai-terraform"
  }
  allowed_account_ids = ["${local.common.inputs.aws_account_id}"]
}
EOF
}

inputs = local.common.inputs
