locals {
  common_tags = {
    Owner       = var.owner
    CostCenter  = var.cost_center
    Environment = var.environment
  }

  bucket_name = "hvt-${var.bucket_name}-${var.environment}"
}

# ------------------------------------------------------------------------------
# Bucket S3
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name

  tags = merge(local.common_tags, var.additional_tags, {
    Name = local.bucket_name
  })
}

# ------------------------------------------------------------------------------
# Block Public Access — total
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# Ownership Controls (necessário para desabilitar ACLs corretamente)
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ------------------------------------------------------------------------------
# Versionamento
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# ------------------------------------------------------------------------------
# Criptografia — SSE-KMS se kms_key_arn fornecido, SSE-S3 (AES256) caso contrário
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }

    bucket_key_enabled = var.kms_key_arn != null ? true : false
  }
}

# ------------------------------------------------------------------------------
# Logging de acesso
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_logging" "this" {
  count = var.logging_bucket != null ? 1 : 0

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.logging_bucket
  target_prefix = coalesce(var.logging_prefix, "s3-access-logs/${local.bucket_name}/")
}
