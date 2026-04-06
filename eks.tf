# ---------------------------------------------------------------------------
# eks.tf — EKS cluster and managed node group
# ---------------------------------------------------------------------------
# Creates an EKS cluster with a single t3.small SPOT node in private
# subnets. Nodes have no public IPs and reach the internet via NAT Gateway.
#
# Cost notes:
#   - t3.small on-demand: ~$0.026/hr (~$19/month) in ap-southeast-2
#   - t3.small spot:      ~$0.008/hr (~$6/month)  — saves ~60-70%
#   - Spot instances can be interrupted with 2 min warning, which is fine
#     for a learning project. The triage agent is short-lived anyway.
#   - CloudWatch control-plane logs are disabled to save on log costs.
#   - Remember to `terraform destroy` when not actively using the cluster!
# ---------------------------------------------------------------------------

# ---- EKS Cluster ---------------------------------------------------------

resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-cluster"
  version  = var.kubernetes_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    # Place the cluster ENIs in PRIVATE subnets. These are the network
    # interfaces that the EKS control plane uses to communicate with
    # worker nodes. Since nodes are also in private subnets, all
    # control-plane-to-node traffic stays within the VPC.
    subnet_ids = [
      aws_subnet.private_a.id,
      aws_subnet.private_b.id,
    ]

    # Attach our custom security group (EKS also creates its own).
    security_group_ids = [aws_security_group.eks_cluster.id]

    # PUBLIC endpoint: allows `kubectl` from local machine or CI.
    # This goes through the EKS-managed API server endpoint on the
    # internet — it does NOT traverse our VPC or subnets. Traffic is
    # authenticated via IAM (aws-iam-authenticator) and encrypted with TLS.
    endpoint_public_access = true

    # PRIVATE endpoint: allows nodes in private subnets to reach the
    # API server internally via the VPC (through ENIs in the private
    # subnets above). Without this, nodes would have to route API calls
    # out through NAT Gateway and back in through the public endpoint,
    # which is slower and costs money for NAT data processing.
    endpoint_private_access = true
  }

  # CloudWatch control-plane logs are disabled to save on costs.
  # Re-enable ["audit", "api"] if you need to debug cluster-level issues.

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
# (kube-proxy, CoreDNS, VPC CNI). Min/max/desired are all 1 to prevent
# autoscaling surprises.
#
# Nodes run in PRIVATE subnets — they have no public IPs and cannot be
# reached directly from the internet. They reach the internet (for pulling
# images, etc.) via the NAT Gateway in the public subnet.

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-nodes"
  node_role_arn   = aws_iam_role.eks_node_group.arn

  # Nodes launch in PRIVATE subnets — no public IPs, no direct internet
  # access. Outbound traffic goes through NAT Gateway.
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id,
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

  # SPOT instances save ~60-70% over on-demand. The trade-off is that AWS
  # can reclaim the instance with 2 minutes notice. This is acceptable for
  # a learning project where the triage agent runs short-lived jobs.
  # If you need guaranteed availability, switch back to "ON_DEMAND".
  capacity_type = "SPOT"

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
