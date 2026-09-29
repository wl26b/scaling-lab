variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "vpc_cidr" {
  type        = string
  description = "Private IP range for the whole VPC"
  default     = "10.0.0.0/16" # 10.0.0.0 – 10.0.255.255, ~65k addresses
}

variable "app_instance_type" {
  type        = string
  description = "Single-server instance size (t4g.small = 2 vCPU ARM, 2 GB RAM, ~$0.02/hr)"
  default     = "t4g.small"
}

variable "loadgen_enabled" {
  type    = bool
  default = true
}

variable "loadgen_instance_type" {
  type = string
  # Free-plan accounts only allow free-tier-eligible types; m7i-flex.large is the largest of those.
  description = "Load generator size (m7i-flex.large = 2 vCPU x86, 8 GB RAM). k6 needs RAM per VU."
  default     = "m7i-flex.large"
}

variable "db_instance_class" {
  type        = string
  description = "RDS size (db.t4g.micro = 2 vCPU ARM, 1 GB RAM: the Free plan's size)"
  default     = "db.t4g.micro"
}
