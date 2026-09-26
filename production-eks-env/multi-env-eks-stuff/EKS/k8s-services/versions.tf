terraform {
  required_version = "1.12.1"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
     kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
}


terraform {
  backend "s3" {
    bucket = "state-bucket-879381241087"
    key = "eks-may-2026/k8s-services/terraform.tfstate"
    region = "ap-south-1"
    encrypt = true
    use_lockfile = true
  }
}   