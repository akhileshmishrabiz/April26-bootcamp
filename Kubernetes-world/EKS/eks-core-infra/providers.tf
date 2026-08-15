provider "aws" {
  region = "ap-south-1"
  default_tags {
    tags = {
      Environment = var.environment
      Terraform = "true"
      repo = "Aprilbootcamp/Kubernetes-world/EKS/eks-core-infra"
    }
  }
}

