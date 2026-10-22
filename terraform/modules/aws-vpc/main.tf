data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc-cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = var.vpc-name
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = var.igw-name
  }
}

# Public Subnet 1 (AZ 1 - Ví dụ: us-east-1a)
resource "aws_subnet" "public_subnet1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.public-cidr1
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name                                            = var.public-subnet1
    "kubernetes.io/role/elb"                        = "1"
    "kubernetes.io/cluster/${var.eks-cluster-name}" = "shared"
  }
}

# Public Subnet 2 (AZ 2 - Ví dụ: us-east-1b - Bắt buộc để tạo EKS)
resource "aws_subnet" "public_subnet2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.public-cidr2
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name                                            = var.public-subnet2
    "kubernetes.io/role/elb"                        = "1"
    "kubernetes.io/cluster/${var.eks-cluster-name}" = "shared"
  }
}

resource "aws_route_table" "public_rt1" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = var.public-rt-name1
  }
}

resource "aws_route_table_association" "public_rt_assoc1" {
  subnet_id      = aws_subnet.public_subnet1.id
  route_table_id = aws_route_table.public_rt1.id
}

resource "aws_route_table_association" "public_rt_assoc2" {
  subnet_id      = aws_subnet.public_subnet2.id
  route_table_id = aws_route_table.public_rt1.id
}