module "groups_enforce_mfa_for_all" {
  source  = "terraform-module/enforce-mfa/aws"
  version = "1.1.1"

  policy_name                     = "UnserKaiEnforceMFAForAllGroups"
  account_id                      = var.aws_account_id
  groups                          = ["unserkai_everbody"]
  manage_own_signing_certificates = true
  manage_own_ssh_public_keys      = true
  manage_own_git_credentials      = true

  depends_on = [module.groups]
}
