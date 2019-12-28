include {
  path = "${find_in_parent_folders()}"
}

terraform {
  source = "github.com/clusterfrak-dynamics/terraform-aws-acm.git?ref=v1.0.2"
}

locals {
  aws_region  = "us-east-1"
  env         = yamldecode(file("${get_terragrunt_dir()}/${find_in_parent_folders("common_tags.yaml")}"))["Env"]
  custom_tags = yamldecode(file("${get_terragrunt_dir()}/${find_in_parent_folders("common_tags.yaml")}"))
}

inputs = {

  env = local.env

  aws = {
    "region" = local.aws_region
  }

  custom_tags = merge(
    local.custom_tags
  )

  common_name               = "dev.particule.io"
  hosted_zone_id            = "ZYP9UY3E2Z6EX"
  validation_method         = "DNS"
  subject_alternative_names = []
  default_ttl               = 60
}
