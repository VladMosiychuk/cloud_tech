provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

# Create VPC
resource "aws_vpc" "lab_07" {
  cidr_block = "10.0.0.0/16"

  enable_dns_support   = true
  enable_dns_hostnames = true
}

# Block access from specific IP
resource "aws_network_acl" "lab_07" {
  vpc_id = aws_vpc.lab_07.id

  ingress {
    protocol   = "all"
    rule_no    = 200
    action     = "deny"
    cidr_block = "50.31.252.0/24"
    from_port  = 0
    to_port    = 0
  }
}


# Create public subnet
resource "aws_subnet" "pub" {
  count                   = 2
  vpc_id                  = aws_vpc.lab_07.id
  cidr_block              = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
}

# Create Internet Gateway to enable VPC to access internet
resource "aws_internet_gateway" "lab_07" {
  vpc_id = aws_vpc.lab_07.id
}

# Create a custom route table for public subnet so it can reach to the internet by using this.
resource "aws_route_table" "pub" {
  vpc_id = aws_vpc.lab_07.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab_07.id
  }
}

# Associate route table with subnet
resource "aws_route_table_association" "crta" {
  count          = length(aws_subnet.pub)
  subnet_id      = aws_subnet.pub[count.index].id
  route_table_id = aws_route_table.pub.id
}

# Create security group for database
resource "aws_security_group" "postgres" {
  vpc_id = aws_vpc.lab_07.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create database subnet goup
resource "aws_db_subnet_group" "default" {
  name       = "main"
  subnet_ids = [for pub in aws_subnet.pub : pub.id]
}

# Create database
resource "aws_db_instance" "default" {
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "postgres"
  instance_class         = "db.t2.micro"
  name                   = "lab_07_db"
  username               = "testuser"
  password               = var.db_pwd
  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.postgres.id]
  publicly_accessible    = true
  skip_final_snapshot    = true
}
