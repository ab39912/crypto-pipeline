output "raw_bucket_name" {
  description = "Name of the raw data S3 bucket"
  value       = aws_s3_bucket.raw.id
}

output "raw_bucket_arn" {
  description = "ARN of the raw bucket"
  value       = aws_s3_bucket.raw.arn
}

output "aws_region" {
  description = "Deployed region"
  value       = var.aws_region
}
