# A cost safety net: AWS emails you when spend this month crosses a threshold.
# Budgets are free, and this is the only thing we'll leave running between sessions.

terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "ap-southeast-1"
}

variable "alert_email" {
  type        = string
  description = "Where AWS sends budget alerts"
}

variable "monthly_limit_usd" {
  type    = number
  default = 15
}

resource "aws_budgets_budget" "lab" {
  name         = "scaling-lab"
  budget_type  = "COST"
  limit_amount = var.monthly_limit_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Early warning at 50% of actual spend...
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  # ...and when AWS forecasts you'll go over the limit this month.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
