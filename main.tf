variable "aws_access_key" {
  sensitive = true
}
variable "aws_secret_key" {
  sensitive = true
}

variable "ami_id" {
  default = ""
}

variable "domain" {
  default = ""
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

