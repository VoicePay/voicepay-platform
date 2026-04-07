module "vpc" {
  source               = "../../modules/vpc"
  environment          = var.environment
  aws_region           = var.aws_region
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  tags                 = var.tags
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
