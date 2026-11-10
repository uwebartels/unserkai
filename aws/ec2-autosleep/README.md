# EC2 AutoSleep with VPC Flow Logs (tag-based EC2 selection)

This Terraform project discovers exactly one existing EC2 instance by a configurable
tag (default: `AutoSleep=true`) and monitors its **primary network interface**.
It creates VPC Flow Logs and counts accepted TCP flow records whose
**destination port is 8080**.

If CloudWatch sees no matching flow records for 30 consecutive one-minute periods,
a CloudWatch alarm invokes Lambda, which stops the configured EC2 instance.

When the instance enters the `running` state again, EventBridge invokes a second
Lambda function. It resets the alarm to `OK` and publishes one startup heartbeat
metric datapoint. That datapoint prevents the old missing-data window from
immediately stopping a freshly started instance; if no traffic follows, the alarm
can trigger after the heartbeat ages out of the 30-minute evaluation window.

## Important behavior and limitations

- VPC Flow Logs record network flows, not HTTP requests or packet payloads.
- The filter counts accepted inbound TCP flow records (`protocol=6`,
  `action=ACCEPT`, `dstport=8080`). It does not count outbound response records
  where only the source port is 8080.
- Flow Logs use a 60-second maximum aggregation interval, but delivery to
  CloudWatch Logs is asynchronous and typically takes about five minutes.
  The stop therefore cannot be guaranteed at exactly 30 minutes after the last
  packet; it can happen later.
- A metric filter default value of zero is emitted for log batches with no matching
  records. If no flow-log events arrive at all, the alarm treats missing data as
  inactivity. If Flow Logs delivery is impaired, the instance could be stopped
  despite traffic. Test before production use.
- Only the primary ENI is monitored. If traffic can reach the instance through
  additional ENIs, create a Flow Log for each relevant interface and aggregate
  their metrics.
- The instance is stopped, not terminated. EBS volumes remain. This project does
  not automatically start the instance.
- Existing security groups, routing, and application settings are not modified.

## Files

```text
.
├── versions.tf
├── variables.tf
├── main.tf
├── outputs.tf
├── terraform.tfvars.example
└── lambda/
    ├── stop_instance.py
    └── reset_alarm.py
```

## Requirements

- Terraform >= 1.5
- AWS provider >= 5.0
- Archive provider >= 2.4
- Exactly one non-terminated EC2 instance must match `instance_tag_key` and
  `instance_tag_value` in the configured region. No match or multiple matches
  cause Terraform to fail rather than selecting an arbitrary instance.
- The Terraform execution identity needs permissions to describe the instance,
  create IAM roles and policies, create VPC Flow Logs, CloudWatch Logs resources,
  CloudWatch alarms, Lambda functions and EventBridge rules/targets, and pass the
  Flow Logs role (`iam:PassRole`).

## Deploy

1. Copy `terraform.tfvars.example` to `terraform.tfvars`.
2. Set the correct AWS region, `instance_tag_key` and `instance_tag_value`.
   The tag must identify exactly one non-terminated EC2 instance.
3. Run:

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

## Verify

1. Confirm that only the intended EC2 instance has the configured tag.
2. Run `terraform output monitored_instance_id` to see which instance Terraform selected.
3. Check the Flow Log on that instance's primary network interface.
4. Open the CloudWatch log group from `terraform output flow_log_group_name`.
5. Confirm that flow records have the five fields: source port, destination port,
   protocol, action and log status.
6. Check the alarm from `terraform output cloudwatch_alarm_name`.
7. Inspect Lambda logs if the alarm stops the instance.
8. Start the instance and verify that EventBridge invokes the reset Lambda.

## Costs

VPC Flow Logs ingestion, CloudWatch Logs storage and metric filters, Lambda and
CloudWatch alarms can incur charges. Log retention defaults to seven days.


## How tag-based selection works

Terraform queries EC2 instances in `aws_region` using these filters:

- Tag key: `instance_tag_key` (default `AutoSleep`)
- Tag value: `instance_tag_value` (default `true`)
- Instance states: pending, running, stopping, stopped

Exactly one matching instance is required. The selected instance ID is then used
internally for the ENI Flow Log, alarm description, EventBridge event pattern,
Lambda environment and narrowly scoped IAM permissions.

This is Terraform-time discovery: if you change the tag assignment or want to
monitor a different instance, run `terraform plan` and `terraform apply` again.
It is not a continuously running tag watcher.


### Primary network interface lookup

The monitored ENI is discovered with the EC2 instance's private IPv4 address
using the `aws_network_interface` data source. The lookup is additionally
restricted to the selected instance (`attachment.instance-id`) and its primary
device (`attachment.device-index = 0`). The VPC Flow Log uses the resulting
`data.aws_network_interface.primary.id`.
