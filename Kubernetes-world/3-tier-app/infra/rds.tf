# 2 rds private subnets  
# create subnet group from that
# rds instance
# random password for the rds instance
# store creds in secret manager

# private subnets

 # 2 private subnet for database
resource "aws_subnet" "rds_1" {
  cidr_block        = "10.0.5.0/24"
  availability_zone = "ap-south-1a"
  vpc_id            = data.aws_vpc.main.id

  tags = {
    Name = "RDS Private Subnet 1"
  }
}

resource "aws_security_group" "rds" {
  name   = "k8s-3tier-rds-sg"
  vpc_id = data.aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    # security group of eks nodes can be added here instead of
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k8s-3tier-rds-sg"
  }
}

resource "aws_subnet" "rds_2" {
  cidr_block        = "10.0.6.0/24"
  availability_zone = "ap-south-1b"
  vpc_id            = data.aws_vpc.main.id

  tags = {
    Name = "RDS Private Subnet 2"
  }
}


# subnet group (a group of subnets)
resource "aws_db_subnet_group" "postgres" {
  name        = "devopsdozo-rds-db-subnet-group"
  description = "Subnet group for RDS instance"
  subnet_ids = [
    aws_subnet.rds_1.id,
    aws_subnet.rds_2.id
  ]
  # subnet_ids =["subnet-0f42a1b9efaf4e602", "subnet-0395e32fc16981198"]

  tags = {
    Name        = "devopsdozo-db-subnet-group"
  }
}

# Generate the password for the database

resource "random_password" "db_password" {
  length           = 10
  special          = false
  override_special = "abcdgktyhtfAZVNNHDD1223434"
}


# create the rds instance

resource "aws_db_instance" "postgres" {
  identifier            = "devopsdozo"
  allocated_storage     = 30
  max_allocated_storage = 50
  engine                = "postgres"
  engine_version        = 17.5
  instance_class        = "db.t3.medium"
  username              = "postgres"
  password              = random_password.db_password.result
  port                  = 5432
  publicly_accessible   = false
  db_subnet_group_name  = aws_db_subnet_group.postgres.id
  ca_cert_identifier    = "rds-ca-rsa2048-g1"
  storage_encrypted     = true
  storage_type          = "gp3"
  kms_key_id            = aws_kms_key.env_kms.arn
  skip_final_snapshot   = true
  vpc_security_group_ids = [
    aws_security_group.rds.id
  ]

  backup_retention_period    = 7
  db_name                    = "devopsdozodb"
  auto_minor_version_upgrade = true
  deletion_protection        = false
  copy_tags_to_snapshot      = true

  tags = {
    Name = "devopsdozo-db"
  }
}


# secret manager

resource "aws_secretsmanager_secret" "db_link" {
  name                    = "db/devopsdozo-db"
  description             = "DB link"
  recovery_window_in_days = 7
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_secretsmanager_secret_version" "dbs_secret_val" {
  secret_id     = aws_secretsmanager_secret.db_link.id
  secret_string = "postgresql://${aws_db_instance.postgres.username}:${random_password.db_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/${aws_db_instance.postgres.db_name}"

  lifecycle {
    create_before_destroy = true
  }
}

# KMS key 

resource "aws_kms_key" "env_kms" {
  description             = "KMS key for RDS and Secrets Manager"
  deletion_window_in_days = 7

  tags = {
    Name        = "3tier-rds-kms-key"
  }
}

resource "aws_kms_alias" "env_kms_alias" {
  name          = "alias/3tier-rds-kms-key"
  target_key_id = aws_kms_key.env_kms.id
}