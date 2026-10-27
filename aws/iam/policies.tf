resource "aws_iam_policy" "policies" {
  for_each = local.policies

  name   = each.key
  path   = "/"
  policy = each.value
}
