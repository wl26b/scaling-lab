# ── Artifact bucket: where each deploy's release package is stored ─────────
#
#   your Mac ──upload──▶ S3 bucket ──download──▶ server
#   (scripts/deploy.sh)   releases/<version>.tar.gz

resource "aws_s3_bucket" "artifacts" {
  # Bucket names are globally unique across all of AWS; a prefix lets AWS add a random suffix.
  bucket_prefix = "scaling-lab-artifacts-"

  # Allow `terraform destroy` to delete the bucket even when it still holds releases.
  force_destroy = true
}

# Let the server's role download from this bucket (read-only, this bucket only).
resource "aws_iam_role_policy" "read_artifacts" {
  name = "read-artifacts"
  role = aws_iam_role.instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.artifacts.arn}/*"
    }]
  })
}
