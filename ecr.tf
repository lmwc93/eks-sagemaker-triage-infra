# ---------------------------------------------------------------------------
# ecr.tf — Elastic Container Registry for the triage agent image
# ---------------------------------------------------------------------------
# Stores the Docker image for the triage agent that runs on EKS.
# Mutable tags are enabled for dev convenience (so we can push :latest
# repeatedly).  A lifecycle policy keeps only the 5 most recent images
# to save on storage costs.
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "triage_agent" {
  name                 = "${var.project_name}/triage-agent"
  image_tag_mutability = "MUTABLE"

  # Scan every pushed image for known CVEs.
  image_scanning_configuration {
    scan_on_push = true
  }

  # AES-256 encryption (default, no extra cost).
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${var.project_name}-triage-agent"
  }
}

# Lifecycle policy: keep only the 5 most recent images.
# This prevents unbounded storage growth during development.
resource "aws_ecr_lifecycle_policy" "triage_agent" {
  repository = aws_ecr_repository.triage_agent.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the last 5 images (cost saving)"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
