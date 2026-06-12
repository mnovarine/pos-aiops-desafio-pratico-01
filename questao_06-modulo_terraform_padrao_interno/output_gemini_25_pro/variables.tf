
variable "bucket_name" {
  description = "O nome do bucket S3. Será prefixado com 'hvt-'."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "O nome do bucket deve conter apenas letras minúsculas, números e hífens, e ter entre 3 e 63 caracteres."
  }
}

variable "environment" {
  description = "Ambiente de implantação (ex: dev, staging, production)."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "O ambiente deve ser 'dev', 'staging' ou 'production'."
  }
}

variable "owner" {
  description = "O proprietário do recurso."
  type        = string
}

variable "cost_center" {
  description = "O centro de custo associado ao recurso."
  type        = string
}

variable "log_bucket_name" {
  description = "O nome do bucket S3 para armazenar os logs de acesso."
  type        = string
}

variable "kms_key_id" {
  description = "O ID da chave KMS para criptografia do lado do servidor. Se não for fornecido, SSE-S3 será usado."
  type        = string
  default     = null
}

variable "tags" {
  description = "Um mapa de tags para adicionar ao bucket S3."
  type        = map(string)
  default     = {}
}
