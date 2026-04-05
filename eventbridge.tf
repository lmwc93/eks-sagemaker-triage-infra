# ---------------------------------------------------------------------------
# eventbridge.tf — EventBridge rule for SageMaker pipeline failures
# ---------------------------------------------------------------------------
# Watches for SageMaker pipeline step failures and routes them to a target.
# The target is currently a CloudWatch log group (placeholder) — it will be
# replaced with a Lambda or direct EKS invocation once the agent is built.
#
# How it works:
#   1. SageMaker emits an event when a pipeline step changes status.
#   2. This rule's event pattern filters for status = "Failed".
#   3. The matched event is forwarded to the target for processing.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "sagemaker_pipeline_failure" {
  name        = "${var.project_name}-pipeline-failure"
  description = "Triggers when a SageMaker pipeline execution step fails"

  # Event pattern docs:
  # https://docs.aws.amazon.com/sagemaker/latest/dg/automating-sagemaker-with-eventbridge.html
  event_pattern = jsonencode({
    source      = ["aws.sagemaker"]
    detail-type = ["SageMaker Model Building Pipeline Execution Step Status Change"]
    detail = {
      currentStepStatus = ["Failed"]
    }
  })

  tags = {
    Name = "${var.project_name}-pipeline-failure-rule"
  }
}

# ---- Placeholder target: CloudWatch Logs ---------------------------------
# Sends matched events to a log group so we can verify the rule fires
# correctly during development.  Replace with Lambda / EKS target later.

resource "aws_cloudwatch_log_group" "eventbridge_target" {
  name              = "/aws/events/${var.project_name}-pipeline-failures"
  retention_in_days = 7 # Short retention — it's just for dev/debugging.

  tags = {
    Name = "${var.project_name}-eventbridge-logs"
  }
}

resource "aws_cloudwatch_event_target" "log_group" {
  rule      = aws_cloudwatch_event_rule.sagemaker_pipeline_failure.name
  target_id = "${var.project_name}-log-target"
  arn       = aws_cloudwatch_log_group.eventbridge_target.arn
}

# EventBridge needs permission to write to the CloudWatch log group.
# This is done via a resource-based policy on the log group.
resource "aws_cloudwatch_log_resource_policy" "eventbridge_logs" {
  policy_name = "${var.project_name}-eventbridge-logs-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EventBridgePutLogs"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.eventbridge_target.arn}:*"
      }
    ]
  })
}
