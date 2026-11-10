# Kai — AWS-Berechtigungen und Terraform für den Pförtner

Stand: 10.11.2026, Vorschlag, nicht angewendet. Gehört zu [05](05_vorschlag-auto-stop.md), Bauplan Nr. 1. Der Code ist als Vorlage für `aws/` gedacht; angewendet wird er mit Terragrunt aus `aws/webui1` und `aws/kai1`.

## 1. Was gebraucht wird

| Wer | Darf | Worauf | Wozu |
|---|---|---|---|
| Instanzrolle von `webui1` (Modul legt sie als `/terraform/webui1` an) | `ec2:StartInstances`, `ec2:StopInstances` | nur Instanzen mit Tag `kai-pfoertner = managed` | Pförtner startet und stoppt GPU-Maschinen |
| dieselbe Rolle | `ec2:DescribeInstances` | alle (AWS erlaubt hier keine Einschränkung auf einzelne Instanzen) | Zustand abfragen (`running`, `stopped`, …); nur lesend |
| CloudWatch (AWS-Dienst) | `ec2:StopInstances` | `kai1` | Sicherheitsnetz: Alarm stoppt die Maschine bei 90 min CPU unter 5 % |

Nicht gebraucht: AWS-Schlüssel (die Rolle liefert kurzlebige Zugangsdaten über IMDS), Änderungen an Security Groups, neue Ports, Rechte für `kai1` selbst.

Warum ein Tag statt einer festen Instanz-ID: Eine zweite GPU-Maschine braucht dann nur das Tag, keine neue Berechtigung. Da nur Terraform Tags setzt (die Rolle hat kein `ec2:CreateTags`), kann sich niemand über das Tag Rechte verschaffen.

Stand im Repo: Die Instanzrolle von `webui1` erlaubt `ec2:StartInstances` und `ec2:StopInstances` bereits auf der festen Instanz-ID von `kai1` (`aws/webui1/iam.tf`, Änderung in PR #18), dazu `ec2:DescribeInstances`; der Pförtner läuft damit für `kai1` ohne weitere Änderung. Die Tag-Lösung unten ist nur nötig, sobald eine zweite GPU-Maschine dazukommt (eine neue Maschine bräuchte dann nur das Tag statt einer Änderung an der Richtlinie); der CloudWatch-Alarm (3.3) fehlt dort noch.

## 2. IAM-Richtlinie (zum Lesen)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "StartStopTaggedGpuInstances",
      "Effect": "Allow",
      "Action": ["ec2:StartInstances", "ec2:StopInstances"],
      "Resource": "arn:aws:ec2:eu-central-1:<Konto-ID>:instance/*",
      "Condition": {
        "StringEquals": { "aws:ResourceTag/kai-pfoertner": "managed" }
      }
    },
    {
      "Sid": "DescribeInstances",
      "Effect": "Allow",
      "Action": "ec2:DescribeInstances",
      "Resource": "*"
    }
  ]
}
```

## 3. Terraform

### 3.1 `aws/webui1/pfoertner.tf` (neu): Richtlinie an die Instanzrolle

Das Modul `ec2instance` gibt die Rolle als `module.ec2.aws_iam_role` heraus; eine Inline-Richtlinie dort hält das Modul unverändert.

```hcl
# Rights for kai-pfoertner on webui1: start and stop GPU instances tagged
# kai-pfoertner=managed, read instance state. No keys: the instance role
# delivers short-lived credentials through IMDS. See kai/docs/05, 07.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "pfoertner" {
  statement {
    sid       = "StartStopTaggedGpuInstances"
    actions   = ["ec2:StartInstances", "ec2:StopInstances"]
    resources = ["arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kai-pfoertner"
      values   = ["managed"]
    }
  }
  statement {
    sid       = "DescribeInstances"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "pfoertner" {
  name   = "kai-pfoertner"
  role   = module.ec2.aws_iam_role.name
  policy = data.aws_iam_policy_document.pfoertner.json
}
```

### 3.2 `aws/kai1/ec2.tf`: Tag an der Instanz

Im Modulaufruf von `kai1` (heute ohne `ec2_tags`):

```hcl
  ec2_tags = {
    "kai-pfoertner" = "managed"
  }
```

### 3.3 `aws/kai1/pfoertner_alarm.tf` (neu): Sicherheitsnetz

```hcl
# Safety net behind kai-pfoertner (kai/docs/05 §5): stop kai1 after 90 min
# with CPU below 5 %. Fires only if the pfoertner failed; normally it has
# stopped the instance long before. ~0.10 $/month.

data "aws_region" "alarm" {}
data "aws_caller_identity" "alarm" {}

resource "aws_cloudwatch_metric_alarm" "kai1_idle_stop" {
  alarm_name          = "kai1-idle-stop"
  alarm_description   = "kai1: CPU below 5 % for 90 min, stop (safety net behind kai-pfoertner)"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 18
  datapoints_to_alarm = 18
  threshold           = 5
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching" # stopped instance sends no data: no alarm

  dimensions = {
    InstanceId = module.ec2.aws_instance.id
  }

  alarm_actions = [
    "arn:aws:automate:${data.aws_region.alarm.name}:ec2:stop"
  ]
}
```

Die Aktion `arn:aws:automate:<region>:ec2:stop` braucht keine eigene Rolle; sie nutzt die Service-Linked Role `AWSServiceRoleForCloudWatchEvents`, die AWS beim ersten Gebrauch anlegt. Die Schwelle 5 % ist eine Annahme und wird nach der Messung in [05 §9](05_vorschlag-auto-stop.md#9-messen-bevor-die-werte-feststehen) geprüft.

### 3.4 Was nicht geändert wird

- `aws/modules/ec2instance`: bleibt generisch; es setzt keine `metadata_options`, also gilt der AWS-Standard (IMDSv2 optional, Hop-Limit 1). Der Pförtner läuft direkt auf `webui1`, nicht im Container, und kommt damit aus. Wer das Hop-Limit auf 1 lassen will, hält so auch Container von der Rolle fern.
- Security Groups und `firewall_rules.csv`: `webui1 → kai1:8080` ist schon erlaubt; der Pförtner lauscht nur im Docker-Netz von `webui1`.
- Private IP und Route-53-Eintrag von `kai1`: bleiben bei Stop/Start erhalten (EBS-gestützte Instanz, ENI bleibt an der Instanz).

## 4. Nachweis nach dem Anwenden

Von `webui1` aus (per SSM-Sitzung, ohne Profil, die Rolle gilt automatisch):

```sh
aws ec2 describe-instances --instance-ids i-0f896ee21e1ae8c72 \
  --query 'Reservations[].Instances[].State.Name' --output text   # stopped oder running
aws ec2 start-instances --instance-ids i-0f896ee21e1ae8c72           # erlaubt (Tag)
aws ec2 stop-instances  --instance-ids i-0f896ee21e1ae8c72           # erlaubt (Tag)
aws ec2 stop-instances  --instance-ids i-0f6dc684ea90b09cf           # UnauthorizedOperation: webui1 trägt das Tag nicht
```

Erwartet: die ersten drei Befehle klappen, der vierte wird abgelehnt. Danach der Alarm: in der CloudWatch-Konsole steht `kai1-idle-stop` auf `OK` oder `INSUFFICIENT_DATA` (Maschine aus), nie dauerhaft auf `ALARM`, solange der Pförtner läuft.

## 5. Kosten und Risiken

- Der Alarm kostet ≈ 0,10 $/Monat; die Berechtigungen nichts.
- Schlimmster Fall bei Missbrauch der Rolle (jemand hat Root auf `webui1`): GPU-Maschinen an- und ausschalten, Instanzliste lesen. Kein Zugriff auf Daten, Volumes oder andere Maschinen.
- Der Alarm stoppt auch während einer Haltesperre des Pförtners, wenn die CPU 90 min unter 5 % bleibt; wer lange ohne Last auf `kai1` arbeitet, stoppt den Alarm vorher (`aws cloudwatch disable-alarm-actions`) oder nimmt die Unterbrechung in Kauf.
