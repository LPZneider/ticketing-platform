# ─── IAM EXECUTION ROLE ──────────────────────────────────────────────────────
resource "aws_iam_role" "execution" {
  name = "role-exec-${local.name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = local.resource_tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ─── IAM TASK ROLE — solo lectura DynamoDB ───────────────────────────────────
resource "aws_iam_role" "task" {
  name = "role-task-${local.name}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
  tags = local.resource_tags
}

resource "aws_iam_role_policy" "task" {
  name = "policy-task-${local.name}"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Read-only: solo consultas de disponibilidad
        Sid    = "DynamoDBReadOnly"
        Effect = "Allow"
        Action = ["dynamodb:GetItem", "dynamodb:Query"]
        Resource = [
          var.tickets_table_arn,
          "${var.tickets_table_arn}/index/idx_status"
        ]
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = [var.kms_dynamodb_arn]
      }
    ]
  })
}
