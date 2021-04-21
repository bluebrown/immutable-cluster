resource "aws_vpc" "packer" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "packer"
    Description = "vpc with 2 public subnets in 2 availability zones and auto scaling group using an application loadbalancer and custom AMI"
  }

}

resource "aws_internet_gateway" "inet" {
  vpc_id = aws_vpc.packer.id
  tags = {
    Name = "packer internet gateway"
  }
}

resource "aws_default_route_table" "public" {
  default_route_table_id = aws_vpc.packer.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.inet.id
  }

  tags = {
    Name = "public route table"
  }
}

resource "aws_subnet" "a" {
  vpc_id            = aws_vpc.packer.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = "eu-central-1a"

  tags = {
    Name = "public subnet a"
  }

  map_public_ip_on_launch = true
}

resource "aws_subnet" "b" {
  vpc_id            = aws_vpc.packer.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-central-1b"


  tags = {
    Name = "public subnet b"
  }

  map_public_ip_on_launch = true
}
