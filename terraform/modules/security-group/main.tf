resource "aws_security_group" "jenkins_sg" {
  name        = var.web-sg-name
  description = "Security Group for Jenkins, Monitoring, Java App & Mosquitto"
  vpc_id      = var.vpc-id

  # 1. SSH port 22: chỉ cho phép IP nhóm
  ingress {
    description = "SSH from Team IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed-ssh-cidrs
  }

  # 2. Jenkins port 8080: chỉ cho phép IP nhóm
  ingress {
    description = "Jenkins UI from Team IPs"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed-jenkins-cidrs
  }

  # 3. Monitoring Ports cho Thành viên 2 (Grafana: 3000, Prometheus: 9090, Node Exporter: 9100)
  ingress {
    description = "Grafana Dashboard"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = var.allowed-jenkins-cidrs
  }

  ingress {
    description = "Prometheus UI"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = var.allowed-jenkins-cidrs
  }

  ingress {
    description = "Node Exporter Metrics"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = var.allowed-jenkins-cidrs
  }

  # 4. Application Ports (Java Backend: 8000, HTTP: 80, HTTPS: 443)
  ingress {
    description = "Java App Port 8000"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS access"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 5. Mosquitto MQTT Broker Ports (1883: MQTT TCP, 9001: MQTT WebSockets)
  ingress {
    description = "Mosquitto MQTT TCP"
    from_port   = 1883
    to_port     = 1883
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Mosquitto MQTT WebSockets"
    from_port   = 9001
    to_port     = 9001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = var.web-sg-name
  }
}