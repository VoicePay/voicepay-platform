module "vpc" {
  source      = "../../modules/vpc"
  environment = var.environment
  aws_region  = var.aws_region
}

module "iam" {
  source      = "../../modules/iam"
  environment = var.environment
}
