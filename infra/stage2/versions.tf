terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Stamped onto every resource this config creates, so you can find
  # (and cost-filter) everything from the lab in the AWS console.
  default_tags {
    tags = {
      Project = "scaling-lab"
      Stage   = "2-separate-db"
    }
  }
}
