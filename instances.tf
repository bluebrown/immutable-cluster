resource "aws_instance" "web_a" {
  ami           = var.ami_id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.a.id
  security_groups = [
    aws_default_security_group.internal.id,
    aws_security_group.web.id
  ]
  tags = {
    Name = "nginx a"
  }
}

resource "aws_instance" "web_b" {
  ami           = var.ami_id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.b.id
  security_groups = [
    aws_default_security_group.internal.id,
    aws_security_group.web.id
  ]
  tags = {
    Name = "nginx b"
  }
}
