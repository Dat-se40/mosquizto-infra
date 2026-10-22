module "vpc" {
  source = "./modules/aws-vpc"

  vpc-name         = var.VPC-NAME
  vpc-cidr         = var.VPC-CIDR
  igw-name         = var.IGW-NAME
  public-cidr1     = var.PUBLIC-CIDR1
  public-subnet1   = var.PUBLIC-SUBNET1
  public-cidr2     = var.PUBLIC-CIDR2
  public-subnet2   = var.PUBLIC-SUBNET2
  public-rt-name1  = var.PUBLIC-RT-NAME1
  eks-cluster-name = var.EKS-CLUSTER-NAME
}

module "security-group" {
  source = "./modules/security-group"

  vpc-id                = module.vpc.vpc_id
  web-sg-name           = var.WEB-SG-NAME
  allowed-ssh-cidrs     = var.ALLOWED-SSH-CIDRS
  allowed-jenkins-cidrs = var.ALLOWED-JENKINS-CIDRS

  depends_on = [module.vpc]
}

module "iam" {
  source = "./modules/aws-iam"

  iam-role              = var.IAM-ROLE
  iam-policy            = var.IAM-POLICY
  instance-profile-name = var.INSTANCE-PROFILE-NAME
  use-lab-role          = var.USE-LAB-ROLE
}

module "ec2" {
  source = "./modules/aws-ec2"

  jenkins-ec2-name      = var.JENKINS-EC2-NAME
  instance-type         = var.INSTANCE-TYPE
  key-name              = var.KEY-NAME
  subnet-id             = module.vpc.public_subnet_id
  security-group-id     = module.security-group.security_group_id
  instance-profile-name = module.iam.instance_profile_name

  depends_on = [module.vpc, module.security-group, module.iam]
}

module "eks" {
  source = "./modules/aws-eks"

  cluster-name       = var.EKS-CLUSTER-NAME
  subnet-ids         = module.vpc.public_subnet_ids
  node-instance-type = var.EKS-NODE-INSTANCE-TYPE
  use-lab-role       = var.USE-LAB-ROLE

  depends_on = [module.vpc]
}