variable "env" {
  description = "Environment key — prefixed on all resource names (dev → dev-, prod → prod-)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "eks_cluster_name" {
  description = "The name of the EKS cluster"
  type        = string
  default     = "sep26-cluster"
}

variable "eks_cluster_version" {
  description = "The version of the EKS cluster"
  type        = string
  default     = "1.35"
}

variable "eks_cluster_endpoint_public_access" {
  description = "Whether to enable public access to the EKS cluster"
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_name" {
  description = "The name of the VPC"
  type        = string
  default     = "sep26-may26"
}


variable "aws_region" {
  description = "The region of the AWS"
  type        = string
  default     = "ap-south-1"
}


variable "eks_nodes" {
  description = "The nodes of the EKS cluster"
  type        = list(object({
    instance_type = string
    desired_size  = number
    max_size      = number
    min_size      = number
  }))
  default     = [
    {
      instance_type = "t3.medium"
      desired_size  = 3
      max_size      = 3
      min_size      = 3
    }
  ]
}

variable "ami_type" {
  description = "The AMI type for the EKS cluster"
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}


variable "enable_nat_gateway" {
  description = "Whether to enable NAT gateway"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Whether to use a single NAT gateway"
  type        = bool
  default     = true
}

variable "one_nat_gateway_per_az" {
  description = "Whether to use a single NAT gateway per AZ"
  type        = bool
  default     = false
}