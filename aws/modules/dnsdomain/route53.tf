resource "aws_route53_zone" "public" {
  name     = "${var.domain}"
}
