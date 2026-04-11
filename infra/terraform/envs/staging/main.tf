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

module "ecr" {
  source                = "../../modules/ecr"
  repository_names      = var.ecr_repository_names
  image_retention_count = var.ecr_image_retention_count
  image_tag_mutability  = var.ecr_image_tag_mutability
  tags                  = var.tags
}

module "eks" {
  source                = "../../modules/eks"
  environment           = var.environment
  aws_region            = var.aws_region
  kubernetes_version    = var.kubernetes_version
  cluster_role_arn      = module.iam.eks_cluster_role_arn
  node_role_arn         = module.iam.eks_node_role_arn
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.private_subnet_ids
  node_instance_types   = var.node_instance_types
  node_desired_size     = var.node_desired_size
  node_min_size         = var.node_min_size
  node_max_size         = var.node_max_size
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs   = var.public_access_cidrs
  tags                  = var.tags
}
