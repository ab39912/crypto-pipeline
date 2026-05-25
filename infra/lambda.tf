resource "null_resource" "build_lambda_zip" {
  triggers = {
    binance_py        = filesha256("${path.module}/../ingestion/binance.py")
    coinbase_py       = filesha256("${path.module}/../ingestion/coinbase.py")
    s3_writer_py      = filesha256("${path.module}/../ingestion/s3_writer.py")
    lambda_handler_py = filesha256("${path.module}/../ingestion/lambda_handler.py")
    init_py           = filesha256("${path.module}/../ingestion/__init__.py")
  }

  provisioner "local-exec" {
    command     = "${path.module}/build_lambda.sh"
    working_dir = path.module
  }
}

locals {
  lambda_zip = "${path.module}/.terraform-tmp/ingestion.zip"
}

# ============================================================================
# Lambda functions for scheduled API ingestion
# ============================================================================

# --- Shared IAM role for both Lambdas ---
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ingestion_lambda" {
  name               = "crypto-pipeline-ingestion-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Write to S3 raw bucket
data "aws_iam_policy_document" "lambda_s3_write" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:PutObjectAcl"]
    resources = ["${aws_s3_bucket.raw.arn}/raw/*"]
  }
}

resource "aws_iam_role_policy" "lambda_s3_write" {
  name   = "s3-write"
  role   = aws_iam_role.ingestion_lambda.id
  policy = data.aws_iam_policy_document.lambda_s3_write.json
}

# CloudWatch Logs (basic execution permissions)
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.ingestion_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --- Package the ingestion code as a zip ---

# --- Lambda layer with requests library ---
# AWS doesn't include `requests` in the Python runtime, so we use a public layer

# --- Binance Lambda ---
resource "aws_lambda_function" "binance_ingestion" {
  function_name    = "crypto-pipeline-binance-ingestion"
  role             = aws_iam_role.ingestion_lambda.arn
  runtime          = "python3.11"
  handler          = "ingestion.lambda_handler.binance_handler"
  filename         = local.lambda_zip
  source_code_hash = filebase64sha256(local.lambda_zip)
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      RAW_BUCKET = aws_s3_bucket.raw.id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.binance_lambda,
  ]
}

resource "aws_cloudwatch_log_group" "binance_lambda" {
  name              = "/aws/lambda/crypto-pipeline-binance-ingestion"
  retention_in_days = 7
}

# --- Coinbase Lambda ---
resource "aws_lambda_function" "coinbase_ingestion" {
  function_name    = "crypto-pipeline-coinbase-ingestion"
  role             = aws_iam_role.ingestion_lambda.arn
  runtime          = "python3.11"
  handler          = "ingestion.lambda_handler.coinbase_handler"
  filename         = local.lambda_zip
  source_code_hash = filebase64sha256(local.lambda_zip)
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      RAW_BUCKET = aws_s3_bucket.raw.id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.coinbase_lambda,
  ]
}

resource "aws_cloudwatch_log_group" "coinbase_lambda" {
  name              = "/aws/lambda/crypto-pipeline-coinbase-ingestion"
  retention_in_days = 7
}

# --- EventBridge schedules ---
resource "aws_cloudwatch_event_rule" "binance_schedule" {
  name                = "crypto-pipeline-binance-schedule"
  description         = "Trigger Binance ingestion every 5 minutes"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "binance_target" {
  rule = aws_cloudwatch_event_rule.binance_schedule.name
  arn  = aws_lambda_function.binance_ingestion.arn
}

resource "aws_lambda_permission" "binance_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.binance_ingestion.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.binance_schedule.arn
}

# Coinbase runs on its own 5-min cycle (no built-in offset, but they won't perfectly align)
resource "aws_cloudwatch_event_rule" "coinbase_schedule" {
  name                = "crypto-pipeline-coinbase-schedule"
  description         = "Trigger Coinbase ingestion every 5 minutes"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "coinbase_target" {
  rule = aws_cloudwatch_event_rule.coinbase_schedule.name
  arn  = aws_lambda_function.coinbase_ingestion.arn
}

resource "aws_lambda_permission" "coinbase_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.coinbase_ingestion.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.coinbase_schedule.arn
}

# --- Outputs ---
output "binance_lambda_name" {
  value = aws_lambda_function.binance_ingestion.function_name
}

output "coinbase_lambda_name" {
  value = aws_lambda_function.coinbase_ingestion.function_name
}
