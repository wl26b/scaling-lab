# ── The network ────────────────────────────────────────────────────────────
#
#   VPC 10.0.0.0/16
#   ├── public subnet 10.0.0.0/24  (AZ a) ─┐
#   ├── public subnet 10.0.1.0/24  (AZ b) ─┼─▶ route table: 0.0.0.0/0 → internet gateway
#   └── internet gateway ──────────────────┘

# Ask AWS which availability zones (separate data centres) this region has.
# A "data" block reads something that already exists; it creates nothing.
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Two AZs. Stage 1 only uses one, but the load balancer and RDS in later stages require two.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "scaling-lab" }
}

# The VPC's door to the internet. Without it, nothing inside can reach out or be reached.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id # referencing another resource also tells Terraform to create the VPC first

  tags = { Name = "scaling-lab" }
}

# One subnet per AZ. for_each creates one resource per map entry:
#   aws_subnet.public["ap-southeast-1a"], aws_subnet.public["ap-southeast-1b"]
resource "aws_subnet" "public" {
  for_each = { for i, az in local.azs : az => i }

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, each.value) # 10.0.0.0/24, 10.0.1.0/24
  map_public_ip_on_launch = true                                    # instances here get a public IP

  tags = { Name = "scaling-lab-public-${each.key}" }
}

# "Public" just means: this subnet's route table sends internet traffic to the internet gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "scaling-lab-public" }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}
