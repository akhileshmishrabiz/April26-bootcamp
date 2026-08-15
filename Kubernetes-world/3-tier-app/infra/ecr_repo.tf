# ecr repo for frontend and backend

resource "aws_ecr_repository" "frontend" {
  name = "augk8s26-frontend"
}

resource "aws_ecr_repository" "backend" {
  name = "augk8s26-backend"
}