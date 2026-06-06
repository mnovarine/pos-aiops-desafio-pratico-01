# ------------------------------------------------------------------------------
# Tags obrigatórias
# ------------------------------------------------------------------------------
variable "owner" {
  description = "Time ou pessoa responsável pelo recurso (tag Owner)"
  type        = string

  validation {
    condition     = length(var.owner) > 0
    error_message = "A variável owner não pode ser vazia."
  }
}

variable "cost_center" {
  description = "Centro de custo para alocação de despesas (tag CostCenter)"
  type        = string

  validation {
    condition     = length(var.cost_center) > 0
    error_message = "A variável cost_center não pode ser vazia."
  }
}

variable "environment" {
  description = "Nome do ambiente. Deve ser um dos valores: dev, staging, production"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "A variável environment deve ser 'dev', 'staging' ou 'production'."
  }
}

# ------------------------------------------------------------------------------
# Identificação do bucket
# ------------------------------------------------------------------------------
variable "bucket_name" {
  description = "Nome base do bucket S3 em kebab-case, sem o prefixo hvt- e sem sufixo de ambiente. Exemplo: 'app-assets', 'data-lake'. O nome final será hvt-<bucket_name>-<environment>"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,50}[a-z0-9]$", var.bucket_name))
    error_message = "O bucket_name deve conter apenas letras minúsculas, números e hífens (kebab-case), entre 3 e 52 caracteres, sem começar ou terminar com hífen."
  }
}

# ------------------------------------------------------------------------------
# Versionamento
# ------------------------------------------------------------------------------
variable "versioning_enabled" {
  description = "Habilita o versionamento de objetos no bucket S3"
  type        = bool
  default     = true
}

# ------------------------------------------------------------------------------
# Criptografia
# ------------------------------------------------------------------------------
variable "kms_key_arn" {
  description = "ARN da chave KMS gerenciada pelo cliente (CMK) para criptografia SSE-KMS. Quando null, utiliza SSE-S3 (AES256) como algoritmo padrão"
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]{36}$", var.kms_key_arn))
    error_message = "O kms_key_arn deve ser um ARN válido de chave KMS no formato arn:aws:kms:<region>:<account-id>:key/<key-id>."
  }
}

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------
variable "logging_bucket" {
  description = "Nome (ID) do bucket S3 de destino para armazenar os logs de acesso ao bucket. Quando null, o logging é desabilitado"
  type        = string
  default     = null
}

variable "logging_prefix" {
  description = "Prefixo de caminho para os logs de acesso dentro do bucket de destino. Quando null, usa 's3-access-logs/<bucket-name>/'"
  type        = string
  default     = null
}

# ------------------------------------------------------------------------------
# Tags adicionais
# ------------------------------------------------------------------------------
variable "additional_tags" {
  description = "Mapa de tags adicionais a serem mescladas às tags obrigatórias (Owner, CostCenter, Environment)"
  type        = map(string)
  default     = {}
}
