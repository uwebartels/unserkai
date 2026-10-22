// resource "aws_cloudwatch_log_group" "public" {
//   provider          = aws.us-east-1
//   name              = "/aws/route53/${aws_route53_zone.public.name}"
//   retention_in_days = 30
// }
//
// data "aws_iam_policy_document" "route53_query_logging_policy" {
//   statement {
//     actions = [
//       "logs:CreateLogStream",
//       "logs:PutLogEvents",
//     ]
//     resources = ["arn:aws:logs:*:*:log-group:/aws/route53/*"]
//     principals {
//       identifiers = ["route53.amazonaws.com"]
//       type        = "Service"
//     }
//   }
// }
//
// resource "aws_cloudwatch_log_resource_policy" "this" {
//   provider        = aws.us-east-1
//   policy_document = data.aws_iam_policy_document.route53_query_logging_policy.json
//   policy_name     = "route53-query-logging-policy-${aws_route53_zone.public.name}"
// }
//
// resource "aws_route53_query_log" "this" {
//   depends_on               = [aws_cloudwatch_log_resource_policy.this]
//   cloudwatch_log_group_arn = aws_cloudwatch_log_group.public.arn
//   zone_id                  = aws_route53_zone.public.zone_id
// }
