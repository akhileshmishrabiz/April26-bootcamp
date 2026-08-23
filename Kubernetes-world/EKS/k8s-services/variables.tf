variable "cluster_name" {
  default = "my-cluster"
}

variable "vpc_name" {
  default = "august-eks-vpc"
}

variable "region" {
  default = "ap-south-1"
}

variable "awsloadbalancercontroller_sa" {
  default = "aws-load-balancer-controller"
}