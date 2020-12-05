provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

locals {
  # Id's of first 2 subnets in defult vpc
  subnet_ids = slice(tolist(data.aws_subnet_ids.lab_06.ids), 0, 2)
}

# Create load balancer
resource "aws_lb" "lab_06_elb" {
  name               = "lab-06-elb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lab_06_sg.id]
  subnets            = local.subnet_ids
}

# Security group for load balancer
resource "aws_security_group" "lab_06_sg" {

  name = "lab-06-sg"

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Generate SSH key
resource "tls_private_key" "lab_06" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create Key-Par
resource "aws_key_pair" "lab_06" {
  key_name   = var.ssh_key_name
  public_key = tls_private_key.lab_06.public_key_openssh
}

# Launch 2 instances
resource "aws_instance" "web" {
  count           = 2
  key_name        = var.ssh_key_name
  instance_type   = var.instance_type
  ami             = data.aws_ami.lab_03_ami.id
  security_groups = [aws_security_group.lab_06_sg.id]
  subnet_id       = element(local.subnet_ids, count.index)
  user_data       = file("../LabWork_04/update_html.sh")
}

# Create target group for load balancing
resource "aws_lb_target_group" "lab_06_tg" {
  name        = "lab-06-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = data.aws_vpc.default.id
}

# Attach instances to target groip
resource "aws_lb_target_group_attachment" "tg_attach" {
  count            = length(aws_instance.web)
  port             = 80
  target_id        = aws_instance.web[count.index].id
  target_group_arn = aws_lb_target_group.lab_06_tg.arn
}

# Create lb listener
resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.lab_06_elb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lab_06_tg.arn
  }
}
