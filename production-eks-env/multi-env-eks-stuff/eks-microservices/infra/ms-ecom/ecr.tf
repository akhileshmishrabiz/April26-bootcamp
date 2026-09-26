locals {
  ecr_repos = [
    for repo in [
      "ecommerce-product-service",
      "ecommerce-user-service",
      "ecommerce-cart-service",
      "ecommerce-order-service",
      "ecommerce-payment-service",
      "ecommerce-notification-service",
      "ecommerce-api-gateway",
      "ecommerce-frontend",
      "ecommerce-seed",
    ] : "${local.env_prefix}${repo}"
  ]
}

resource "aws_ecr_repository" "this" {
  for_each             = toset(local.ecr_repos)
  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
