# Outputs are printed after apply and readable with `terraform output`.
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnets" {
  value = { for az, s in aws_subnet.public : az => s.cidr_block }
}

output "app_instance_id" {
  value = aws_instance.app.id
}

output "app_private_ip" {
  value = aws_instance.app.private_ip
}

output "shell" {
  description = "Open a shell on the server"
  value       = "aws ssm start-session --target ${aws_instance.app.id}"
}

output "tunnel" {
  description = "Forward the server's port 80 to localhost:8080 on your Mac"
  value       = "aws ssm start-session --target ${aws_instance.app.id} --document-name AWS-StartPortForwardingSession --parameters portNumber=80,localPortNumber=8080"
}

# one() turns a 0-or-1 element list into the element, or null when loadgen is disabled.
output "loadgen_shell" {
  description = "Open a shell on the load generator"
  value       = one([for i in aws_instance.loadgen : "aws ssm start-session --target ${i.id}"])
}

output "artifact_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}

output "db_endpoint" {
  value = aws_db_instance.main.address
}
