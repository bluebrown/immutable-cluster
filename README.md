# Immutable Infrastructure in AWS with Packer, Ansible and Terraform

> Immutable infrastructure is an approach to managing services and software deployments on IT resources wherein components are replaced rather than changed. An application or services is effectively redeployed each time any change occurs.

In this post I am going to show how one can create a workflow based in the idea of immutable infrastructure. You can find the full working code in github <https://github.com/bluebrown/immutable-cluster>.

## The Recipe

Since the goal is to simply replace the instance on each application release, we want to create a machine image containing the application. This way we can swap out the whole instance quickly without further installation steps after provisioning. This is sometimes called a [golden image](https://opensource.com/article/19/7/what-golden-image). We are going to use [Packer](https://www.packer.io/) & [Ansible](https://www.ansible.com/) for this.

Further, we want to manage our infrastructure as code. [Terraform](https://www.terraform.io/) is a good choice for this. It can create, change and destroy infrastructure remotely and keeps track of the current state of our system.

 With a golden image and infrastructure as code, we can throw away the complete environment, in this case the vpc with instances, and create a new one within minutes if we wish. Usually we only want to swap the instances though.

## Prerequisites

To follow along you need:

- an [AWS](https://aws.amazon.com/) account & access tokens
- have [Ansible](https://www.ansible.com/) installed
- have [Packer](https://www.packer.io/) installed
- have [Terraform](https://www.terraform.io/) installed
- have the [AWS CLI](https://aws.amazon.com/cli/) version 2 installed

## Creating a Custom Image with Packer

**If you are using a custom vpc, make sure to configure [Packer](https://www.packer.io/) to use a subnet with automatic public ip assignment and a route to the internet gateway.**

### Packer File

First we create a [Packer](https://www.packer.io/) file with some information about the image we want to create.

Most importantly We specify the `region`. By default our `AMI` will only be available in this `region`.

We specify [Ansible](https://www.ansible.com/) as provisioner. It will execute the `playbook` on the temporary instance to apply additional configuration.

```go
variable "aws_access_key" {
  sensitive = true
}
variable "aws_secret_key" {
  sensitive = true
}

source "amazon-ebs" "example" {
  access_key      = var.aws_access_key
  secret_key      = var.aws_secret_key
  ssh_timeout     = "30s"
  region          = "eu-central-1"
  // amazon linux 2
  source_ami      = "ami-0db9040eb3ab74509"
  ssh_username    = "ec2-user"
  ami_name        = "packer nginx"
  instance_type   = "t2.micro"
  skip_create_ami = false

}

build {
  sources = [
    "source.amazon-ebs.example"
  ]
  provisioner "ansible" {
    playbook_file = "playbook.yml"
  }
}

```

### Ansible Playbook

Once [Packer](https://www.packer.io/) has created the temporary instance, we use [Ansible](https://www.ansible.com/) to apply additional configuration.

The playbook tells ansible to install and enable the nginx service. The result will be `nginx` serving the default page on port 80 when the `instance` is booted.

```yml
---
- name: set up nginx

  hosts: default
  become: true

  tasks:
    - name: ensure extra repo is available
      yum:
        name: [amazon-linux-extras]
        state: present

    - name: enable nginx repo
      shell: amazon-linux-extras enable nginx1

    - name: yum-clean-metadata
      command: yum clean metadata
      args:
        warn: no

    - name: install nginx
      yum:
        name: [nginx]
        state: latest

    - name: enable nginx service
      service:
        name: nginx
        enabled: true
```

### Build

With the 2 configuration files we can validate the input and build our custom `AMI` in [AWS](https://aws.amazon.com/).

```console
packer validate . 
packer build .
```

### The AMI

Once the process is completed, we can use the [AWS CLI](https://aws.amazon.com/cli/) to inspect the created `AMI` and find the `ImageId`.

```json
$ aws ec2 describe-images --owner self --region eu-central-1
{
    "Images": [
        {
            "Architecture": "x86_64",
            "CreationDate": "2021-04-18T00:00:05.000Z",
            "ImageId": "ami-01cce7ac6df33f08e",
            "ImageLocation": "<your_account_id>/packer nginx",
            "ImageType": "machine",
            "Public": false,
            "OwnerId": "<your_account_id>",
            "PlatformDetails": "Linux/UNIX",
            "UsageOperation": "RunInstances",
            "State": "available",
            "BlockDeviceMappings": [
                {
                    "DeviceName": "/dev/xvda",
                    "Ebs": {
                        "DeleteOnTermination": true,
                        "SnapshotId": "snap-0692717e44e63cbd1",
                        "VolumeSize": 8,
                        "VolumeType": "gp2",
                        "Encrypted": false
                    }
                }
            ],
            "EnaSupport": true,
            "Hypervisor": "xen",
            "Name": "packer nginx",
            "RootDeviceName": "/dev/xvda",
            "RootDeviceType": "ebs",
            "SriovNetSupport": "simple",
            "VirtualizationType": "hvm"
        }
    ]
}
```

## Deploying the Infrastructure with Terraform

Now we have our custom `AMI` in the `eu-central-1` region. Next we will use [Terraform](https://www.terraform.io/) to deploy this image together with the required infrastructure.

![image of infrastructure with elb](https://user-images.githubusercontent.com/39703898/115515253-dc43b000-a27c-11eb-8c96-b7fd705b7a9f.png)

```go
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
```

### VPC

First we create a simple `VPC` with 2 `subnets` in different `availability zones`.

```go
resource "aws_vpc" "packer" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "packer"
    Description = "sample vpc with 2 public subnets in 2 availability zones and a network load balancer for high availability"
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
```

### Security Groups

Next, we create the `security groups`.

The default security group has only a reference to itself. It is used to allow traffic to flow between the `ALB` and its `targets`.

The second `security group` is to allow tcp traffic from the public web to the `ALB` on port 80(HTTP) and 443 (HTTPS).

```go
resource "aws_default_security_group" "internal" {
  vpc_id = aws_vpc.packer.id

  tags = {
    Name = "default internal sg"
  }

  ingress {
    protocol    = -1
    self        = true
    from_port   = 0
    to_port     = 0
    description = "self ref"
  }

  egress {
    protocol    = -1
    self        = true
    from_port   = 0
    to_port     = 0
    description = "self ref"
  }

}

resource "aws_security_group" "web" {
  vpc_id = aws_vpc.packer.id

  tags = {
    Name = "web sg for nginx"
  }

  ingress {
    description      = "http traffic"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "http traffic"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

}
```

### Logging

We are going to create an `S3 bucket` with the required access `policy` to use it as log destination for the `ALB` in the next section.

```go
resource "aws_s3_bucket" "logs" {
  bucket = "com.myorg.logs"
  acl    = "private"
  force_destroy = true
  tags = {
    Name        = "nginx cluster access logs"
    Environment = "Dev"
  }
}


data "aws_elb_service_account" "main" {
    region = "eu-central-1"
}


resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Id": "allow-elb-logs",
    "Statement": [
        {
            "Sid": "RegionRootArn",
            "Effect": "Allow",
            "Principal": {
                "AWS": "${data.aws_elb_service_account.main.arn}"
            },
            "Action": "s3:PutObject",
            "Resource": "${aws_s3_bucket.logs.arn}/*"
        },
        {
            "Sid": "AWSLogDeliveryWrite",
            "Effect": "Allow",
            "Principal": {
                "Service": "delivery.logs.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "${aws_s3_bucket.logs.arn}/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-acl": "bucket-owner-full-control"
                }
            }
        },
        {
            "Sid": "AWSLogDeliveryAclCheck",
            "Effect": "Allow",
            "Principal": {
                "Service": "delivery.logs.amazonaws.com"
            },
            "Action": "s3:GetBucketAcl",
            "Resource": "${aws_s3_bucket.logs.arn}"
        }
    ]
}
  POLICY
}
```

### Load balancing

Next, an application load balancer (ALB) is created with a 2 `listeners`.

The first `listener` will listen on port 80 and redirect the traffic to port 443. The

The second  `listener` will serve a tls certificate, that is imported from `ACM`, on port 443. After the `TLS handshake` it will forward the traffic over http on port 80 to the target group, also known asl `TLS Termination`.

I am assuming that you already have uploaded your own cert or issues one with ACM. There [a branch without tls](https://github.com/bluebrown/immutable-cluster/tree/no-tls) in this repo.

The `target group` will be populated by the `auto scaling group` in the next section.

```go
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
```

### Autoscaling

Lastly, we create a launch template and auto scaling group to launch new instances of the custom `AMI`.

We will require a minimum of 2 instances with a desired count of 2 instances. Optionally we allow to scale up to 4 instances if instances reach their resource limit.

The `strategy` of the `placement group` is set to `partition` which means that the instances should get spread across the racks in physical data center.

```go
resource "aws_placement_group" "web" {
  name     = "web-pl"
  strategy = "partition"
}

resource "aws_launch_template" "web" {
  name_prefix   = "web-lt-"
  image_id      = var.ami_id
  instance_type = "t2.micro"
  vpc_security_group_ids = [
    aws_default_security_group.internal.id,
  ]
}

resource "aws_autoscaling_group" "web" {
  name                = "webscale"
  vpc_zone_identifier = [aws_subnet.a.id, aws_subnet.b.id]
  desired_capacity    = 2
  max_size            = 4
  min_size            = 2
  placement_group     = aws_placement_group.web.id
  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }
  lifecycle {
    ignore_changes = [load_balancers, target_group_arns]
  }
}

resource "aws_autoscaling_attachment" "web" {
  autoscaling_group_name = aws_autoscaling_group.web.id
  alb_target_group_arn   = aws_lb_target_group.web.arn
}
```

## Deploy

Now we can deploy the infrastructure. Run `terraform apply` and confirm the prompt. The process will take a couple minutes until all the resources are created and ready.

```console
terraform apply
```

You can use [AWS CLI](https://aws.amazon.com/cli/) to see if the targets of the load balancer are health.

They may not be ready yet. If that is the case, just wait a couple minutes and check again.

```console
$ arn=$(aws elbv2 describe-target-groups --name web-tg --query "TargetGroups[0].TargetGroupArn" --output text)
$ aws elbv2 describe-target-health --target-group-arn "$arn"
{
    "TargetHealthDescriptions": [
        {
            "Target": {
                "Id": "i-0b8137e9710a695a3",
                "Port": 80
            },
            "HealthCheckPort": "80",
            "TargetHealth": {
                "State": "healthy"
            }
        },
        {
            "Target": {
                "Id": "i-08db17910a66c9372",
                "Port": 80
            },
            "HealthCheckPort": "80",
            "TargetHealth": {
                "State": "healthy"
            }
        }
    ]
}
```

Once the targets are marked as healthy, we need to point a `CNAME record` from our domain to the `ELB DNS`. I am managing my certificate with `Linode`, so I will give an example of how to do it via [linode-cli](https://www.linode.com/docs/guides/linode-cli/).

```console
dns=$(aws elbv2 describe-load-balancers --name "packer-nginx" --query "LoadBalancers[0].DNSName" --output text)
linode-cli domains records-create --type CNAME --name elb --target $dns --ttl_sec 300  <my-domain-id>
```

You can now visit the url in your browser under your the configured subdomain.

![nginx default web page](https://user-images.githubusercontent.com/39703898/115831360-64ef5700-a409-11eb-9c8f-5c44fb06be11.png)

Thats it!

The application is deployed from a custom `AMI` across 2 `availability zones` and utilizing `autoscaling`. The traffic is routed via `ELB` which also performs `TLS Termination`.

Additionally, e have our whole infrastructure as code which we can source control.

## Cleaning Up

In order to avoid cost, lets remove all created resources.

```console
terraform destroy
```

Since the AMI and snapshot was not created with [Terraform](https://www.terraform.io/), it wont be destroyed by the former command. We are going to remove them via CLI.

### Deregister Image

```console
aws ec2 deregister-image --image-id <your-ami-id>
```

### Find the snapshot Id

```console
aws ec2 describe-snapshots --owner self
```

### Delete snapshot

```console
aws ec2 delete-snapshot --snapshot-id <your-snap-id>
```

```console
linode-cli domains records-delete <main-id> <record-id>
```
