output "cicd_role_arn" {
  description = "CI/CD IAM role ARN"
  value       = var.github_oidc_provider_arn != "" ? aws_iam_role.cicd[0].arn : ""
}

output "terraform_role_arn" {
  description = "Terraform execution IAM role ARN"
  value       = aws_iam_role.terraform.arn
}

output "eks_cluster_role_arn" {
  description = "EKS cluster IAM role ARN"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  description = "EKS node IAM role ARN"
  value       = aws_iam_role.eks_node.arn
}

output "argocd_role_arn" {
  description = "ArgoCD IAM role ARN"
  value       = var.eks_oidc_provider_arn != "" ? aws_iam_role.argocd[0].arn : ""
}
