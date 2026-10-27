locals {

  iam_users = csvdecode(file("../files/iam/users.csv"))

  # create dictionary policy_name: policy_content
  # use template engine to replace some variables
  policies = {
    for file_name in toset(fileset("../files/policies", "*.json")) :
    replace(file_name, ".json", "") => file("../files/policies/${file_name}")
  }

  groups = [
    for group in csvdecode(file("../files/iam/groups.csv")) :
    group.name == "unserkai_everbody" ?
    {
      name : group.name
      members : [for user in local.iam_users : user.name]
      policy_arns : length(group.policy_arns) > 0 ? split(";", group.policy_arns) : []
    }
    :
    {
      name : group.name
      members : length(group.members) > 0 ? split(";", group.members) : []
      policy_arns : length(group.policy_arns) > 0 ? split(";", group.policy_arns) : []
    }
  ]

}
