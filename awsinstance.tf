terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amzn_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# VPC
resource "aws_vpc" "example" {
  cidr_block = "172.16.0.0/16"

  tags = {
    Name = "example-vpc"
  }
}

# Public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "172.16.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "eu-north-1b"

  tags = {
    Name = "public-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "example-igw"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "public-rt"
  }
}

# Route Table Association
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "allow_web" {
  name        = "allow_web"
  description = "Allow HTTP HTTPS SSH"
  vpc_id      = aws_vpc.example.id

  tags = {
    Name = "allow-web-sg"
  }
}

# HTTP
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# HTTPS
resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# SSH
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

# Outbound
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.allow_web.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# EC2 instance
resource "aws_instance" "example" {
  ami                    = data.aws_ami.amzn_linux_2023.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.allow_web.id]

  key_name = "ec2-key"

  user_data = templatefile("start.sh", {
    connection_string = var.connection_string
    grafana_password  = var.grafana_password
    grafana_user      = var.grafana_user
    noip_email        = var.noip_email
    noip_password     = var.noip_password
    domain_name       = var.domain_name
    certbot_email     = var.certbot_email
  })

  tags = {
    Name = "hello"
  }
}

# Outputs
output "instance_ip" {
  value = aws_instance.example.public_ip
}

output "ssh_command" {
  value = "ssh -i ec2-key.pem ec2-user@${aws_instance.example.public_ip}"
}

output "app_url" {
  value = "http://${var.domain_name}"
}

output "grafana_url" {
  value = "http://${var.domain_name}/grafana/"
}

output "prometheus_url" {
  value = "http://${var.domain_name}/prometheus/"
}

output "script_running_live" {
  value = "sudo tail -f /var/log/cloud-init-output.log"
}
