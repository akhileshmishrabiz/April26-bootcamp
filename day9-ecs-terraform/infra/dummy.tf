# # aws ec2 instance

# resource "aws_instance" "from_me" {
#   ami           = "ami-09ed39e30153c3bf9"
#   instance_type = "t2.micro"
# }

# resource "aws_vpc" "that" {
#     count = 2
#   cidr_block = "10.0.${count.index}.0/24"
#   tags = {
#     Name = "april-2026-bootcamp-vpc-${count.index}"
#   }
# }

# resource "aws_subnet" "private_subnet_1" {
#   vpc_id     = aws_vpc.this.id
#   cidr_block = "10.0.1.0/24"
# #   availability_zone = "ap-south-1a"
# # string interpolation (in python we call it f-string)
# availability_zone = "${var.aws_region}a"
#   tags = {
#     Name = "april-2026-bootcamp-private-subnet-1"
#   }
# }