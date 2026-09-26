# Credentials — never committed. One set per environment for isolation.

resource "random_password" "db" {
  for_each = local.vault_envs

  length  = 24
  special = false
}

resource "random_password" "redis" {
  for_each = local.vault_envs

  length  = 24
  special = false
}

resource "random_password" "rabbitmq" {
  for_each = local.vault_envs

  length  = 24
  special = false
}

resource "random_password" "jwt" {
  for_each = local.vault_envs

  length  = 48
  special = false
}
