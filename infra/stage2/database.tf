# ── The database: managed Postgres (RDS) in the private subnets ────────────
#
#   app instance (public subnet) ──5432──▶ RDS Postgres (private subnets)
#                                          only the app's security group may connect

# Which subnets RDS may place the database in. RDS insists on at least two AZs.
resource "aws_db_subnet_group" "main" {
  name       = "scaling-lab"
  subnet_ids = [for s in aws_subnet.private : s.id]
}

resource "aws_security_group" "db" {
  name        = "scaling-lab-db"
  description = "Postgres: only from the app instances"
  vpc_id      = aws_vpc.main.id
}

# The rule names a security group, not an IP range: "anything wearing the app SG may connect".
# Keeps working however many app instances there are, or whatever IPs they get (stage 3).
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# Postgres settings. RDS doesn't let you edit postgresql.conf; you set values in a parameter group.
resource "aws_db_parameter_group" "main" {
  name   = "scaling-lab-pg16"
  family = "postgres16"

  # Log every statement that takes longer than 200 ms *inside Postgres*, and any lock wait over 1 s.
  # Cheap (only slow statements are logged) and it's how we proved the stage 2 slow tail came from
  # the database itself. Read with: aws rds download-db-log-file-portion
  parameter {
    name  = "log_min_duration_statement"
    value = "200"
  }
  parameter {
    name  = "log_lock_waits"
    value = "1"
  }
}

resource "aws_db_instance" "main" {
  identifier     = "scaling-lab"
  engine         = "postgres"
  engine_version = "16" # same major version as stage 1; RDS picks the latest 16.x
  instance_class = var.db_instance_class

  db_name  = "social"
  username = "app"
  # RDS generates the password and keeps it in Secrets Manager. It never appears in our code or state.
  manage_master_user_password = true

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  parameter_group_name   = aws_db_parameter_group.main.name
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false # no public IP; only reachable inside the VPC
  multi_az               = false # one instance, one AZ (a standby in a second AZ doubles the cost)

  backup_retention_period = 1    # keep 1 day of automatic backups
  skip_final_snapshot     = true # lab: don't keep a snapshot on destroy
  deletion_protection     = false
  apply_immediately       = true # apply changes now, not in the next maintenance window
}
