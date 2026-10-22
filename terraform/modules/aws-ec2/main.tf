# Tự động lấy AMI Ubuntu 22.04 LTS mới nhất trên Region hiện tại
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Nhúng Public Key của nhóm vào AWS, không phụ thuộc vào nút Download PEM của Lab
resource "aws_key_pair" "devops-teams-key" {
  key_name   = "devops-teams-key"
  public_key = file("${path.root}/devops-teams-key.pub")
}

resource "aws_instance" "jenkins_ec2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance-type
  subnet_id              = var.subnet-id
  vpc_security_group_ids = [var.security-group-id]
  key_name               = aws_key_pair.devops-teams-key.key_name
  iam_instance_profile   = var.instance-profile-name

  root_block_device {
    volume_size           = 25
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = var.jenkins-ec2-name
  }
}