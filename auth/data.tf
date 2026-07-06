data "aws_caller_identity" "current" {}

# Empaqueta desde source_dir si se provee, si no usa el zip pre-construido
data "archive_file" "lambda_auth" {
  count       = var.lambda_source_dir != "" ? 1 : 0
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/lambda_auth_built.zip"
}

locals {
  lambda_zip_path = var.lambda_source_dir != "" ? data.archive_file.lambda_auth[0].output_path : var.lambda_zip_path
  lambda_zip_hash = var.lambda_source_dir != "" ? data.archive_file.lambda_auth[0].output_base64sha256 : filebase64sha256(var.lambda_zip_path)
}
