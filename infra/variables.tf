variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Owner tag for cost tracking"
  type        = string
  default     = "ab39912"
}

variable "bucket_prefix" {
  description = "Prefix for the raw data S3 bucket"
  type        = string
  default     = "crypto-pipeline-raw"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}
