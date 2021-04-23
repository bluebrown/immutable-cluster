resource "aws_lb" "web" {
  name               = "packer-nginx"
  internal           = false
  load_balancer_type = "application"
  security_groups = [
    aws_default_security_group.internal.id,
    aws_security_group.web.id,
  ]
  subnets = [
    aws_subnet.a.id,
    aws_subnet.b.id
  ]
  access_logs {
    bucket  = aws_s3_bucket.logs.id
    enabled = true
  }
}

resource "aws_lb_target_group" "web" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.packer.id
}


resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

data "aws_acm_certificate" "mycert" {
  domain   = var.domain
  statuses = ["ISSUED"]
  most_recent = true
}

resource "aws_lb_listener" "websecure" {
  load_balancer_arn = aws_lb.web.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_acm_certificate.mycert.arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
