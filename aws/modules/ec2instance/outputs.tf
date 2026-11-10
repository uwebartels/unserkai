output "aws_instance" {
  value = {
    id                      = aws_instance.this.id
    arn                     = aws_instance.this.arn
    instance_type           = aws_instance.this.instance_type
    private_ip              = aws_instance.this.private_ip
    subnet_id               = aws_instance.this.subnet_id
    availability_zone       = aws_instance.this.availability_zone
    primary_network_interface_id = aws_instance.this.primary_network_interface_id
  }
}

output "dns_name" {
  value = local.dns_name
}

output "aws_iam_role" {
  value = aws_iam_role.ec2-role
}

output "public_fqdn" {
  value = aws_route53_record.ec2public.0.fqdn
}

output "subnet_id" {
  value = local.instance_subnet_id
  description = "subnet_id used for the ec2 instance"
}

output "availability_zone" {
  value = data.aws_subnet.selected.availability_zone
  description = "availability zone used for the ec2 instance"
}
 output "ec2_iam_role" {
   value = aws_iam_role.ec2-role
 }
