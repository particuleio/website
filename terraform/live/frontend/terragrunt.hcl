include {
  path = "${find_in_parent_folders()}"
}

terraform {
  source = "github.com/clusterfrak-dynamics/terraform-aws-s3-cloudfront?ref=v1.3.0"
}

locals {
  env         = yamldecode(file("${get_terragrunt_dir()}/${find_in_parent_folders("common_tags.yaml")}"))["Env"]
  aws_region  = "eu-west-3"
  project     = "frontend"
  prefix      = "particule"
  custom_tags = yamldecode(file("${get_terragrunt_dir()}/${find_in_parent_folders("common_tags.yaml")}"))
}

dependency "acm" {
  config_path = "../acm-particule-io"

  mock_outputs = {
    certificate_arn = "arn:aws:acm:us-east-1:000000000000:certificate/00000000-0000-0000-0000-000000000000"
  }
}

inputs = {
  env     = local.env
  project = local.project
  prefix  = local.prefix

  aws = {
    "region" = local.aws_region
  }

  dns = {
    use_route53    = true
    hosted_zone_id = "ZYP9UY3E2Z6EX"
    hostname       = "dev.particule.io"
  }

  custom_tags = merge(
    local.custom_tags
  )

  front = {
    bucket_name                    = "particule-frontend-static-site"
    log_bucket_name                = "particule-frontend-static-site-logs"
    log_bucket_expiration_days     = 365
    s3_origin_id                   = "s3-particule-frontend-static-site"
    origin_access_identity_comment = "Origin Access Identity for particule website"
    aliases                        = ["dev.particule.io"]
    cloudfront_price_class         = "PriceClass_100"
    acm_arn                        = dependency.acm.outputs.certificate_arn
    minimum_protocol_version       = "TLSv1.1_2016"
    ssl_support_method             = "sni-only"
    wait_for_deployment            = "false"
    index_document                 = "index.html"
    error_document                 = null
    custom_error_response          = []
  }
}
