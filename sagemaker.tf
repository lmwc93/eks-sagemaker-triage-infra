# ---------------------------------------------------------------------------
# sagemaker.tf — Dummy SageMaker pipeline for testing
# ---------------------------------------------------------------------------
# Creates a minimal SageMaker pipeline with a single FailStep that
# immediately fails when executed.  This lets us trigger the EventBridge
# rule and test the triage agent end-to-end without needing real ML
# training infrastructure.
#
# To trigger a failure:
#   aws sagemaker start-pipeline-execution \
#     --pipeline-name eks-sagemaker-triage-dummy-fail \
#     --region ap-southeast-2
# ---------------------------------------------------------------------------

resource "aws_sagemaker_pipeline" "dummy_fail" {
  pipeline_name         = "${var.project_name}-dummy-fail"
  pipeline_display_name = "Dummy Fail Pipeline (Testing)"
  role_arn              = aws_iam_role.sagemaker_pipeline.arn

  # The pipeline definition is a JSON document following the SageMaker
  # Pipeline Definition JSON Schema.  This one defines a single FailStep
  # that always fails with a descriptive error message.
  pipeline_definition = jsonencode({
    Version    = "2020-12-01"
    Metadata   = {}
    Parameters = []
    Steps = [
      {
        Name = "AlwaysFailStep"
        Type = "Fail"
        Arguments = {
          ErrorMessage = "Intentional failure for triage agent testing. This pipeline is a dummy designed to trigger EventBridge rules."
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-dummy-fail-pipeline"
    Description = "Intentionally-failing pipeline for testing the triage agent"
  }
}
