terraform {
  required_version = "1.16.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}


terraform {
  backend "s3" {
  }
}