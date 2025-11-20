
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}




# Setting VPC and 2 public subnets

resource "aws_vpc" "custom_vpc" {
    cidr_block = var.vpc_cidr
    enable_dns_support   = true
    enable_dns_hostnames = true

    tags = {
        Name = "GitOps-VPC-JG"
    }
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.custom_vpc.id

    tags = {
        Name = "GitOps-IGW-JG"
    }
}
resource "aws_subnet" "public_a" {
    vpc_id =  aws_vpc.custom_vpc.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "${var.aws_region}a"
    map_public_ip_on_launch = true

    tags = {
        Name = "jg-Public-Subnet-A"
    }
}

resource "aws_subnet" "public_b" {
    vpc_id =  aws_vpc.custom_vpc.id
    cidr_block = "10.0.2.0/24"
    availability_zone = "${var.aws_region}b"
    map_public_ip_on_launch = true
    
    tags = {
        Name = "jg-Public-Subnet-B"
    }
}

resource "aws_route_table" "public" {
    vpc_id = aws_vpc.custom_vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }
    tags = { Name = "jg-public-rt" }
}

resource "aws_route_table_association" "public_a" {
    subnet_id      = aws_subnet.public_a.id
    route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
    subnet_id      = aws_subnet.public_b.id
    route_table_id = aws_route_table.public.id
}











resource "aws_subnet" "private_a" {
    vpc_id            = aws_vpc.custom_vpc.id
    cidr_block        = "10.0.3.0/24"
    availability_zone = "${var.aws_region}a"
    tags = { Name = "jg-Private-Subnet-A" }
}
resource "aws_subnet" "private_b" {
    vpc_id            = aws_vpc.custom_vpc.id
    cidr_block        = "10.0.4.0/24"
    availability_zone = "${var.aws_region}b"
    tags = { Name = "jg-Private-Subnet-B" }
}   

resource "aws_eip" "nat_eip" {
    domain = "vpc"
    tags   = { Name = "jg-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
    allocation_id = aws_eip.nat_eip.id
    subnet_id     = aws_subnet.public_a.id 
    tags          = { Name = "jg-nat-gateway" }

    depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
    vpc_id = aws_vpc.custom_vpc.id
    route {
        cidr_block     = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.nat.id
    }
    tags = { Name = "jg-private-rt" }
}

resource "aws_route_table_association" "private_a" {
    subnet_id      = aws_subnet.private_a.id
    route_table_id = aws_route_table.private.id
}
resource "aws_route_table_association" "private_b" {
    subnet_id      = aws_subnet.private_b.id
    route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "alb_sg" {
    name        = "jg-alb-sg"
    description = "ALB Public Traffic"
    vpc_id      = aws_vpc.custom_vpc.id

    ingress {
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
  }
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
}
    tags = { Name = "ALB-SG-JG" }
}

resource "aws_security_group" "web_sg" {
    name = "jg-web-sg"
    description = "Allows SSH, HTTP/S"
    vpc_id = aws_vpc.custom_vpc.id

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        security_groups = [aws_security_group.alb_sg.id]
    }
    ingress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        security_groups = [aws_security_group.alb_sg.id]
    }
    tags = {
        Name = "Web-SG-JG"
    }
}

resource "aws_security_group" "db_sg" {
    name        = "jg-db-sg-rds"
    description = "Reglas para RDS Postgres"
    vpc_id      = aws_vpc.custom_vpc.id

    # Solo acepta tráfico de las EC2
    ingress {
        from_port       = 5432
        to_port         = 5432
        protocol        = "tcp"
        security_groups = [aws_security_group.web_sg.id]
    }
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_lb" "app_lb" {
    name               = "jg-alb"
    internal           = false
    load_balancer_type = "application"
    security_groups    = [aws_security_group.alb_sg.id]
    subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

resource "aws_lb_target_group" "tg" {
    name     = "jg-tg"
    port     = 80
    protocol = "HTTP"
    vpc_id   = aws_vpc.custom_vpc.id
    health_check {
        matcher = "200"
    }
}

resource "aws_lb_listener" "listener" {
    load_balancer_arn = aws_lb.app_lb.arn
    port              = "80"
    protocol          = "HTTP"
    default_action {
        type             = "forward"
        target_group_arn = aws_lb_target_group.tg.arn
    }
}

resource "aws_launch_template" "web_lt" {
    name_prefix   = "jg-lt-"
    image_id      = data.aws_ami.ubuntu.id
    instance_type = "t3.micro"
    key_name      = var.key_name
  
    network_interfaces {
        associate_public_ip_address = true
        security_groups             = [aws_security_group.web_sg.id]
    }

    user_data = base64encode(<<-EOF
                #!/bin/bash
                apt-get update
                apt-get install -y python3 python3-pip
                EOF
    )
    tag_specifications {
        resource_type = "instance"
        tags = {
	    Name = "ec2-jg"
	    role = "gitops"
        }
    }
}

resource "aws_autoscaling_group" "asg" {
    name                = "jg-asg"
    vpc_zone_identifier = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    desired_capacity    = 2
    min_size            = 2
    max_size            = 4
    target_group_arns   = [aws_lb_target_group.tg.arn]

    launch_template {
        id      = aws_launch_template.web_lt.id
        version = "$Latest"
    }
}

resource "aws_db_subnet_group" "rds_group" {
    name       = "jg-rds-group"
    subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

resource "aws_db_instance" "db" {
    allocated_storage      = 10
    identifier = "jg-db-gitops"
    db_name                = "jgdb"
    engine                 = "postgres"
    engine_version         = "16.11"
    instance_class         = "db.t3.micro"
    username               = "adminuser"
    password               = "password123"
    skip_final_snapshot    = true
    db_subnet_group_name   = aws_db_subnet_group.rds_group.name
    vpc_security_group_ids = [aws_security_group.db_sg.id]
}

output "alb_dns_name" {
  value       = aws_lb.app_lb.dns_name
}

output "rds_endpoint" {
  value       = aws_db_instance.db.address
}

output "asg_name" {
  value       = aws_autoscaling_group.asg.name
}

