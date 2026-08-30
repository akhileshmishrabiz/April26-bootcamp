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



variable "argocd_subdomain" {
  description = "The subdomain of the application"
  type = string
  default = "argocd"
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


variable "alb_group_name" {
  description = "The name of the ALB group"
  type = string
  default = "devopsdozo-alb-group"
}