# 1. Lấy thông tin LabRole có sẵn nếu chạy trên tài khoản AWS Academy Lab
data "aws_iam_role" "lab_role" {
  count = var.use-lab-role ? 1 : 0
  name  = "LabRole"
}

# 2. Tạo IAM Role riêng cho EKS nếu chạy trên tài khoản AWS thông thường
resource "aws_iam_role" "eks_cluster_role" {
  count = var.use-lab-role ? 0 : 1
  name  = "${var.cluster-name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  count      = var.use-lab-role ? 0 : 1
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role[0].name
}

resource "aws_iam_role" "eks_node_role" {
  count = var.use-lab-role ? 0 : 1
  name  = "${var.cluster-name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  count      = var.use-lab-role ? 0 : 1
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role[0].name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  count      = var.use-lab-role ? 0 : 1
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role[0].name
}

resource "aws_iam_role_policy_attachment" "eks_ecr_readonly" {
  count      = var.use-lab-role ? 0 : 1
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role[0].name
}

# 3. Khởi tạo EKS Control Plane
resource "aws_eks_cluster" "eks" {
  name     = var.cluster-name
  role_arn = var.use-lab-role ? data.aws_iam_role.lab_role[0].arn : aws_iam_role.eks_cluster_role[0].arn

  vpc_config {
    subnet_ids              = var.subnet-ids
    endpoint_public_access  = true
    endpoint_private_access = true
  }
}

# 4. Khởi tạo EKS Worker Nodes (2 máy t3.medium chạy Java App, Mosquitto & Monitoring)
resource "aws_eks_node_group" "nodes" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "${var.cluster-name}-node-group"
  node_role_arn   = var.use-lab-role ? data.aws_iam_role.lab_role[0].arn : aws_iam_role.eks_node_role[0].arn
  subnet_ids      = var.subnet-ids
  instance_types  = [var.node-instance-type]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  depends_on = [aws_eks_cluster.eks]
}