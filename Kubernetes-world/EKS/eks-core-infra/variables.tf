variable "eks_cluster_name" {
  description = "The name of the EKS cluster"
  type = string
  default = "aug-eks-cluster"
}

variable "eks_cluster_version" {
  description = "The version of the EKS cluster"
  type = string
  default = "1.27"
}

variable "environment" {
  description = "The environment of the EKS cluster"
  type = string
  default = "dev"
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type = string
  default = "10.0.0.0/16"
  
}

variable "private_subnets_cidr" {
  description = "The CIDR block for the private subnets"
  type = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnets_cidr" {
  description = "The CIDR block for the public subnets"
  type = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "vpc_name" {
  description = "The name of the VPC"
  type = string
  default = "august-eks-vpc"
}

variable "do_i_need_1_nat"{
    type = bool
    description = "Do I need 1 NAT gateway?"
    default = true
}

variable "region" {
    type = string
    description = "The region of the EKS cluster"
    default = "ap-south-1"
}