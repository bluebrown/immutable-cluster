# AWS DevOps Workflow with Packer and Terraform

First a custom image is build with packer, using ansible as provisioner to apply configuration. Then terraform is used to provision infrastructure and create instances using the custom image within the created infrastructure.

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

## Hands On

### Creating a Custom Image

> *If you are using a custom vpc, make sure to configure packer to use a subnet with automatic public ip assignment and a route to the internet gateway.  

EBS snapshots are snapshots or single volumes of an instance. i.e. the root volume. AMI are conceptionally snapshots of instances while they are technically just a collection of all ebs snapshots of the instance.

If a instance has only a root volume attached, taking a a ebs snapshot of this volume and creating an AMI from the image are the same things.

#### Packer File

First we create a packer file with some information about the image we want to create. Important is to specify ansible as provisioner. It will execute the playbook locally on the temporary instance.

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

#### Ansible Playbook

The playbook with simply install and enable nginx

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

#### The AMI

One the process is completed, we can inspect the snapshot.

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

> Don't forget to delete the created AMI and snapshot from the ec2 dashboard later, in order to avoid charges.*

## Deploying the Infrastructure

Now we have our custom AMI in the eu-central-1 region. Next we will use terraform to deploy this image with the required infrastructure.

We create 2 subnets in different availability zones and create a instance from the earlier created AMI.

```go
...
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
...
```

## Load balancing

Since the application is deployed cross zones, this has an impact on our loadbalancer design.  When using AWS loadbalancer, aws will deploy a instance of the loadbalancer in the specified availability zones of the given region or by default in all zones.

A network loadbalancer will by default only forward traffic to the targets in its own region. Cross zone routing can be enabled but it will cost additional money as it counts as outbound traffic.

The application loadbalancer will always route across all configured availability zones but AWS will not charge for the outbound traffic.

When using the loadbalancer to serve a tls certificate, one can perform tls termination in order to reduce computation cost and configuration on the target instances. However, this is not advised when using cross zone routing.

The loadbalancer instances itself are exposed via dns from Route 53. Route 53 performs DNS roudrobin to the loadbalancer and the loadbalancer forward the traffic in the configured manner to the targets.

It can make sense to point A records directly to the target instances (DNS roundrobin) and skip the loadbalancer altogether. This would be the case when:

- sophisticated routing based on layer 7 is not required
- each instance serves its own certificate
- the number of instances is relatively low
- server side dns failover is available

For example when a running low number of identical instances across more than 1 availability zone using a modern dns provider such as Route 53.
