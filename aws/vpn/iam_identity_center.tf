// This is a template file for a basic deployment.
// Modify the parameters below with actual values

module "aws-iam-identity-center" {
  source = "aws-ia/iam-identity-center/aws"

  // Create desired GROUPS in IAM Identity Center
  sso_groups = {
    Admin : {
      group_name        = "Admin"
      group_description = "Admin IAM Identity Center Group"
    },
    Dev : {
      group_name        = "Dev"
      group_description = "Dev IAM Identity Center Group"
    }
  }

  // Create desired USERS in IAM Identity Center
  sso_users = {
    "uwe.bartels" : {
      group_membership = ["Admin", "Dev"]
      user_name        = "uwe.bartels"
      given_name       = "Uwe"
      family_name      = "Bartels"
      email            = "uwe.bartels@posteo.de"
    } 
  }

  // Create permissions sets backed by AWS managed policies
  permission_sets = {
    AdministratorAccess = {
      description          = "Provides AWS full access permissions.",
      session_duration     = "PT12H", // how long until session expires - this means 4 hours. max is 12 hours
      aws_managed_policies = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      tags                 = { ManagedBy = "Terraform" }
    },
    ViewOnlyAccess = {
      description          = "Provides AWS view only permissions.",
      session_duration     = "PT12H", // how long until session expires - this means 3 hours. max is 12 hours
      aws_managed_policies = ["arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"]
      tags                 = { ManagedBy = "Terraform" }
    },
  }

}
