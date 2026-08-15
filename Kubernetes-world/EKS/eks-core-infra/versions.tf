terraform {
  required_version = "= 1.15.1"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}


terraform {
    backend "s3" {
        bucket = "state-bucket-879381241087"
        key = "augk8s26/dev/terraform.tfstate"
        region = "ap-south-1"
        use_lockfile = true 
    }
}