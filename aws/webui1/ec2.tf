
module "ec2" {
  source = "../modules/ec2instance"

  name                         = "webui1"
  vpc_id                       = var.vpc_id
  availability_zone            = "eu-central-1b"
  subnet_id                    = var.private_subnet_ids[1]
  dns_name                     = "webui1"
  ssh_public_key               = var.ssh_public_key

  ec2_ami_id                   = "ami-04e9b382a9b6299a6" # amazon/debian-13-amd64-20261103-2651
  #ami_name_pattern = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20260503"
  instance_type                = "t3.medium"

  firewall_rules = local.rules
  ec2_role_policy_attachments  = [
    aws_iam_policy.ec2_start_stop.arn
  ]
  route53_public_hostedzone_id = var.route53_public_hostedzone_id


  user_data = <<-USERDATA
    #!/bin/bash
    set -euxo pipefail
    exec > >(tee -a /var/log/ssm-agent-install.log) 2>&1
    tee /etc/apt/apt.conf.d/99force-ipv4 <<'EOF'
    Acquire::ForceIPv4 "true";
    EOF
    export DEBIAN_FRONTEND=noninteractive
    apt-get update

    mkdir /tmp/ssm
    cd /tmp/ssm
    wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
    sudo dpkg -i amazon-ssm-agent.deb
    sudo systemctl status amazon-ssm-agent
    sudo systemctl enable amazon-ssm-agent
    sudo systemctl start amazon-ssm-agent

    apt-get install -y xfsprogs
    hostnamectl webui1
  USERDATA

  ec2_tags = {
    SSMAccess	= "UnserkaiUserSelfManagement"
  }
  # firewall_rules               = local.firewall_rules
  volume_size                  = 30
  volume_tags = {
    Name         = "webui1"
    dlm_snapshot = "true"
  }
}

resource "aws_ebs_volume" "data" {
  availability_zone = module.ec2.aws_instance.availability_zone
  size              = 20

  # tags coded here will be overwritten by volume_tags in aws_instance
  tags = {
    Name         = "webui1"
    dlm_snapshot = "true"
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = module.ec2.aws_instance.id
}
