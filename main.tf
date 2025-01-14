locals {
  principals_readonly_access_non_empty = signum(length(var.principals_readonly_access))
  principals_full_access_non_empty     = signum(length(var.principals_full_access))
  ecr_need_policy                      = length(var.principals_full_access) + length(var.principals_readonly_access) > 0 ? "true" : "false"
}

module "label" {
  source     = "git::https://github.com/betterworks/terraform-null-label.git?ref=tags/0.14.0"
  enabled    = var.enabled
  namespace  = var.namespace
  stage      = var.stage
  name       = var.name
  delimiter  = var.delimiter
  attributes = var.attributes
  tags       = var.tags
}

resource "aws_ecr_repository" "default" {
  count = var.enabled == "true" ? 1 : 0
  name  = var.use_fullname == "true" ? module.label.id : module.label.name
  tags  = module.label.tags
}

resource "aws_ecr_lifecycle_policy" "default" {
  count      = var.enabled == "true" ? 1 : 0
  repository = aws_ecr_repository.default[0].name

  policy = <<EOF
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Remove untagged images",
      "selection": {
        "tagStatus": "untagged",
        "countType": "imageCountMoreThan",
        "countNumber": 1
      },
      "action": {
        "type": "expire"
      }
    },
    {
      "rulePriority": 2,
      "description": "Rotate images when reach ${var.max_image_count} images stored",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": ${var.max_image_count}
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
EOF

}

data "aws_iam_policy_document" "empty" {
}

data "aws_iam_policy_document" "resource_readonly_access" {
  statement {
    sid = "ReadonlyAccess"
    effect = "Allow"

    principals {
      type = "AWS"

      identifiers = var.principals_readonly_access
    }

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
    ]
  }
}

data "aws_iam_policy_document" "resource_full_access" {
  statement {
    sid = "FullAccess"
    effect = "Allow"

    principals {
      type = "AWS"

      identifiers = var.principals_full_access
    }

    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetRepositoryPolicy",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchGetImage",
    ]
  }
}

data "aws_iam_policy_document" "resource" {
  source_policy_documents = local.principals_readonly_access_non_empty != 0 ? [data.aws_iam_policy_document.resource_readonly_access.json] : [data.aws_iam_policy_document.empty.json]
  override_policy_documents = local.principals_full_access_non_empty != 0 ? [data.aws_iam_policy_document.resource_full_access.json] : [data.aws_iam_policy_document.empty.json]
}

resource "aws_ecr_repository_policy" "default" {
  count = local.ecr_need_policy == "true" && var.enabled == "true" ? 1 : 0
  repository = aws_ecr_repository.default[0].name
  policy = data.aws_iam_policy_document.resource.json
}

