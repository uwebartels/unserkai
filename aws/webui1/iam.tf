data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "ec2_start_stop" {
  name        = "EC2StartStopPolicy"
  description = "Allows starting, stopping and describing EC2 instances"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "StartStopSpecificInstance"
        Effect = "Allow"

        Action = [
          "ec2:StartInstances",
          "ec2:StopInstances"
        ]

        Resource = "arn:${data.aws_partition.current.partition}:ec2:${var.aws_region}:${var.aws_account_id}:instance/${var.kai1_aws_instance_id}"
      },
      {
        Sid    = "DescribeInstances"
        Effect = "Allow"

        Action = [
          "ec2:DescribeInstances"
        ]

        Resource = "*"
      }
    ]
  })
}
