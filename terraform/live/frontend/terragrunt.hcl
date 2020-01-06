include {
  path = "${find_in_parent_folders()}"
}

terraform {
  source = "github.com/clusterfrak-dynamics/terraform-aws-s3-cloudfront//website?ref=v1.4.0"
}

locals {
  env         = yamldecode(file("${get_terragrunt_dir()}/${find_in_parent_folders("common_tags.yaml")}"))["Env"]
  aws_region  = "eu-west-3"
  project     = "frontend"
  prefix      = "particule"
  custom_tags = yamldecode(file("${get_terragrunt_dir()}/${find_in_parent_folders("common_tags.yaml")}"))
  referer     = jsondecode(run_cmd("--terragrunt-quiet", "bash", "-c", " aws --profile particule ssm get-parameter --name /cloudfront/default/referer --with-decryption | jq .Parameter.Value"))
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
    error_document                 = "404.html"
    custom_error_response          = []
    web_acl_id                     = "arn:aws:wafv2:us-east-1:886701765425:global/webacl/particuleio/ac7b8423-a3bf-4b24-8b2e-e9c5bd87acf3"
  }

  dynamic_custom_origin_config = [
    {
      domain_name              = "particule-training.s3-website.eu-west-3.amazonaws.com"
      origin_id                = "s3-particule-training"
      origin_path              = ""
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "http-only"
      origin_ssl_protocols     = ["TLSv1", "TLSv1.1" , "TLSv1.2"]
      custom_headers           = [
      {
        name = "Referer"
        value = local.referer
      }
    ]
    },
  ]

  dynamic_ordered_cache_behavior = [
    {
      path_pattern           = "formations/*"
      allowed_methods        = ["GET", "HEAD"]
      cached_methods         = ["GET", "HEAD"]
      target_origin_id       = "s3-particule-training"
      compress               = false
      query_string           = false
      cookies_forward        = "none"
      headers                = []
      viewer_protocol_policy = "redirect-to-https"
      min_ttl                = 0
      default_ttl            = 0
      max_ttl                = 0
    }
  ]
}
