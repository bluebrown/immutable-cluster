# Immutable Infrastructure in AWS with Packer, Ansible and Terraform

In this post, I will showcase one possible DevOps workflow to provision infrastructure and deploy application. I am going to use Packer, Ansible and Terraform. Additionally I will use the AWS CLI.

## Tools

### Terraform

Terraform is great at provisioning infrastructure and keeping track of the state of this infrastructure. We may use Terraform to create a new VPC in AWS and add various gateways, security groups and other configuration. Terraform tracks the state in a lock file that can be source controlled.

While terraform is great at creating resources, it isn't particularly great and configuring instances such as ec2 or droplets. Usually it wont wait until an instance is ready to be further configured. So if it is required to run some sort of script, after the instance was created, one has to resort to provisioners which should be avoided.

The preferred solution is to have Terraform create the instances with a custom image that doesn't need any additional steps after instance creation.

### Packer

Packer is a tool to create images using various builders. For example one can create a simple virtualbox and run it locally. But also a number of cloud native builders is available such as AWS, Linode, Digital Ocean and so on. When using such a builder, packer will use the environment of this builder to create the image. For example, we can use packer to create an AMI in aws using a real ec2 instance as base.

Packer allows to run a number of provisioners such as ansible and chef. These can be used to apply configuration to the base image before packaging it as new custom image.

### Ansible

Ansible can be used to apply repeatable configuration to one or more instance, local or remote. It is very useful to have in this stack as it can be integrated in packer to create custom images. Furthermore, it can be used to apply configuration to running instances in robust and consistent manner.

<br>

## The workflow 

First a custom image is build with packer, using ansible as provisioner to apply configuration. Then terraform is used to provision infrastructure and create instances using the custom image within the created infrastructure.

## Hands On

You can find the full working code in github https://github.com/bluebrown/packer-terraform-ha-cluster

### Prerequisites

To follow along you need:

- an aws account & access tokens
- have ansible installed
- have packer installed
- have terraform installed
- have the aws cli version 2 installed

### Creating a Custom Image

> *If you are using a custom vpc, make sure to configure packer to use a subnet with automatic public ip assignment and a route to the internet gateway.  

EBS snapshots are snapshots of single volumes of an instance. i.e. the root volume. AMI are conceptionally snapshots of instances while they are technically just a collection of all ebs snapshots of the instances volumes.

If a instance has only a root volume attached, taking an ebs snapshot of this volume and creating an AMI from the image are the same things.

#### Packer File

First we create a packer file with some information about the image we want to create. We specify ansible as provisioner. It will execute the playbook on the temporary instance to apply additional configuration.

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
  source_ami      = "ami-0db9040eb3ab74509" // amazon linux 2
  ssh_username    = "ec2-user"
  ami_name        = "packer nginx"
  instance_type   = "t2.micro"
  skip_create_ami = false // set to true if you don't want to create an actual ami. Useful for development.
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

#### Ansible Playbook

Once packer has created the temporary instance, we use ansible to apply additional configuration. For this example, we use the playbook to install and enable the nginx service. The result will be nginx serving the default page on port 80.

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

    - name: enable and start nginx service
      service:
        name: nginx
        state: restarted
        enabled: true
```

#### Build

With the 2 configuration files we can validate the input and build our custom ami in AWS.

```
packer validate . 
packer build .
```

#### The AMI

Once the process is completed, we can use the `aws-cli` to inspect the created ami and find the image id.

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

### Deploying the Infrastructure with Terraform

Now we have our custom AMI in the eu-central-1 region. Next we will use terraform to deploy this image together with the required infrastructure.

![image of infrastructure with nlb](https://user-images.githubusercontent.com/39703898/115248770-e43a0d80-a11f-11eb-9601-7529e7ede7de.png)

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
```

#### VPC

We create a VPC with 2 subnets in different availability zones and create a instance from the earlier created AMI in each zone.

```go
resource "aws_vpc" "packer" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name        = "packer"
    Description = "sample vpc with 2 public subnets in 2 availability zones and a network loadbalancer for high availability"
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

#### Security Groups

We need to create the security groups as well

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

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

}
```

#### EC2 Instances

Now the general vpc is setup. We have 2 subnets in 2 availability zones. We also have configured the security groups. Next lets declare 1 instance from our custom image in each subnet.

```go
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
```

#### Load balancing

Since the application is deployed cross zones, this has an impact on our loadbalancer design.  When using AWS loadbalancer, aws will deploy an instance of the loadbalancer in the specified availability zones of the given region or by default in all zones.

A Network Load Balancer (NLB) will by default only forward traffic to the targets in its own region. Cross zone routing can be enabled but it will cost additional money as cross regional routing counts as outbound traffic.

The Application Load Balancer (ALB) will always route across all configured availability zones but AWS will not charge for the outbound traffic. It is generally more expensive and feature rich than a NLB though.

When using the loadbalancer to serve a tls certificate, one can perform tls termination in order to reduce computation cost and configuration on the target instances. However, this is not advised when using cross zone routing.

The loadbalancer instances itself are exposed via dns from Route 53. Route 53 performs DNS roudrobin to the loadbalancer and the loadbalancer forward the traffic in the configured manner to the targets.

It can make sense to point A records directly to the target instances (DNS roundrobin) and skip the loadbalancer altogether. This would be the case when:

- sophisticated routing based on layer 7 is not required
- each instance serves its own certificate
- the number of instances is relatively low
- server side dns failover is available

For example when a running low number of identical instances across more than 1 availability zone using a modern dns provider such as Route 53.

#### NLB

For this example I will use a network loadbalancer with cross zone routing enabled.

```go
resource "aws_lb" "tcp_lb" {
  name                             = "packer-nginx"
  internal                         = false
  load_balancer_type               = "network"
  enable_cross_zone_load_balancing = true // extra charges for outbound traffic
  subnets = [
    aws_subnet.a.id, // deploy in both subnets
    aws_subnet.b.id
  ]
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

```

### Deploy

Now we can deploy the infrastructure. Run terraform apply and confirm the prompt. The process will take a couple minutes until all the resources are created and ready.

```
$ terraform apply
```

You can use `aws-cli` to see if the targets of the load balancer are health. 

They may not be ready yet. If that is the case, just wait a couple minutes and check again.


```bash
$ arn=$(aws elbv2 describe-target-groups --name nginx-web --query "TargetGroups[0].TargetGroupArn" --output text)
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

Once the targets are marked as health we can visit the web page. Lets take the load balancer dns via cli

```
$ echo "http://$(aws elbv2 describe-load-balancers --name "packer-nginx" --query "LoadBalancers[0].DNSName" --output text)"
http://packer-nginx-266ae005c3577db4.elb.eu-central-1.amazonaws.com
```

You can now visit this url in your browser:

![image](https://user-images.githubusercontent.com/39703898/115232775-05dec900-a10f-11eb-9670-fa773436e547.png)

Thats it, we have deployed our application with high availability across 2 zones and balance the traffic with a network loadbalancer. We have our whole infrastructure as code which we can source control.

### Cleaning Up

In order to avoid cost, lets remove all created resources. 

```
terraform destroy
```

Since the AMI and snapshot was not created with terraform, it wont be destroyed by the former command. We are going to remove them via CLI.

#### Deregister Image
```
 aws ec2 deregister-image --image-id <your-ami-id>
```

#### Find the snapshot Id

 ```
 aws ec2 describe-snapshots --owner self
 ```

#### Delete snapshot

 ```bash
 aws ec2 delete-snapshot --snapshot-id <your-snap-id>
 ```
