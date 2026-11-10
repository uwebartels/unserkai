# Find the EC2 instance by tag. Exactly one non-terminated instance
# must match this selector.
data "aws_instance" "target" {
  instance_tags   = var.instance_tag_filter

  filter {
    name = "instance-state-name"
    values = [
      "pending",
      "running",
      "stopping",
      "stopped"
    ]
  }
}

locals {
  # one() fails if multiple instances match; a missing match results in
  # a null ID and Terraform will report an invalid instance lookup below.
  target_instance_id = data.aws_instance.target.id


  instance_arn = "arn:aws:ec2:${var.aws_region}:${var.aws_account_id}:instance/${local.target_instance_id}"

  # Plain-text fields: srcport dstport protocol action log-status
  # Terraform's $${...} escape emits the literal ${...} expected by AWS.
  flow_log_format = "$${srcport} $${dstport} $${protocol} $${action} $${log-status}"
}

# # Find the primary ENI by the EC2 instance's private IP address.
# # The attachment filters ensure that this is device index 0 on the
# # selected instance, rather than another ENI with an unrelated address.
data "aws_network_interface" "primary" {
  filter {
    name   = "addresses.private-ip-address"
    values = [data.aws_instance.target.private_ip]
  }

  filter {
    name   = "attachment.instance-id"
    values = [local.target_instance_id]
  }

  filter {
    name   = "attachment.device-index"
    values = ["0"]
  }
}

# CloudWatch Logs destination
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/${var.name_prefix}/${local.target_instance_id}/vpc-flow-logs"
  retention_in_days = var.flow_log_retention_days

  tags = {
    ManagedBy = "Terraform"
    Purpose   = "EC2-AutoSleep"
  }
}

# IAM role used by the VPC Flow Logs service
data "aws_iam_policy_document" "flow_logs_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.name_prefix}-vpc-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume_role.json
}

data "aws_iam_policy_document" "flow_logs_write" {
  statement {
    sid    = "WriteFlowLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }

  statement {
    sid       = "DescribeLogGroupsAndStreams"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups", "logs:DescribeLogStreams"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "flow_logs_write" {
  name   = "${var.name_prefix}-write-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_write.json
}

# Monitor only the primary network interface of the selected EC2 instance.
resource "aws_flow_log" "instance" {
  eni_id                   = data.aws_network_interface.primary.id
  traffic_type             = "ACCEPT"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn             = aws_iam_role.flow_logs.arn
  max_aggregation_interval = 60
  log_format               = local.flow_log_format

  depends_on = [aws_iam_role_policy.flow_logs_write]

  tags = {
    Name      = "${var.name_prefix}-${local.target_instance_id}"
    ManagedBy = "Terraform"
  }
}

# Count accepted inbound TCP flow records whose destination port is 8080.
# VPC Flow Logs use positional, space-delimited fields here:
# srcport, dstport, protocol, action, log-status.
resource "aws_cloudwatch_log_metric_filter" "tcp_8080_activity" {
  name           = "${var.name_prefix}-tcp-8080-activity"
  log_group_name = aws_cloudwatch_log_group.flow_logs.name

  pattern = "[srcport, dstport = 8080, protocol = 6, action = ACCEPT, log_status = OK]"

  metric_transformation {
    name          = "Tcp8080AcceptedFlowRecords"
    namespace     = "Custom/EC2AutoSleep"
    value         = "1"
    default_value = 0
  }
}

# Shared Lambda execution role
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "autosleep_lambda" {
  name               = "${var.name_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_logging" {
  role       = aws_iam_role.autosleep_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda permissions are restricted to the target EC2 instance and alarm.
resource "aws_iam_role_policy" "autosleep_permissions" {
  name = "${var.name_prefix}-ec2-stop-and-alarm-reset"
  role = aws_iam_role.autosleep_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StopOnlyConfiguredInstance"
        Effect   = "Allow"
        Action   = ["ec2:StopInstances"]
        Resource = local.instance_arn
      },
      {
        Sid      = "ReadConfiguredInstanceState"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      },
      {
        Sid      = "ResetOnlyAutosleepAlarm"
        Effect   = "Allow"
        Action   = ["cloudwatch:SetAlarmState"]
        Resource = aws_cloudwatch_metric_alarm.tcp_8080_idle.arn
      },
      {
        Sid      = "PublishStartupHeartbeat"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "Custom/EC2AutoSleep"
          }
        }
      }
    ]
  })
}

# Package both Python Lambda functions.
data "archive_file" "stop_instance" {
  type        = "zip"
  source_file = "${path.module}/lambda/stop_instance.py"
  output_path = "${path.module}/stop_instance.zip"
}

data "archive_file" "reset_alarm" {
  type        = "zip"
  source_file = "${path.module}/lambda/reset_alarm.py"
  output_path = "${path.module}/reset_alarm.zip"
}

resource "aws_lambda_function" "stop_instance" {
  function_name    = "${var.name_prefix}-stop-instance"
  description      = "Stops the configured EC2 instance when the TCP/8080 idle alarm enters ALARM"
  role             = aws_iam_role.autosleep_lambda.arn
  handler          = "stop_instance.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.stop_instance.output_path
  source_code_hash = data.archive_file.stop_instance.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      EC2_INSTANCE_ID = local.target_instance_id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logging
  ]

  tags = {
    ManagedBy = "Terraform"
    Purpose   = "EC2-AutoSleep"
  }
}

resource "aws_lambda_function" "reset_alarm" {
  function_name    = "${var.name_prefix}-reset-alarm"
  description      = "Resets the AutoSleep alarm when the EC2 instance starts"
  role             = aws_iam_role.autosleep_lambda.arn
  handler          = "reset_alarm.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.reset_alarm.output_path
  source_code_hash = data.archive_file.reset_alarm.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      ALARM_NAME = aws_cloudwatch_metric_alarm.tcp_8080_idle.alarm_name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logging
  ]

  tags = {
    ManagedBy = "Terraform"
    Purpose   = "EC2-AutoSleep"
  }
}

resource "aws_cloudwatch_metric_alarm" "tcp_8080_idle" {
  alarm_name        = var.alarm_name
  alarm_description = "Stop ${local.target_instance_id} after ${var.idle_minutes} minutes without accepted inbound TCP flows to port 8080"

  namespace   = "Custom/EC2AutoSleep"
  metric_name = "Tcp8080AcceptedFlowRecords"
  statistic   = "Sum"
  period      = 60

  evaluation_periods  = var.idle_minutes
  datapoints_to_alarm = var.idle_minutes

  threshold           = 0
  comparison_operator = "LessThanOrEqualToThreshold"
  treat_missing_data  = "breaching"

  actions_enabled = true
  alarm_actions   = [aws_lambda_function.stop_instance.arn]

  depends_on = [aws_cloudwatch_log_metric_filter.tcp_8080_activity]

  tags = {
    ManagedBy = "Terraform"
    Purpose   = "EC2-AutoSleep"
  }
}

# CloudWatch alarm must be explicitly allowed to invoke the stop Lambda.
resource "aws_lambda_permission" "allow_alarm" {
  statement_id  = "AllowCloudWatchAlarmInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stop_instance.function_name
  principal     = "lambda.alarms.cloudwatch.amazonaws.com"
  source_account = var.aws_account_id
  source_arn     = aws_cloudwatch_metric_alarm.tcp_8080_idle.arn
}

# When the EC2 instance starts, reset the alarm to OK so a new idle window begins.
resource "aws_cloudwatch_event_rule" "instance_running" {
  name        = "${var.name_prefix}-instance-running"
  description = "Reset the AutoSleep alarm when the target EC2 instance enters running state"

  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
    detail = {
      state         = ["running"]
      "instance-id" = [local.target_instance_id]
    }
  })
}

resource "aws_cloudwatch_event_target" "reset_alarm" {
  rule      = aws_cloudwatch_event_rule.instance_running.name
  target_id = "ResetAutoSleepAlarm"
  arn       = aws_lambda_function.reset_alarm.arn
}

resource "aws_lambda_permission" "allow_eventbridge_reset" {
  statement_id  = "AllowEventBridgeResetAlarm"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.reset_alarm.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.instance_running.arn
}
