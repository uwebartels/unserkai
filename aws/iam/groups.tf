module "groups" {
  source   = "terraform-aws-modules/iam/aws//modules/iam-group-with-policies"
  version  = "5.11.1"
  for_each = { for group in local.groups : group.name => group }

  name                              = each.value.name
  group_users                       = each.value.members
  custom_group_policy_arns          = each.value.policy_arns
  attach_iam_self_management_policy = false

  depends_on = [
    aws_iam_policy.policies,
    module.iam_users
  ]
}
