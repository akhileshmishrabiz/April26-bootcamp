# security group for rds subnets

resource "aws_security_group" "rds_sg" {
  name = "april-2026-bootcamp-rds-sg"
  description = "Security group for rds subnets"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port = 5432
    to_port = 5432
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "april-2026-bootcamp-rds-sg"
  }
}

# ecs security group on port 8000 inbound

resource "aws_security_group" "ecs_sg" {
  name = "april-2026-bootcamp-ecs-sg"
  description = "Security group for ecs subnets"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port = 8000
    to_port = 8000
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "april-2026-bootcamp-ecs-sg"
  }
}

# security group for ALB on port 80 and 443 inbound

resource "aws_security_group" "alb_sg" {
  name = "april-2026-bootcamp-alb-sg"
  description = "Security group for alb subnets"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "april-2026-bootcamp-alb-sg"
  }
}