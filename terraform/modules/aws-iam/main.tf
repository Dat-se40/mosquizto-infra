# Khi chạy trên AWS Classroom Lab (use-lab-role = true), sử dụng LabInstanceProfile có sẵn
# Khi chạy trên AWS cá nhân (use-lab-role = false), tự tạo IAM Role kèm quyền ECR + EKS + SSM

resource "aws_iam_role" "iam_role" {
  count = var.use-lab-role ? 0 : 1
  name  = var.iam-role

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "iam_policy" {
  count       = var.use-lab-role ? 0 : 1
  name        = var.iam-policy
  description = "IAM Policy for Jenkins EC2 (SSM, ECR, EKS)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:*",
          "ssmmessages:*",
          "ec2messages:*",
          "ecr:*",
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "policy_attach" {
  count      = var.use-lab-role ? 0 : 1
  role       = aws_iam_role.iam_role[0].name
  policy_arn = aws_iam_policy.iam_policy[0].arn
}

resource "aws_iam_instance_profile" "instance_profile" {
  count = var.use-lab-role ? 0 : 1
  name  = var.instance-profile-name
  role  = aws_iam_role.iam_role[0].name
}