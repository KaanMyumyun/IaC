# Hospital Backend Infrastructure with Terraform

This project provisions an AWS EC2 infrastructure using Terraform and automatically deploys a Dockerized hospital application stack with:

- Backend API
- Frontend UI
- Prometheus
- Grafana
- cAdvisor
- Watchtower
- Nginx reverse proxy
- HTTPS via Certbot
- Dynamic DNS via No-IP

---

## Related Repositories
- [Hospital Management System](https://github.com/KaanMyumyun/HospitalSystem) — The application this infrastructure hosts
- [Grafana Dashboards](https://github.com/KaanMyumyun/grafanadashboards) — Dashboards auto-loaded on provisioning
---

# Architecture

```text
Internet
   │
   ▼
Nginx (EC2)
   ├── /           → Frontend
   ├── /api        → Backend API
   ├── /grafana    → Grafana
   └── /prometheus → Prometheus

Docker Compose Stack
   ├── hospital-backend
   ├── hospital-frontend
   ├── prometheus
   ├── grafana
   ├── cadvisor
   └── watchtower
```

---

# Features

- Infrastructure as Code with Terraform
- Automatic EC2 provisioning
- Public subnet + Internet Gateway
- Security groups for:
  - SSH (22)
  - HTTP (80)
  - HTTPS (443)
- Docker & Docker Compose installation
- Automatic SSL certificates using Certbot
- Dynamic DNS updates with No-IP
- Monitoring stack:
  - Prometheus
  - Grafana
  - cAdvisor
- Automatic container updates with Watchtower

---

# AWS Resources Created

Terraform provisions:

- VPC
- Public Subnet
- Internet Gateway
- Route Table
- Route Table Association
- Security Group
- EC2 Instance

---

# Prerequisites

Before running this project, make sure you have:

- Terraform installed
- AWS CLI configured
- An AWS key pair named:

```bash
ec2-key
```

- A No-IP account
- A domain configured in No-IP
- Docker Hub images:
  - `kstkaan/hospital-backend`
  - `kstkaan/hospital-frontend`

---

# Project Structure

```text
.
├── awsinstance.tf
├── start.sh
├── variables.tf
├── terraform.tfvars
└── README.md
```

---

# Required Variables

Create a `variables.tf` file:

```hcl
variable "connection_string" {
  type = string
}

variable "grafana_password" {
  type      = string
  sensitive = true
}

variable "grafana_user" {
  type = string
}

variable "noip_email" {
  type = string
}

variable "noip_password" {
  type      = string
  sensitive = true
}

variable "domain_name" {
  type = string
}

variable "certbot_email" {
  type = string
}
```

---

# Example terraform.tfvars

```hcl
connection_string = "Server=db;Database=hospital;User Id=sa;Password=StrongPassword123;"
grafana_password  = "admin123"
grafana_user      = "admin"

noip_email        = "your@email.com"
noip_password     = "your-noip-password"

domain_name       = "example.ddns.net"

certbot_email     = "your@email.com"
```

---

# Deploy Infrastructure

Initialize Terraform:

```bash
terraform init
```

Preview changes:

```bash
terraform plan
```

Apply infrastructure:

```bash
terraform apply
```

Terraform outputs:

```bash
instance_ip = "X.X.X.X"
```

---

# Access Services

After deployment:

| Service | URL |
|---|---|
| Frontend | `https://your-domain/` |
| Backend API | `https://your-domain/api/` |
| Grafana | `https://your-domain/grafana/` |
| Prometheus | `https://your-domain/prometheus/` |

---

# SSH Into EC2

```bash
ssh -i ec2-key.pem ec2-user@YOUR_PUBLIC_IP
```

---

# Destroy Infrastructure

To remove everything:

```bash
terraform destroy
```

---

# Security Notes

Current security group configuration allows:

- SSH from anywhere (`0.0.0.0/0`)
- HTTP from anywhere
- HTTPS from anywhere

For production environments, restrict SSH access:

```hcl
cidr_ipv4 = "YOUR_IP/32"
```

---

# Monitoring Stack

## Prometheus

Scrapes metrics from:

- Backend `/metrics`
- cAdvisor
- Prometheus itself

## Grafana

Configured with:

- Persistent storage
- Reverse proxy subpath support

---

# Auto Updates

Watchtower checks for updated Docker images every 5 minutes:

```text
--interval 300
```

and automatically redeploys containers.

---

# SSL Certificates

Certbot automatically:

- Requests Let's Encrypt certificates
- Configures Nginx HTTPS
- Enables automatic renewal

---

# Dynamic DNS

The script installs:

```text
noip2
```

to keep the No-IP domain updated with the EC2 public IP.

---

# Useful Commands

## Check running containers

```bash
docker ps
```

## View logs

```bash
docker logs hospital-backend
```

## Restart stack

```bash
sudo systemctl restart hospital-stack
```

## Check Nginx config

```bash
sudo nginx -t
```

---

# Notes

- Uses Amazon Linux 2023
- Uses Docker Compose v2
- Deploys to AWS region:

```text
eu-north-1
```

- Instance type:

```text
t3.small
```

---

# Future Improvements

- Use Route53 instead of No-IP
- Store secrets in AWS Secrets Manager
- Add RDS PostgreSQL/MySQL
- Add ALB (Application Load Balancer)
- Use ECS or EKS
- Add CI/CD pipeline
- Add Terraform remote state
- Add CloudWatch monitoring
- Restrict SSH access
- Add autoscaling

---

# License

MIT License
