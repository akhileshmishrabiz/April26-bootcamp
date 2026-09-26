provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Environment = var.env
      Project     = "aprile/bootcamp/production-eks-env"
      Terraform   = "true"
    }
  }
}