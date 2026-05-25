# IAM role that Snowflake assumes to read from S3.

variable "snowflake_aws_iam_user_arn" {
  description = "STORAGE_AWS_IAM_USER_ARN from DESC INTEGRATION s3_crypto_raw"
  type        = string
}

variable "snowflake_external_id" {
  description = "STORAGE_AWS_EXTERNAL_ID from DESC INTEGRATION s3_crypto_raw"
  type        = string
}

data "aws_iam_policy_document" "snowflake_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [var.snowflake_aws_iam_user_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.snowflake_external_id]
    }
  }
}

resource "aws_iam_role" "snowflake_s3_access" {
  name               = "snowflake-s3-access-role"
  assume_role_policy = data.aws_iam_policy_document.snowflake_trust.json
}

data "aws_iam_policy_document" "snowflake_s3_read" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
    ]
    resources = ["${aws_s3_bucket.raw.arn}/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.raw.arn]
  }
}

resource "aws_iam_role_policy" "snowflake_s3_read" {
  name   = "snowflake-s3-read"
  role   = aws_iam_role.snowflake_s3_access.id
  policy = data.aws_iam_policy_document.snowflake_s3_read.json
}

output "snowflake_iam_role_arn" {
  description = "ARN to put in Snowflake STORAGE_AWS_ROLE_ARN"
  value       = aws_iam_role.snowflake_s3_access.arn
}
