resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = "voicepay-${each.key}"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.tags, {
    Name = "voicepay-${each.key}"
  })
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = toset(var.repository_names)

  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.image_retention_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.image_retention_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
