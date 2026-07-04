data "aws_caller_identity" "current" {}

# Empaqueta el código del Lambda authorizer desde el repo clonado localmente
data "archive_file" "lambda_auth" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/lambda_auth_built.zip"
}
