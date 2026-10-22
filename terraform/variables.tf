variable "AWS-REGION" {
  description = "AWS Region triển khai hạ tầng"
  type        = string
  default     = "us-east-1"
}

variable "USE-LAB-ROLE" {
  description = "Đặt true nếu chạy trên AWS Academy Lab (dùng LabRole), false nếu dùng tài khoản AWS thường"
  type        = bool
  default     = true
}

# --- VPC ---
variable "VPC-NAME" { type = string }
variable "VPC-CIDR" { type = string }
variable "IGW-NAME" { type = string }
variable "PUBLIC-CIDR1" { type = string }
variable "PUBLIC-SUBNET1" { type = string }
variable "PUBLIC-CIDR2" { type = string }
variable "PUBLIC-SUBNET2" { type = string }
variable "PUBLIC-RT-NAME1" { type = string }

# --- SECURITY GROUP ---
variable "WEB-SG-NAME" { type = string }
variable "ALLOWED-SSH-CIDRS" { type = list(string) }
variable "ALLOWED-JENKINS-CIDRS" { type = list(string) }

# --- IAM ---
variable "IAM-ROLE" { type = string }
variable "IAM-POLICY" { type = string }
variable "INSTANCE-PROFILE-NAME" { type = string }

# --- EC2 JENKINS ---
variable "JENKINS-EC2-NAME" {
  type    = string
  default = "Project11-Jenkins-EC2"
}
variable "INSTANCE-TYPE" {
  type    = string
  default = "t3.medium"
}
variable "KEY-NAME" {
  description = "Tên SSH Key Pair trên AWS (mặc định trên AWS Lab là vockey)"
  type        = string
}

# --- EKS CLUSTER ---
variable "EKS-CLUSTER-NAME" {
  description = "Tên cụm EKS chạy Java App và Mosquitto"
  type        = string
  default     = "project11-eks-cluster"
}
variable "EKS-NODE-INSTANCE-TYPE" {
  type    = string
  default = "t3.medium"
}