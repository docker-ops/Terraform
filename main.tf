resource "aws_vpc" "my_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name        = "${var.environment}-vpc"
    Environment = "${var.environment}"
  }
}

resource "aws_internet_gateway" "my_ig" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name        = "${var.environment}-igw"
    Environment = "${var.environment}"
  }
}

resource "aws_subnet" "public_subnet1" {
  vpc_id                  = aws_vpc.vpc.id
  count                   = length(var.public_subnets_cidr)
  cidr_block              = element(var.public_subnets_cidr, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name        = "${var.environment}-${element(var.availability_zones, count.index)}-public-subnet1"
    Environment = "${var.environment}"
  }
}

resource "aws_subnet" "public_subnet2" {
  vpc_id                  = aws_vpc.vpc.id
  count                   = length(var.public_subnets_cidr)
  cidr_block              = element(var.public_subnets_cidr, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name        = "${var.environment}-${element(var.availability_zones, count.index)}-public-subnet2"
    Environment = "${var.environment}"
  }
}

resource "aws_subnet" "private_subnet1" {
  vpc_id                  = aws_vpc.vpc.id
  count                   = length(var.private_subnets_cidr)
  cidr_block              = element(var.private_subnets_cidr, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = false
  tags = {
    Name        = "${var.environment}-${element(var.availability_zones, count.index)}-private_subnet1"
    Environment = "${var.environment}"
  }
}

resource "aws_subnet" "private_subnet2" {
  vpc_id                  = aws_vpc.vpc.id
  count                   = length(var.private_subnets_cidr)
  cidr_block              = element(var.private_subnets_cidr, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = false
  tags = {
    Name        = "${var.environment}-${element(var.availability_zones, count.index)}-private-subnet2"
    Environment = "${var.environment}"
  }
}

resource "aws_nat_gateway" "my_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = element(aws_subnet.public_subnet.*.id, 0)
  depends_on    = [aws_internet_gateway.ig]
  tags = {
    Name        = "nat"
    Environment = "${var.environment}"
  }
}

resource "aws_eip" "nat_eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.ig]
}

resource "aws_security_group" "default" {
  name        = "${var.environment}-default-sg"
  description = "Default security group to allow inbound/outbound from the VPC"
  vpc_id      = aws_vpc.vpc.id
  depends_on  = [aws_vpc.vpc]
  ingress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = "true"
  }
  tags = {
    Environment = "${var.environment}"
  }
}

resource "aws_instance" "nginx_server" {
  ami           = "ami-0cf31d971a3ca20d6"
  instance_type = "t2.micro"
  tags = {
    Name = "nginx_server"
  }
resource "aws_instance" "nginx_server" {
    ami           = "ami-08d70e59c07c61a3a"
    instance_type = "t2.micro"
    tags = {
      Name = "nginx_server"
}

  subnet_id              = aws_subnet.prod-subnet-public-1.id
  vpc_security_group_ids = ["${aws_security_group.ssh-allowed.id}"]
  key_name               = aws_key_pair.aws-key.id

  provisioner "file" {
    source      = "nginx.sh"
    destination = "/tmp/nginx.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/nginx.sh",
      "sudo /tmp/nginx.sh"
    ]
  }

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ubuntu"
    private_key = file("${var.PRIVATE_KEY_PATH}")
  }
}

resource "aws_iam_role" "this" {
  name = var.ec2_iam_role_name
  path = "/"

  assume_role_policy = var.assume_role_policy
}

resource "aws_iam_instance_profile" "this" {
  name = var.ec2_iam_role_name
  role = aws_iam_role.this.name
}

resource "aws_iam_policy" "this" {
  name        = var.ec2_iam_role_name
  path        = "/"
  description = var.policy_description
  policy      = var.policy
}

resource "aws_iam_policy_attachment" "this" {
  name       = var.ec2_iam_role_name
  roles      = [aws_iam_role.this.name]
  policy_arn = aws_iam_policy.this.arn
}

resource "aws_s3_bucket" "b" {
  bucket_prefix = var.bucket_prefix
  acl    = var.acl
versioning {
        enabled = var.versioning
    }
logging {
        target_bucket = var.target_bucket
        target_prefix = var.target_prefix
    }
server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = var.kms_master_key_id
        sse_algorithm     = var.sse_algorithm
      }
    }
  }
tags = var.tags
}

resource "aws_lb" "alb" {
  name               = "backend-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  idle_timeout       = 60
  subnets            = [element(aws_subnet.public.*.id, 0), element(aws_subnet.public.*.id, 1)]
}

resource "aws_lb_target_group" "alb_target_group" {
  name        = "backend-tg"
  port        = 8000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled = true
    path = "/"
    port = "8000"
    protocol = "HTTP"
    healthy_threshold = 3
    unhealthy_threshold = 2
    interval = 90
    timeout = 20
    matcher = "200"
  }

  depends_on = [aws_lb.alb]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_group.arn

  }
}

resource "aws_lb_target_group_attachment" "one" {
  target_group_arn = aws_lb_target_group.alb_target_group.arn
  target_id        = aws_instance.ec2.private_ip
  port             = 8000
}
