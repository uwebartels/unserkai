
module "ec2" {
  source = "../modules/ec2instance"

  name                         = local.name
  vpc_id                       = var.vpc_id
  availability_zone            = "eu-central-1b"
  subnet_id                    = var.private_subnet_ids[1] # private_subnet_2 due to g4dn.xlarge resources at the time
  dns_name                     = local.name
  #s3_bucket_software_arn       = var.s3_bucket_software
  ssh_public_key               = var.ssh_public_key

  ec2_ami_id                   = "ami-04e9b382a9b6299a6" # amazon/debian-13-amd64-20261103-2651
  instance_type                = "g4dn.xlarge"

  firewall_rules = local.rules
  route53_public_hostedzone_id = var.route53_public_hostedzone_id

  user_data = <<-USERDATA
    #!/bin/bash
    #set -euxo pipefail
    #exec > >(tee -a /var/log/ssm-agent-install.log) 2>&1
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
    hostnamectl kai1
  USERDATA

  volume_size                  = 30
  volume_tags = {
    Name         = local.name
    dlm_snapshot = "true"
  }

  ec2_tags = {
    AutoSleep = true
  }
}


resource "aws_ebs_volume" "data" {
  availability_zone = module.ec2.aws_instance.availability_zone
  size              = 150

  # tags coded here will be overwritten by volume_tags in aws_instance
  tags = {
    Name         = local.name
    dlm_snapshot = "true"
  }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = module.ec2.aws_instance.id
}
