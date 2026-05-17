# vpc 

resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
  region = var.aws_region
  tags = {
    Name = "april-2026-bootcamp-vpc"
  }
}

# internet gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name = "april-2026-bootcamp-internet-gateway"
  }
}

  ##########    Private  Area ##########
# 2 private subnets
# dependencies
# implicitly depends on the vpc
resource "aws_subnet" "private_subnet_1" {
  vpc_id     = aws_vpc.this.id
  cidr_block = "10.0.1.0/24"
#   availability_zone = "ap-south-1a"
# string interpolation (in python we call it f-string)
availability_zone = "${var.aws_region}a"
  tags = {
    Name = "april-2026-bootcamp-private-subnet-1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id     = aws_vpc.this.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"
  tags = {
    Name = "april-2026-bootcamp-private-subnet-2"
  }
}

# route table for private subnets

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name = "april-2026-bootcamp-private-route-table"
  }
}

# route table association for private subnets

resource "aws_route_table_association" "private_subnet_1_association" {
  subnet_id = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_subnet_2_association" {
  subnet_id = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_route_table.id
}

# route for private subnets to nat gateway

resource "aws_route" "private_subnet_1_route" {
  route_table_id = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.nat_gateway.id
}


##########    Public  Area ##########
# 2 public subnets

resource "aws_subnet" "public_subnet_1" {
  vpc_id     = aws_vpc.this.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "${var.aws_region}a"
  tags = {
    Name = "april-2026-bootcamp-public-subnet-1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id     = aws_vpc.this.id
  cidr_block = "10.0.4.0/24"
  availability_zone = "${var.aws_region}b"
  tags = {
    Name = "april-2026-bootcamp-public-subnet-2"
  }
}


# route table for public subnets

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.this.id
  tags = {
    Name = "april-2026-bootcamp-public-route-table"
  }
}

# route for public subnets to internet gateway

resource "aws_route" "public_subnet_1_route" {
  route_table_id = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.this.id
}

# route table association for public subnets

resource "aws_route_table_association" "public_subnet_1_association" {
  subnet_id = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_2_association" {
  subnet_id = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_route_table.id
}


# elastic IP for nat gateway
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = {
    Name = "april-2026-bootcamp-nat-eip"
  }
}

#  nat gateway
resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id = aws_subnet.public_subnet_1.id
  tags = {
    Name = "april-2026-bootcamp-nat-gateway"
  }
}

# route table for nat gateway



# 2 rds subnets

resource "aws_subnet" "rds_subnet_1" {
  vpc_id     = aws_vpc.this.id
  cidr_block = "10.0.5.0/24"
  availability_zone = "${var.aws_region}a"
  tags = {
    Name = "april-2026-bootcamp-rds-subnet-1"
  }
}

resource "aws_subnet" "rds_subnet_2" {
  vpc_id     = aws_vpc.this.id
  cidr_block = "10.0.6.0/24"
  availability_zone = "${var.aws_region}b"
  tags = {
    Name = "april-2026-bootcamp-rds-subnet-2"
  }
}

# 1 internet gateway

# 1 nat gateway

# elastic IP

# 1 route table for public subnets

# 1 route table for private subnets

# 1 route table for rds subnets


# 1 security group for rds subnets

# 1 security group for internet gateway

# 1 security group for nat gateway

# 1 security group for elastic IP

# 1 security group for route table for public subnets
# 1 security group for route table for private subnets
# 1 security group for route table for rds subnets
# 1 security group for public subnets