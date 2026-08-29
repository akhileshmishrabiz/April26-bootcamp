provider "kubernetes" {
  config_path = "~/.kube/config"
}


provider "aws" {
  region = var.aws_region
}