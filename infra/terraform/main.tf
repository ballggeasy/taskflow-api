terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state in an S3-compatible bucket (LocalStack). State is never committed.
  backend "s3" {
    bucket                      = "taskflow-tfstate"
    key                         = "taskflow/terraform.tfstate"
    region                      = "us-east-1"
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    endpoints = {
      s3 = "http://localstack:4566"
    }
  }
}

variable "allowed_cidr" {
  type        = string
  description = "Private network allowed to reach taskflow-api (never 0.0.0.0/0)"
  default     = "10.0.0.0/8"
}

variable "localstack_endpoint" {
  type    = string
  default = "http://localstack:4566"
}

# Credentials come from AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY in the environment.
provider "aws" {
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    ec2 = var.localstack_endpoint
    s3  = var.localstack_endpoint
  }
}

resource "aws_security_group" "taskflow" {
  name        = "taskflow-sg"
  description = "Allow taskflow-api traffic on 8080"

  ingress {
    description = "taskflow-api from the private network"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    description = "outbound to the private network only"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.allowed_cidr]
  }
}

resource "aws_instance" "taskflow" {
  #checkov:skip=CKV2_AWS_41:no AWS API access is needed by this lab instance, so no IAM role is attached
  #checkov:skip=CKV_AWS_126:LocalStack does not implement MonitorInstances (returns 501); enable detailed monitoring on real AWS
  ami                    = "ami-03cf127a"
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.taskflow.id]
  ebs_optimized          = true
  monitoring             = false

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted   = true
    volume_size = 8
  }

  # LocalStack accepts these at creation but returns 501 for the follow-up ModifyInstance*
  # calls, which would show up as perpetual drift. Not needed on real AWS.
  lifecycle {
    ignore_changes = [metadata_options, monitoring]
  }

  tags = {
    Name = "taskflow-host"
  }
}

output "instance_address" {
  description = "Address of the taskflow instance"
  value       = aws_instance.taskflow.private_ip
}

output "instance_name" {
  value = aws_instance.taskflow.tags["Name"]
}
