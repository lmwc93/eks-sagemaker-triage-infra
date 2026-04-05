# ---------------------------------------------------------------------------
# eks.tf — EKS cluster and managed node group
# ---------------------------------------------------------------------------
# Creates a minimal EKS cluster with a single t3.small node.  This is the
# cheapest viable setup for running the triage agent pod while still using
# a managed node group (so AWS handles node lifecycle for us).
#
# Cost note: t3.small is ~$0.026/hr (~$19/month) in ap-southeast-2.
# Remember to `terraform destroy` when not actively using the cluster!
# ---------------------------------------------------------------------------

# ---- EKS Cluster ---------------------------------------------------------

resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-cluster"
  version  = var.kubernetes_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    # Place the cluster in both public subnets.
    subnet_ids = [
      aws_subnet.public_a.id,
      aws_subnet.public_b.id,
    ]

    # Attach our custom security group (EKS also creates its own).
    security_group_ids = [aws_security_group.eks_cluster.id]

    # Public endpoint so we can `kubectl` from a local machine or CI.
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  # Enable CloudWatch logging for the control plane — useful for debugging
  # cluster-level issues.  Only enable audit + api for cost savings.
  enabled_cluster_log_types = ["audit", "api"]

  tags = {
    Name = "${var.project_name}-cluster"
  }

  # EKS needs the cluster policy attached before it can create the cluster.
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]
}

# ---- Managed Node Group --------------------------------------------------
# A single t3.small node is enough to run the triage agent plus system pods
# (kube-proxy, CoreDNS, VPC CNI).  Min/max/desired are all 1 to prevent
# autoscaling surprises.

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-nodes"
  node_role_arn   = aws_iam_role.eks_node_group.arn

  subnet_ids = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id,
  ]

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  # t3.small: 2 vCPU, 2 GiB RAM — tight but workable for a single agent pod.
  instance_types = ["t3.small"]

  # Use the latest Amazon Linux 2 EKS-optimised AMI (default).
  ami_type = "AL2_x86_64"

  # On-demand (not spot) for simplicity.  Spot would be cheaper but adds
  # complexity around interruptions.
  capacity_type = "ON_DEMAND"

  # Size the root volume modestly.
  disk_size = 20

  tags = {
    Name = "${var.project_name}-node-group"
  }

  # Nodes need all three policies attached before they can join the cluster.
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.eks_ecr_read,
  ]
}
