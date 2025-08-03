output "name" {
  description = "Name of the SFTP server"
  value       = aws_iam_role.transfer_logging_role.name
  
}

output "partner_policy" {
  description = "IAM policy for SFTP server access"
  value       = [for policy in aws_iam_policy.partner_policies: policy.arn]
}