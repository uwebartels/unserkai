module "iam_users" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-user"
  version = "5.11.1"

  for_each = { for user in local.iam_users : user.name => user }

  name = each.value.name

  create_iam_access_key         = false
  create_iam_user_login_profile = each.value.enable_iam_user_login_profile
  create_user                   = true
  force_destroy                 = false
  password_reset_required       = false
  password_length               = 20
  # chomp: remove last newline, cause: https://github.com/hashicorp/terraform/issues/20271
  pgp_key = chomp(var.pgp_key)
}
