variable "aws_access_key" {
  sensitive = true
}
variable "aws_secret_key" {
  sensitive = true
}

variable "ami_id" {
  default = "ami-01cce7ac6df33f08e"
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

resource "aws_vpc" "packer" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "packer"
    Description = "sample vpc with 2 public subnets in 2 availability zones and a network loadblancer for high availability"
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

