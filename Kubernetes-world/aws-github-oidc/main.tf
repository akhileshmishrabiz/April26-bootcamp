locals {
  github_repo = [
    { user = "akhileshmishrabiz", repo = "April26-bootcamp", branch = "main" },
    { user = "akhileshmishrabiz", repo = "k8sbootcamp-march26", branch = "main" },
    { user = "akhileshmishrabiz", repo = "july-devops", branch = "*" },
  ]


  # branch = "main" -> repo:OWNER/REPO:ref:refs/heads/main
  # branch = "*"     -> repo:OWNER/REPO:*  (any ref, tag, environment, etc.)
  github_oidc_subjects = distinct([
    for r in local.github_repo :
    r.branch == "*" ?
    "repo:${r.user}/${r.repo}:*" :
    "repo:${r.user}/${r.repo}:ref:refs/heads/${r.branch}"
  ])
}


resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  tags = {
    Name = "AWS-GH-aug26"
  }
}


resource "aws_iam_role" "aws_github_oidc_aug26" {
  name = "aws-github-oidc-aug26"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.github_oidc_subjects
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "GitHub-Actions-aws-aug26"
  }
}

resource "aws_iam_role_policy_attachment" "attach_ecr_policy" {
  role       = aws_iam_role.aws_github_oidc_aug26.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}


output "aws_iam_role_arn" {
  value = aws_iam_role.aws_github_oidc_aug26.arn
}