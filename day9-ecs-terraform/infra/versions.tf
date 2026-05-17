terraform {
  required_version = "1.12.1"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.8.0"
    }
  }
}


terraform {
  backend "s3" {
    bucket = "state-bucket-879381241087"
    key = "april26/ecs/terraform.tfstate"
    region = "ap-south-1"
    use_lockfile = true
    encrypt = true
  } 
}