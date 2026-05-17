# random password

resource "random_password" "rds_password" {
  length = 16
  special = false
  override_special = "asdfgjhkqwrtopASHLSGSAGNAX12345667890"
}


# rds subnet group

resource "aws_db_subnet_group" "this" {
  name = "april-2026-bootcamp-rds-subnet-group"
  description = "Subnet group for rds instance"
  subnet_ids = [aws_subnet.rds_subnet_1.id, aws_subnet.rds_subnet_2.id]
}

# rds instance

resource "aws_db_instance" "this" {
  engine = "postgres"
  engine_version = "15.x"
  instance_class = "t3.micro"
  username = "postgres"
  password = random_password.rds_password.result
  db_name = "mydb"
  db_subnet_group_name = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible = false
  backup_retention_period = 7

}

# aws secret manager for rds password

resource "aws_secretsmanager_secret" "rds_password" {
  name = "april-2026-bootcamp-rds-password"
  description = "Password for rds instance"
}

# aws secret manager version for rds password

resource "aws_secretsmanager_secret_version" "rds_password" {
  secret_id = aws_secretsmanager_secret.rds_password.id
  # db_link = "postgresql://{user}:{password}@{host}:{port}/{database_name}"
  secret_string = "postgresql://${aws_db_instance.this.username}:${random_password.rds_password.result}@${aws_db_instance.this.endpoint}:${aws_db_instance.this.port}/${aws_db_instance.this.db_name}"
}