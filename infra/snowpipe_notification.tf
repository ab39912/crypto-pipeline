# S3 → SQS notification so Snowpipe auto-ingests new files.

variable "snowpipe_sqs_arn" {
  description = "SQS queue ARN from SHOW PIPES (notification_channel)"
  type        = string
}

resource "aws_s3_bucket_notification" "snowpipe_trigger" {
  bucket = aws_s3_bucket.raw.id

  queue {
    queue_arn     = var.snowpipe_sqs_arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "raw/"
    filter_suffix = ".jsonl"
  }
}
