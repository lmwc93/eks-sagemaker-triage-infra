# ---------------------------------------------------------------------------
# outputs.tf — Useful values printed after `terraform apply`
# ---------------------------------------------------------------------------
# These outputs make it easy to wire up kubectl, push Docker images, and
# reference resources from other tooling (CI, scripts, etc.).
# ---------------------------------------------------------------------------

output "eks_cluster_endpoint" {
  description = "Endpoint URL for the EKS cluster API server"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_certificate_authority" {
  description = "Base64-encoded certificate authority data for the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "ecr_repository_url" {
  description = "URL of the ECR repository for the triage agent image"
  value       = aws_ecr_repository.triage_agent.repository_url
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "subnet_ids" {
  description = "IDs of the public subnets"
  value = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id,
  ]
}

output "kubeconfig_update_command" {
  description = "Run this command to configure kubectl for the cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "triage_agent_pod_role_arn" {
  description = "ARN of the IAM role for the triage agent pod (use in K8s ServiceAccount annotation)"
  value       = aws_iam_role.triage_agent_pod.arn
}

output "dummy_pipeline_name" {
  description = "Name of the dummy SageMaker pipeline (use to trigger test failures)"
  value       = aws_sagemaker_pipeline.dummy_fail.pipeline_name
}
