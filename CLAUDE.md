Personal learning project: Terraform infrastructure for an EKS-based medical triage pipeline on AWS.

## Key commands
- `terraform init` — initialise providers and backend
- `terraform plan` — preview changes
- `terraform apply` — create/update infrastructure
- `terraform destroy` — tear everything down (runs automatically on /exit)

## Architecture
EKS cluster + EventBridge + SageMaker + Bedrock (Kimi K2.5) in ap-southeast-2.

## State
S3 backend: `eks-sagemaker-triage-tfstate-208107893626` (ap-southeast-2).

## CI/CD
GitHub Actions runs `terraform plan` on PRs and `terraform apply` on merge to main.
Auth via OIDC federation — no long-lived AWS credentials stored in GitHub.
