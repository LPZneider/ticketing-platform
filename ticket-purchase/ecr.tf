resource "aws_ecr_repository" "svc" {
  name                 = "ecr-${local.name}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.resource_tags
}

resource "aws_ecr_lifecycle_policy" "svc" {
  repository = aws_ecr_repository.svc.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Retener últimas 5 imágenes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
