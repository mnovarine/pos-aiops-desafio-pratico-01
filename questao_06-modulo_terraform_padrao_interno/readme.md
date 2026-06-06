## Prompt

```
# Context
Trabalhamos com Terraform na AWS. Seguimos o padrão de módulos do terraform-aws-modules como referência de estrutura. Usamos workspaces para separar ambientes (dev, staging, production). Convenção de naming: kebab-case para recursos, snake_case para variáveis,  prefixo hvt- nos nomes de recursos e tags obrigatórias em todo recurso: Owner, CostCenter, Environment.

# Action
Crie um Terraform module para provisionar um bucket S3 com versionamento, encryption com KMS (SSE-S3 mínimo), block public access total e logging configurado.

# Result
O module deve conter: main.tf, variables.tf com descrições e validações, outputs.tf com ARN e nome do bucket s3, e um README.md com exemplo de uso. Seguir as convenções de naming definidas no contexto.

# Example
Aqui está a estrutura do nosso modulo de VPC que é a referência que utilizamos:

modules/vpc/main.tf
locals {
  common_tags = {
    Owner       = var.owner
    CostCenter  = var.cost_center
    Environment = var.environment
  }
}

resource "aws_vpc" "this" {
  cidr_block = var.cidr_block
  tags = merge(local.common_tags, {
    Name = "hvt-vpc-${var.environment}"
  })
}

modules/vpc/variables.tf
variable "environment" {
  description = "Nome do ambiente (dev, staging, production)"
  type        = string
}
```

## Modelo

Claude Sonnet 4.6

## Output

[modules/s3-bucket](modules/s3-bucket)