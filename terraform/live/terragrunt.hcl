remote_state {
  backend = "s3"

  config = {
    bucket         = "particule-tf-state-store-frontend-eu-west-3"
    key            = "${path_relative_to_include()}"
    region         = "eu-west-3"
    encrypt        = true
    dynamodb_table = "particule-tf-state-store-lock-frontend-eu-west-3"
  }
}
