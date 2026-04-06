# ---------------------------------------------------------------------------
# providers.tf — Provider configuration
# ---------------------------------------------------------------------------
# Pins the AWS provider version and sets default tags so every resource
# in the project inherits the Project tag automatically.
# ---------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # The tls provider is used to fetch the EKS OIDC issuer certificate
    # so we can compute the thumbprint dynamically (see iam.tf).
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

# ---------------------------------------------------------------------------
# Data sources used across multiple files
# ---------------------------------------------------------------------------

# Current AWS account ID — avoids hard-coding it in IAM ARNs.
data "aws_caller_identity" "current" {}

# Current region — useful when constructing ARNs.
data "aws_region" "current" {}

# Availability zones we target for subnet placement.
data "aws_availability_zones" "available" {
  state = "available"
}
