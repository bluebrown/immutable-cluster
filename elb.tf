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
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}