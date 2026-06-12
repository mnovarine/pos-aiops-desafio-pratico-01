output "bucket_arn" {
  description = "ARN do bucket S3 provisionado"
  value       = aws_s3_bucket.this.arn
}

output "bucket_name" {
  description = "Nome (ID) do bucket S3 provisionado"
  value       = aws_s3_bucket.this.id
}

output "bucket_domain_name" {
  description = "Nome de domínio global do bucket S3 (path-style)"
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Nome de domínio regional do bucket S3"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_hosted_zone_id" {
  description = "Hosted zone ID do bucket S3 (usado em registros Route 53 ALIAS)"
  value       = aws_s3_bucket.this.hosted_zone_id
}
