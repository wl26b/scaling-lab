# ── The app instance: nginx + Node only. Postgres now lives in RDS (database.tf) ──

# Latest official Ubuntu 24.04 image for ARM (Graviton). 099720109477 is Canonical's AWS account.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }
}

# Firewall for the server. Stateful: replies to allowed traffic are let back out automatically.
resource "aws_security_group" "app" {
  name        = "scaling-lab-stage2-app"
  description = "App instance: HTTP from inside the VPC only"
  vpc_id      = aws_vpc.main.id
}

# Port 80 from anything in our VPC (the load generator). Nothing from the internet.
resource "aws_vpc_security_group_ingress_rule" "app_http" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# Outbound anywhere: apt/npm downloads, and the Session Manager agent calling home to AWS.
resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ── IAM: let the instance register with Session Manager ────────────────────
# A role is an identity the EC2 instance "assumes"; the policy says what that identity may do.
resource "aws_iam_role" "instance" {
  name = "scaling-lab-stage2-instance"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" } # only EC2 instances may wear this role
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" # AWS-managed policy for SSM
}

# Let the app read the database password (only this one secret).
resource "aws_iam_role_policy" "read_db_secret" {
  name = "read-db-secret"
  role = aws_iam_role.instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = aws_db_instance.main.master_user_secret[0].secret_arn
    }]
  })
}

# The wrapper EC2 needs to attach a role to an instance.
resource "aws_iam_instance_profile" "instance" {
  name = "scaling-lab-stage2-instance"
  role = aws_iam_role.instance.name
}

# ── The instance ───────────────────────────────────────────────────────────
resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.public[local.azs[0]].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  # Burstable (t4g) instances throttle once CPU credits run out. "unlimited" keeps full
  # speed and bills any surplus by the hour: pennies for a test, and consistent results.
  credit_specification {
    cpu_credits = "unlimited"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
  }

  # First-boot script: sets up the machine (packages, nginx, DB connection settings). No app code:
  # that's shipped separately by scripts/deploy.sh, so code changes never touch this instance's lifecycle.
  user_data = templatefile("${path.module}/templates/bootstrap.sh.tftpl", {
    region        = var.region
    db_host       = aws_db_instance.main.address
    db_name       = aws_db_instance.main.db_name
    db_user       = aws_db_instance.main.username
    db_secret_arn = aws_db_instance.main.master_user_secret[0].secret_arn
  })
  # user_data only runs on first boot, so changing it means we want a fresh machine.
  user_data_replace_on_change = true

  tags = { Name = "scaling-lab-app" }

  lifecycle {
    # A newer Ubuntu image appearing shouldn't make Terraform rebuild the server on the next apply.
    ignore_changes = [ami]
  }
}
