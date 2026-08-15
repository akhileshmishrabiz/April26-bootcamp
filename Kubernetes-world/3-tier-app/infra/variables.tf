variable "environment" {
  description = "The environment of the application"
  type = string
  default = "dev"
}

variable "vpc_name" {
  description = "The name of the VPC"
  type = string
  default = "august-eks-vpc"
}

variable "region" {
  description = "The region of the application"
  type = string
  default = "ap-south-1"
}