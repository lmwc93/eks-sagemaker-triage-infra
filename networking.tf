# ---------------------------------------------------------------------------
# networking.tf — VPC, subnets, routing, and security groups
# ---------------------------------------------------------------------------
# Creates a minimal VPC with PUBLIC subnets only (no NAT gateway) to keep
# costs at zero for this learning project.  EKS nodes sit in public subnets
# and get public IPs so they can pull container images and reach the
# Kubernetes API server.
# ---------------------------------------------------------------------------

# ---- VPC -----------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ---- Public subnets (one per AZ) ----------------------------------------
# EKS requires subnets in at least 2 AZs.  We use /24 blocks which give
# 251 usable IPs each — more than enough for a single-node cluster.

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-southeast-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-a"
    # These tags tell the AWS Load Balancer Controller which subnets to use
    # for internet-facing load balancers (not needed yet, but good practice).
    "kubernetes.io/role/elb"                            = "1"
    "kubernetes.io/cluster/${var.project_name}-cluster" = "shared"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-southeast-2b"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-b"
    "kubernetes.io/role/elb"                            = "1"
    "kubernetes.io/cluster/${var.project_name}-cluster" = "shared"
  }
}

# ---- Internet gateway ----------------------------------------------------
# Allows outbound internet access from the public subnets.

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ---- Route table for public subnets -------------------------------------
# A single route table shared by both public subnets with a default route
# pointing to the internet gateway.

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# ---- Security group for EKS cluster -------------------------------------
# Controls traffic to the EKS control plane.  The managed node group gets
# its own security group automatically, but this one is explicitly attached
# to the cluster so we can add custom rules later (e.g. restricting API
# access to specific IPs).

resource "aws_security_group" "eks_cluster" {
  name        = "${var.project_name}-eks-cluster-sg"
  description = "Security group for the EKS cluster control plane"
  vpc_id      = aws_vpc.main.id

  # Allow all outbound — the control plane needs to talk to nodes, ECR, etc.
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-eks-cluster-sg"
  }
}
