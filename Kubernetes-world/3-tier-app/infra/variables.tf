variable "environment" {
  description = "The environment of the application"
  type = string
  default = "dev"
}

variable "aws_region" {
  description = "The region of the application"
  type = string
  default = "ap-south-1"
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

variable "app_subdomain" {
  description = "The subdomain of the application"
  type = string
  default = "devopsdozo"
}

variable "app_namepace" {
  description = "The namespace of the application"
  type = string
  default = "devopsdozo"
}

variable "domain_name" {
  description = "The domain of the application"
  type = string
  default = "mansipandey.in"
}