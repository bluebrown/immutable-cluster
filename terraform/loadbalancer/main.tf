variable "aws_access_key" {
  sensitive = true
}
variable "aws_secret_key" {
  sensitive = true
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region     = "eu-central-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}


resource "aws_lb" "tcp_lb" {
  name               = "packer-nginx"
  internal           = false
  load_balancer_type = "network"
  subnets            = [aws_subnet.a.id, aws_subnet.b.id]
  tags = {
    Environment = "public tcp loadbalancer"
  }
}

resource "aws_lb_target_group" "nginx" {
  name     = "nginx-web"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.packer.id
}

resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.tcp_lb.arn
  port              = "80"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx.arn
  }
}

resource "aws_lb_target_group_attachment" "nginx_a" {
  target_group_arn = aws_lb_target_group.nginx.arn
  target_id        = aws_instance.web_a.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "nginx_b" {
  target_group_arn = aws_lb_target_group.nginx.arn
  target_id        = aws_instance.web_b.id
  port             = 80
}
