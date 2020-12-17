include {
  path = "${find_in_parent_folders()}"
}

terraform {
  source = "github.com/terraform-aws-modules/terraform-aws-acm?ref=v2.12.0"
}

locals {
  aws_region  = "us-east-1"
  custom_tags = yamldecode(file("${find_in_parent_folders("common_tags.yaml")}"))
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.aws_region}"
    }
  EOF
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite"
  contents  = <<-EOF
    terraform {
      backend "s3" {}
    }
  EOF
}

inputs = {

  domain_name = "particule.io"
  zone_id     = "ZYP9UY3E2Z6EX"
  subject_alternative_names = [
    "*.particule.io",
    "dev.particule.io",
    "*.dev.particule.io"
  ]

  tags = merge(
    local.custom_tags
  )
}
