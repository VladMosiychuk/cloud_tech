variable "ssh_key_name" {}
variable "aws_region" {}
variable "aws_access_key" {}
variable "aws_secret_key" {}

variable "instance_type" {
  default = "t2.micro"
}

# Default VPC for region
data "aws_vpc" "default" {
  default = true
}

# AMI from labwork_03
data "aws_ami" "lab_03_ami" {
  most_recent = true
  owners      = ["self"]
}

# Subnet ids
data "aws_subnet_ids" "lab_06" {
  vpc_id = data.aws_vpc.default.id
}