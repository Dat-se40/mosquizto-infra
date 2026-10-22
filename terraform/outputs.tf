output "jenkins_public_ip" {
  description = "Public IP của Jenkins EC2 (Gửi cho Thành viên 2 chạy Ansible)"
  value       = module.ec2.public_ip
}

output "jenkins_public_dns" {
  description = "Public DNS của Jenkins EC2"
  value       = module.ec2.public_dns
}

output "jenkins_instance_id" {
  description = "Instance ID của Jenkins EC2"
  value       = module.ec2.instance_id
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Danh sách Public Subnet IDs (AZ1 & AZ2)"
  value       = module.vpc.public_subnet_ids
}

output "security_group_id" {
  description = "Security Group ID của Jenkins EC2"
  value       = module.security-group.security_group_id
}

output "eks_cluster_name" {
  description = "Tên cụm EKS"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "API Server Endpoint của cụm EKS"
  value       = module.eks.cluster_endpoint
}

output "eks_kubeconfig_command" {
  description = "Lệnh kết nối kubectl vào cụm EKS (Gửi cho nhóm)"
  value       = "aws eks update-kubeconfig --region ${var.AWS-REGION} --name ${module.eks.cluster_name}"
}