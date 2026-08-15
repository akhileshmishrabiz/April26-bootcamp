data "aws_vpc" "main" {
  filter {
    name = "tag:Name"
    values = [var.vpc_name]
  }
}

# vpc_id - data.aws_vpc.main.id