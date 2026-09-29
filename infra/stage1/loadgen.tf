# ── Load generator: a separate, bigger EC2 instance that runs k6 ───────────
#
# Toggle with a variable, so you can remove just this (the priciest part) and keep the server:
#   terraform apply -var loadgen_enabled=false

# The load generator uses an Intel (x86) instance type, so it needs the x86 build of Ubuntu.
data "aws_ami" "ubuntu_x86" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# No inbound rules at all: nothing needs to connect *to* the load generator.
resource "aws_security_group" "loadgen" {
  name        = "scaling-lab-loadgen"
  description = "Load generator: outbound only"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_egress_rule" "loadgen_all" {
  security_group_id = aws_security_group.loadgen.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_instance" "loadgen" {
  # count = 1 creates it, count = 0 removes it. Refer to it as aws_instance.loadgen[0].
  count = var.loadgen_enabled ? 1 : 0

  ami                    = data.aws_ami.ubuntu_x86.id
  instance_type          = var.loadgen_instance_type
  subnet_id              = aws_subnet.public[local.azs[0]].id # same AZ as the server: no cross-AZ latency
  vpc_security_group_ids = [aws_security_group.loadgen.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name # same role: just Session Manager

  user_data = templatefile("${path.module}/templates/loadgen.sh.tftpl", {
    social_js    = filebase64("${path.module}/../../loadtest/social.js")
    run_steps_sh = filebase64("${path.module}/../../loadtest/run-steps.sh")
    target_url   = "http://${aws_instance.app.private_ip}" # private IP: traffic never leaves the VPC
  })
  user_data_replace_on_change = true

  tags = { Name = "scaling-lab-loadgen" }

  lifecycle {
    ignore_changes = [ami]
  }
}
