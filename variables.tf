# ---------------------------------------------------------------------------
# variables.tf — Input variables
# ---------------------------------------------------------------------------
# Centralises every tuneable parameter.  Defaults are set so that
# `terraform apply` works without a .tfvars file for the learning project.
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-2"
}

variable "project_name" {
  description = "Short project name used in resource names and tags"
  type        = string
  default     = "eks-sagemaker-triage"
}

variable "account_id" {
  description = "AWS account ID (used where data sources are not available)"
  type        = string
  default     = "208107893626"
}

variable "common_tags" {
  description = "Tags applied to every resource in addition to the provider default_tags"
  type        = map(string)
  default = {
    Project = "eks-sagemaker-triage"
  }
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.31"
}
