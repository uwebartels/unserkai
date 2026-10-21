module "iam_user-terraform" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-user"
  version = "~> 3.0"
  name    = var.username

  create_iam_access_key         = "true"
  create_iam_user_login_profile = "false"
  create_user                   = "true"
  force_destroy                 = "false"
  password_reset_required       = "false"
  password_length               = "20"
  # chomp: remove last newline, cause: https://github.com/hashicorp/terraform/issues/20271
  pgp_key = chomp(var.pgp_key)
}

module "group" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-group-with-policies"
  version = "4.7.0"

  name                              = var.groupname
  group_users                       = [var.username]
  custom_group_policy_arns          = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  attach_iam_self_management_policy = false

}

# not using iam module as creating user+iam_assumable_role works only when executing code several times
#resource "aws_iam_user_policy_attachment" "terraform_AdministratorAccess" {
#  user       = module.iam_user-terraform.this_iam_user_name
#  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
#}

# create assumable role to be used in sub-accounts
module "iam_assumable_role_terraform" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "~> 3.0"

  trusted_role_arns = [
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${var.username}",
  ]

  create_role = true
  role_name   = var.username
  # security exception - because terraform doesn't support AWS IAM MFA yet
  # see: https://github.com/hashicorp/terraform-provider-aws/issues/2420
  role_requires_mfa = false
  # set maximum CLI/API session duration to maximum allowed value of 43200 seconds = 12 hours
  max_session_duration = 43200

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/AdministratorAccess",
  ]
}
