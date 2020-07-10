provider "aws" {
  region = "us-east-1"
  //shared_credentials_file = "~/.aws/credentials"
  access_key = ""
  secret_key = ""
  version = "~> 2.69"
}

resource "aws_vpc" "nuvemshop" {
  cidr_block = "10.31.0.0/16"
  enable_dns_hostnames = "true"
  enable_dns_support = "true"
}

resource "aws_internet_gateway" "gw_ns" {
  vpc_id = aws_vpc.nuvemshop.id

  tags = {
    Name = "NuvemShop"
  }
}

resource "aws_subnet" "nuvemshop" {
  vpc_id     = aws_vpc.nuvemshop.id
  cidr_block = "10.31.19.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "NuvemShop"
  }
}

resource "aws_subnet" "nuvemshop_1" {
  vpc_id     = aws_vpc.nuvemshop.id
  cidr_block = "10.31.11.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "NuvemShop"
  }
}

resource "aws_route_table" "ns_global" {
  vpc_id = aws_vpc.nuvemshop.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw_ns.id
  }
}

resource "aws_main_route_table_association" "ns_global" {
  vpc_id         = aws_vpc.nuvemshop.id
  route_table_id = aws_route_table.ns_global.id
}

resource "aws_key_pair" "NuvemShop" {
  key_name = "NuvemShop"
  public_key = file("~/.ssh/id_rsa.pub")
}

//resource "aws_s3_bucket" "nuvemshop-alb-logs"{
  //bucket = "nuvemshop-alb-logs"
  //acl    = "log-delivery-write"

  //tags = {
   // Name        = "ALB Logs"
    //Environment = "NuvemShop"
  //}
//}

//resource "aws_s3_bucket" "nuvemshop-alb" {
  //bucket = "nuvemshop-alb-logs"
  //acl    = "log-delivery-write"

  //logging {
    //target_bucket = aws_s3_bucket.nuvemshop-alb-logs.id
    //target_prefix = "NS-ALB_log/"
  //}
//}

resource "aws_alb_target_group" "http" {
  name     = "http"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.nuvemshop.id
}

resource "aws_alb" "NS" {
  name               = "NuvemShop"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_http.id]
  subnet_mapping {
    subnet_id     = aws_subnet.nuvemshop.id
  }

  subnet_mapping {
    subnet_id     = aws_subnet.nuvemshop_1.id
    //allocation_id = "${aws_eip.example2.id}"
  }

  enable_deletion_protection = true

  //access_logs {
    //bucket  = aws_s3_bucket.nuvemshop-alb-logs.bucket
    //prefix  = "NS"
    //enabled = true
  //}
  depends_on = [aws_internet_gateway.gw_ns]

  tags = {
    Environment = "NuvemShop"
  }
}

resource "aws_alb_listener" "NS" {
  load_balancer_arn = aws_alb.NS.arn
  port              = "80"
  protocol          = "HTTP"
  depends_on        = [aws_alb_target_group.http]

  default_action {
    target_group_arn = aws_alb_target_group.http.arn
    type             = "forward"
  }
}

resource "aws_security_group" "ec2" {
  name        = "ec2"
  description = "Allow SSH inbound traffic in EC2"
  vpc_id      = aws_vpc.nuvemshop.id

  ingress {
    description = "SSH only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["189.78.214.173/32"]
  }

  ingress {
    description = "TCP local"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.31.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SSH_EC2"
  }
}

resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow HTTP inbound traffic in HTTP"
  vpc_id      = aws_vpc.nuvemshop.id

  ingress {
    description = "HTTP only"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "HTTP_ALB"
  }
}

resource "aws_instance" "apache" {
  ami           = "ami-01ca03df4a6012157"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.NuvemShop.key_name
  security_groups = [aws_security_group.ec2.id]
  subnet_id       = aws_subnet.nuvemshop.id
  associate_public_ip_address = "true"
  user_data     = <<-EOF
                  #!/bin/bash
                  sudo su
                  dnf -y install httpd
                  echo "<p>Access Denied</p>" >> /var/www/html/index.html
                  sudo systemctl enable httpd
                  sudo systemctl start httpd
                  EOF

  tags = {
    Name = "Apache-NuvemShop"
  }
}

resource "aws_instance" "nginx" {
  ami           = "ami-01ca03df4a6012157"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.NuvemShop.key_name
  security_groups = [aws_security_group.ec2.id]
  subnet_id     = aws_subnet.nuvemshop.id
  associate_public_ip_address = "true"
  user_data     = <<-EOF
                  #!/bin/bash
                  sudo su
                  dnf -y install nginx
                  mv /usr/share/nginx/html /usr/share/nginx/html.old
                  echo "<p>Access Denied</p>" >> /usr/share/nginx/html
                  sudo systemctl enable nginx
                  sudo systemctl start nginx
                  EOF

  tags = {
    Name = "NGINX-NuvemShop"
  }
}

resource "aws_alb_target_group_attachment" "NS-Apache" {
  target_group_arn = aws_alb_target_group.http.arn
  target_id        = aws_instance.apache.id
  port             = 80
}

resource "aws_alb_target_group_attachment" "NS-NGINX" {
  target_group_arn = aws_alb_target_group.http.arn
  target_id        = aws_instance.nginx.id
  port             = 80
}

output "ALB_DNS" {
  value = aws_alb.NS.dns_name
}
