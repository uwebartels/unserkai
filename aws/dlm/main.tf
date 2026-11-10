# --------------------------------------------------
# IAM Role for Amazon Data Lifecycle Manager
# --------------------------------------------------

data "aws_iam_policy_document" "dlm_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "dlm_snapshot_role" {
  name               = "dlm-ebs-snapshot-lifecycle-role"
  assume_role_policy = data.aws_iam_policy_document.dlm_assume_role.json
}

resource "aws_iam_role_policy_attachment" "dlm_snapshot_policy" {
  role = aws_iam_role.dlm_snapshot_role.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

# --------------------------------------------------
# EBS Snapshot Lifecycle Policy
# Target: Volumes with dlm_snapshot=true
# --------------------------------------------------

resource "aws_dlm_lifecycle_policy" "ebs_snapshots" {
  description        = "Daily and monthly EBS snapshots"
  execution_role_arn = aws_iam_role.dlm_snapshot_role.arn
  state              = "ENABLED"

  policy_details {
    policy_type   = "EBS_SNAPSHOT_MANAGEMENT"
    resource_types = ["VOLUME"]

    target_tags = {
      dlm_snapshot = "true"
    }

    # ----------------------------------------------
    # Daily snapshots: retain 30 snapshots
    # ----------------------------------------------

    schedule {
      name = "DailySnapshots"

      copy_tags = true

      tags_to_add = {
        SnapshotType = "Daily"
        ManagedBy    = "DLM"
      }

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["03:00"]
      }

      retain_rule {
        count = 30
      }
    }

    # ----------------------------------------------
    # Monthly snapshots: retain 11 snapshots
    # Runs on the first day of each month
    # ----------------------------------------------

    schedule {
      name = "MonthlySnapshots"

      copy_tags = true

      tags_to_add = {
        SnapshotType = "Monthly"
        ManagedBy    = "DLM"
      }

      create_rule {
        cron_expression = "cron(0 4 1 * ? *)"
      }

      retain_rule {
        count = 11
      }
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.dlm_snapshot_policy
  ]

  tags = {
    Name      = "EBS-Snapshot-Lifecycle"
    ManagedBy = "Terraform"
  }
}

# --------------------------------------------------
# Output
# --------------------------------------------------

output "dlm_snapshot_policy_id" {
  description = "ID of the DLM snapshot lifecycle policy"
  value       = aws_dlm_lifecycle_policy.ebs_snapshots.id
}
