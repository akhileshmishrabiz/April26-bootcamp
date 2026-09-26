# Writes ecommerce secrets into Vault's KV v2 `secret/` mount.
# Paths: secret/ecommerce/<env>/{database,redis,rabbitmq,app,razorpay,aws}

resource "vault_kv_secret_v2" "database" {
  for_each = local.vault_envs

  mount = "secret"
  name  = "ecommerce/${each.key}/database"
  data_json = jsonencode({
    username = var.db_user
    password = random_password.db[each.key].result
  })
}

resource "vault_kv_secret_v2" "redis" {
  for_each = local.vault_envs

  mount = "secret"
  name  = "ecommerce/${each.key}/redis"
  data_json = jsonencode({
    password = random_password.redis[each.key].result
  })
}

resource "vault_kv_secret_v2" "rabbitmq" {
  for_each = local.vault_envs

  mount = "secret"
  name  = "ecommerce/${each.key}/rabbitmq"
  data_json = jsonencode({
    username = var.rabbitmq_user
    password = random_password.rabbitmq[each.key].result
  })
}

resource "vault_kv_secret_v2" "app" {
  for_each = local.vault_envs

  mount = "secret"
  name  = "ecommerce/${each.key}/app"
  data_json = jsonencode({
    jwt_secret = random_password.jwt[each.key].result
  })
}

resource "vault_kv_secret_v2" "razorpay" {
  for_each = local.vault_envs

  mount = "secret"
  name  = "ecommerce/${each.key}/razorpay"
  data_json = jsonencode({
    key_id         = var.razorpay_key_id
    key_secret     = var.razorpay_key_secret
    webhook_secret = var.razorpay_webhook_secret
  })
}

resource "vault_kv_secret_v2" "aws" {
  for_each = local.vault_envs

  mount = "secret"
  name  = "ecommerce/${each.key}/aws"
  data_json = jsonencode({
    access_key_id     = var.aws_access_key_id
    secret_access_key = var.aws_secret_access_key
  })
}
