terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "4.11.0"
    }
    github = {
      source = "integrations/github"
      version = "4.23.0"
    }
  }
}

provider "aws" {
  # Configuration options
  region = "us-east-1"
}

provider "github" {
  # Configuration options
    token = file("~/.ssh/bronze-github-token.txt")

}

resource "github_repository" "myrepo" {
  name = "Bookstore-App-AWS-Dockerization-API-Python-Mysql"
  auto_init = true
  visibility = "public"
}

resource "github_branch_default" "main" {
  branch = "main"
  repository = github_repository.myrepo.name
}

variable "files" {
  default = ["bookstore-api.py", "requirements.txt", "Dockerfile", "docker-compose.yml"]
}

resource "github_repository_file" "gitrepo-files" {
  for_each = toset(var.files)
  content = file(each.value) #PWD file name (FROM)
  file = each.value #Repo file name (TO)
  repository = github_repository.myrepo.name
  branch = "main"
  commit_message = "Generated by terraform"
  overwrite_on_create = true
}

resource "aws_instance" "tf-docker-ec2" {
  ami = "ami-0f9fc25dd2506cf6d" #Amazon Linux 2 AMI
  instance_type = "t2.micro"
  key_name = "mat-ec2-key"
  security_groups = ["docker-sec-group"]
  tags = {
    Name = "Web Server of Bookstore"
  }

  user_data = <<-EOF
          #! /bin/bash
          yum update -y
          amazon-linux-extras install docker -y
          systemctl start docker
          systemctl enable docker
          usermod -a -G docker ec2-user

          curl -L "https://github.com/docker/compose/releases/download/1.26.2/docker-compose-$(uname -s)-$(uname -m)" \
          -o /usr/local/bin/docker-compose
          chmod +x /usr/local/bin/docker-compose
          mkdir -p /home/ec2-user/bookstore-api

          # Copy github repo files one by one
          FOLDER="https://raw.githubusercontent.com/tunckasik/Bookstore-App-AWS-Dockerization-API-Python-Mysql/main/"
          curl -s --create-dirs -o "/home/ec2-user/bookstore-api/bookstore-api.py" -L "$FOLDER"bookstore-api.py
          curl -s --create-dirs -o "/home/ec2-user/bookstore-api/requirements.txt" -L "$FOLDER"requirements.txt
          curl -s --create-dirs -o "/home/ec2-user/bookstore-api/Dockerfile" -L "$FOLDER"Dockerfile
          curl -s --create-dirs -o "/home/ec2-user/bookstore-api/docker-compose.yml" -L "$FOLDER"docker-compose.yml
          cd /home/ec2-user/bookstore-api

          # Create a custom image
          docker build -t bookstore-app:latest .
          docker-compose up -d
          EOF

  depends_on = [github_repository.myrepo, github_repository_file.gitrepo-files]

}
resource "aws_security_group" "tf-docker-sec-gr" {
  name = "docker-sec-group"
  tags = {
    Name = "docker-sec-gr"
  }
  ingress {
    from_port = 80
    protocol = "tcp"
    to_port = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 22
    protocol = "tcp"
    to_port = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "website" {
  value = "http://${aws_instance.tf-docker-ec2.public_dns}"
}