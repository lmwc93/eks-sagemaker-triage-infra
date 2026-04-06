# ---------------------------------------------------------------------------
# networking.tf — VPC, subnets, NAT gateway, routing, and security groups
# ---------------------------------------------------------------------------
# Production-style networking with public and private subnets.
#
# TRAFFIC FLOW:
#   Outbound from EKS nodes (private subnets):
#     Node -> Private subnet route table -> NAT Gateway (in public subnet)
#     -> Internet Gateway -> Internet
#
#   Inbound to EKS API (kubectl from local machine):
#     Internet -> EKS managed public endpoint (not through our VPC)
#
#   Inbound to future load balancers:
#     Internet -> Internet Gateway -> ALB (in public subnets)
#     -> Target pods (in private subnets via VPC networking)
#
# WHY PRIVATE SUBNETS?
#   Nodes in private subnets have no public IPs and cannot be reached
#   directly from the internet. This is a security best practice — the
#   only way in is through a load balancer or the EKS API endpoint.
#   Nodes can still reach the internet (to pull images, etc.) via the
#   NAT Gateway.
#
# COST NOTE:
#   NAT Gateway costs ~$0.059/hr (~$43/month) in ap-southeast-2 plus
#   $0.059/GB for data processed. This is the main ongoing cost of this
#   networking setup. We use a single NAT GW (not one per AZ) to save
#   money — production would use one per AZ for high availability.
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

# ---- Public subnets ------------------------------------------------------
# These subnets have a route to the Internet Gateway, so resources here
# can have public IPs and be reached from the internet.
#
# In our setup, public subnets hold ONLY:
#   1. The NAT Gateway (so private subnets can reach the internet)
#   2. Future load balancers (ALB/NLB for ingress traffic)
#
# EKS nodes do NOT live here — they go in the private subnets below.

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  # No map_public_ip_on_launch — we don't launch instances here.
  # The NAT Gateway gets an Elastic IP explicitly, and load balancers
  # manage their own public IPs.

  tags = {
    Name = "${var.project_name}-public-a"
    # This tag tells the AWS Load Balancer Controller to place
    # internet-facing load balancers in this subnet.
    "kubernetes.io/role/elb"                            = "1"
    "kubernetes.io/cluster/${var.project_name}-cluster" = "shared"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${var.project_name}-public-b"
    "kubernetes.io/role/elb"                            = "1"
    "kubernetes.io/cluster/${var.project_name}-cluster" = "shared"
  }
}

# ---- Private subnets -----------------------------------------------------
# These subnets have NO direct internet access. Outbound traffic goes
# through the NAT Gateway. Inbound traffic from the internet is impossible
# unless routed through a load balancer in the public subnets.
#
# EKS worker nodes run here. They can still:
#   - Pull container images from ECR (via NAT -> internet)
#   - Reach the EKS API server (via private endpoint within the VPC)
#   - Communicate with other AWS services (via NAT or VPC endpoints)

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project_name}-private-a"
    # This tag tells the AWS Load Balancer Controller to place
    # internal (non-internet-facing) load balancers in this subnet.
    "kubernetes.io/role/internal-elb"                   = "1"
    "kubernetes.io/cluster/${var.project_name}-cluster" = "shared"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.20.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${var.project_name}-private-b"
    "kubernetes.io/role/internal-elb"                   = "1"
    "kubernetes.io/cluster/${var.project_name}-cluster" = "shared"
  }
}

# ---- Internet Gateway ----------------------------------------------------
# Allows resources in PUBLIC subnets to reach the internet.
# The NAT Gateway sits in a public subnet and uses this to forward
# traffic from private subnets outbound.

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ---- NAT Gateway ---------------------------------------------------------
# Sits in a PUBLIC subnet and forwards outbound traffic from private
# subnets to the internet. Private subnet resources initiate connections
# to the internet (e.g., pulling Docker images), and the NAT GW
# translates their private IPs to its own Elastic IP.
#
# We only create ONE NAT Gateway (in AZ a) to save cost. If the AZ
# goes down, nodes in AZ b lose internet access. Production would
# create one NAT GW per AZ for high availability.

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }

  # The EIP needs the IGW to exist before it can be associated with
  # a NAT Gateway that routes to the internet.
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id # NAT GW lives in a PUBLIC subnet

  tags = {
    Name = "${var.project_name}-nat-gw"
  }

  # NAT Gateway needs the IGW to route traffic to the internet.
  depends_on = [aws_internet_gateway.main]
}

# ---- Route table for PUBLIC subnets --------------------------------------
# Routes all non-local traffic (0.0.0.0/0) to the Internet Gateway.
# This is what makes these subnets "public" — they can reach the internet
# directly without NAT.

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

# ---- Route table for PRIVATE subnets ------------------------------------
# Routes all non-local traffic (0.0.0.0/0) to the NAT Gateway.
# This is the key difference from public subnets: traffic goes through
# NAT (which does the address translation) instead of directly to the IGW.
#
# Local traffic (10.0.0.0/16) is automatically routed within the VPC
# by an implicit local route that AWS adds to every route table.

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# ---- Security group for EKS cluster -------------------------------------
# Controls traffic to the EKS control plane. The managed node group gets
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
