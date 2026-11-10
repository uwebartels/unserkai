variable "aws_region" {}
variable "aws_account_id" {}

variable "instance_tag_filter" {
  description = "Tags used to select the EC2 instance monitored by AutoSleep"
  type        = map(string)
  default     = {
    "Name" = "kai1"
    "AutoSleep" = "true"
  }
}


variable "idle_minutes" {
  description = "Consecutive one-minute periods without matching TCP flow records"
  type        = number
  default     = 30

  validation {
    condition     = var.idle_minutes >= 5 && var.idle_minutes <= 60
    error_message = "idle_minutes must be between 5 and 60."
  }
}

variable "flow_log_retention_days" {
  description = "CloudWatch Logs retention period for VPC Flow Logs"
  type        = number
  default     = 7
}

variable "alarm_name" {
  description = "CloudWatch alarm name"
  type        = string
  default     = "EC2-TCP8080-AutoSleep"
}

variable "name_prefix" {
  description = "Prefix for created AWS resources"
  type        = string
  default     = "ec2-autosleep"
}
