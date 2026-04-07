module "vpc" {
  source      = "../../modules/vpc"
  environment = var.environment
  aws_region  = var.aws_region
  tags        = var.tags
}

module "iam" {
  source                   = "../../modules/iam"
  environment              = var.environment
  aws_region               = var.aws_region
  aws_account_id           = var.aws_account_id
  github_org               = var.github_org
  github_repo              = var.github_repo
  github_oidc_provider_arn = var.github_oidc_provider_arn
  tags                     = var.tags
}
