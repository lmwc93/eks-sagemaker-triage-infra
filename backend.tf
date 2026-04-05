# ---------------------------------------------------------------------------
# backend.tf — Remote state configuration
# ---------------------------------------------------------------------------
# Stores Terraform state in S3 with DynamoDB-based locking so that
# concurrent applies are prevented.  The bucket and table were created
# out-of-band (bootstrap step) before any `terraform init`.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket         = "eks-sagemaker-triage-tfstate-208107893626"
    key            = "infra/terraform.tfstate"
    region         = "ap-southeast-2"
    dynamodb_table = "eks-sagemaker-triage-tflock"
    encrypt        = true
  }
}
