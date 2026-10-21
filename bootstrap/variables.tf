variable "profile" {
  description = "aws profile with personal account"
  type        = string
}
variable "region" {
  description = "aws region"
  type        = string
}
variable "pgp_key" {
  description = "base64 encoded string of pgp public key"
  type        = string
}
variable "username" {
  description  = "terraform username"
  type = string
}
variable "groupname" {
  description  = "terraform groupname"
  type = string
}
variable "s3_bucket_name" {
  description = "s3 bucket name used to store terraform state"
  type        = string
}
