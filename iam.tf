# ---------------------------------------------------------------------------
# iam.tf — IAM roles and policies
# ---------------------------------------------------------------------------
# Every AWS service that this project uses needs an IAM role.  This file
# keeps them all in one place so the permission model is easy to audit.
# ---------------------------------------------------------------------------

# ===========================================================================
# 1. EKS CLUSTER ROLE
# ===========================================================================
# The EKS service itself needs a role to manage networking and compute on
# our behalf.  AmazonEKSClusterPolicy is the AWS-managed policy that
# grants exactly the permissions EKS requires.

resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-eks-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ===========================================================================
# 2. EKS NODE GROUP ROLE
# ===========================================================================
# Worker nodes need permissions to join the cluster, pull images from ECR,
# and manage ENIs for pod networking (VPC CNI plugin).

resource "aws_iam_role" "eks_node_group" {
  name = "${var.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-eks-node-role"
  }
}

# AmazonEKSWorkerNodePolicy — lets the node register with the cluster.
resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  role       = aws_iam_role.eks_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# AmazonEKS_CNI_Policy — lets the VPC CNI plugin manage ENIs for pod IPs.
resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.eks_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# AmazonEC2ContainerRegistryReadOnly — lets nodes pull images from ECR.
resource "aws_iam_role_policy_attachment" "eks_ecr_read" {
  role       = aws_iam_role.eks_node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ===========================================================================
# 3. TRIAGE AGENT POD ROLE (IRSA — IAM Roles for Service Accounts)
# ===========================================================================
# The triage agent pod needs to call Bedrock, read SageMaker pipeline info,
# and fetch a GitHub token from Secrets Manager.  We use IRSA so that ONLY
# pods with the matching Kubernetes service account get these permissions.
#
# NOTE: The OIDC provider is created after the cluster, so we reference it
# via the EKS cluster's OIDC issuer.  The trust policy restricts assumption
# to the "triage-agent" service account in the "default" namespace.

# Fetch the TLS certificate from the EKS OIDC issuer so we can compute
# the thumbprint dynamically. This avoids hardcoding a thumbprint that
# could change when AWS rotates certificates.
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# The OIDC provider for the EKS cluster — enables IRSA.
# The thumbprint is computed dynamically from the TLS certificate above
# instead of being hardcoded.
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name = "${var.project_name}-eks-oidc"
  }
}

resource "aws_iam_role" "triage_agent_pod" {
  name = "${var.project_name}-triage-agent-pod-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:default:triage-agent"
            "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-triage-agent-pod-role"
  }
}

# Inline policy: Bedrock — invoke the Kimi K2.5 model for triage analysis.
resource "aws_iam_role_policy" "triage_agent_bedrock" {
  name = "bedrock-invoke"
  role = aws_iam_role.triage_agent_pod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeBedrockModel"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        # Scoped to the specific model we use for triage.
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/moonshotai.kimi-k2.5"
      }
    ]
  })
}

# Inline policy: SageMaker — read pipeline execution details and step logs.
resource "aws_iam_role_policy" "triage_agent_sagemaker" {
  name = "sagemaker-read"
  role = aws_iam_role.triage_agent_pod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SageMakerReadPipelines"
        Effect = "Allow"
        Action = [
          "sagemaker:DescribePipeline",
          "sagemaker:DescribePipelineExecution",
          "sagemaker:DescribePipelineDefinitionForExecution",
          "sagemaker:ListPipelineExecutionSteps",
          "sagemaker:ListPipelineExecutions"
        ]
        Resource = [
          "arn:aws:sagemaker:${var.aws_region}:${data.aws_caller_identity.current.account_id}:pipeline/*",
          "arn:aws:sagemaker:${var.aws_region}:${data.aws_caller_identity.current.account_id}:pipeline/*/execution/*"
        ]
      },
      {
        Sid    = "SageMakerReadLogs"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/sagemaker/*"
      }
    ]
  })
}

# Inline policy: Secrets Manager — read the GitHub PAT used to create PRs.
resource "aws_iam_role_policy" "triage_agent_secrets" {
  name = "secrets-read"
  role = aws_iam_role.triage_agent_pod.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadGitHubToken"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        # Scoped to secrets prefixed with the project name.
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/*"
      }
    ]
  })
}

# ===========================================================================
# 4. SAGEMAKER PIPELINE EXECUTION ROLE
# ===========================================================================
# The dummy SageMaker pipeline needs a role to execute.  We give it minimal
# permissions — just enough to run a pipeline step and write logs.

resource "aws_iam_role" "sagemaker_pipeline" {
  name = "${var.project_name}-sagemaker-pipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-sagemaker-pipeline-role"
  }
}

# Minimal SageMaker permissions for pipeline execution.
resource "aws_iam_role_policy" "sagemaker_pipeline_exec" {
  name = "sagemaker-pipeline-exec"
  role = aws_iam_role.sagemaker_pipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SageMakerPipelineExec"
        Effect = "Allow"
        Action = [
          "sagemaker:CreatePipeline",
          "sagemaker:DescribePipeline",
          "sagemaker:StartPipelineExecution",
          "sagemaker:DescribePipelineExecution",
          "sagemaker:ListPipelineExecutionSteps",
          "sagemaker:AddTags"
        ]
        Resource = [
          "arn:aws:sagemaker:${var.aws_region}:${data.aws_caller_identity.current.account_id}:pipeline/${var.project_name}-*",
          "arn:aws:sagemaker:${var.aws_region}:${data.aws_caller_identity.current.account_id}:pipeline/${var.project_name}-*/execution/*"
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/sagemaker/*"
      },
      {
        Sid    = "PassRoleToSelf"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-sagemaker-pipeline-role"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "sagemaker.amazonaws.com"
          }
        }
      }
    ]
  })
}

# ===========================================================================
# 5. EVENTBRIDGE TARGET ROLE (STUB)
# ===========================================================================
# EventBridge needs a role to invoke the target (Lambda, EKS, etc.).
# The actual permissions will be added once we decide on the invocation
# method.  For now it's an empty role that EventBridge can assume.

resource "aws_iam_role" "eventbridge_target" {
  name = "${var.project_name}-eventbridge-target-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-eventbridge-target-role"
  }
}

# Placeholder policy — will be replaced when we wire up the actual target.
resource "aws_iam_role_policy" "eventbridge_target_stub" {
  name = "stub-placeholder"
  role = aws_iam_role.eventbridge_target.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Placeholder"
        Effect   = "Allow"
        Action   = "logs:PutLogEvents"
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/events/${var.project_name}*"
      }
    ]
  })
}
