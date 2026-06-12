---
nome: Criar Módulo Terraform para Bucket S3
descricao: Gera a estrutura completa de um módulo Terraform interno para provisionar bucket S3 com versionamento, criptografia, bloqueio de acesso público e logging.
versao: 1.0.0
tags: [terraform, aws, s3, módulo, infraestrutura-como-código]
modelo: Claude Sonnet 4.6
inputs:
  - nome: owner
    descricao: Time ou pessoa responsável pelo recurso, aplicado na tag obrigatória Owner
  - nome: cost_center
    descricao: Centro de custo para alocação de despesas de nuvem, aplicado na tag obrigatória CostCenter
  - nome: environment
    descricao: Ambiente de deploy (dev, staging ou production), usado no nome do bucket e na tag Environment
  - nome: bucket_name
    descricao: Nome base do bucket em kebab-case, sem o prefixo hvt- e sem sufixo de ambiente
  - nome: kms_key_arn
    descricao: ARN da chave KMS para criptografia SSE-KMS; quando ausente, aplica SSE-S3 (AES256) como mínimo
  - nome: logging_bucket
    descricao: Nome do bucket de destino para logs de acesso; quando ausente, o logging é desabilitado
---

## Objetivo

Gerar a estrutura completa de um módulo Terraform interno para provisionar um bucket S3 na AWS, seguindo as convenções do time: prefixo `hvt-` nos nomes de recursos, kebab-case para recursos, snake_case para variáveis e tags obrigatórias (`Owner`, `CostCenter`, `Environment`). O módulo deve incluir versionamento habilitado, criptografia com KMS (SSE-S3 como mínimo), bloqueio total de acesso público e logging configurável, organizado nos arquivos `main.tf`, `variables.tf`, `outputs.tf` e `README.md`.

## Quando usar

- Ao criar um novo bucket S3 que precise estar em conformidade com os padrões de segurança e governança do time.
- Ao padronizar recursos de armazenamento com versionamento, criptografia e bloqueio de acesso público já configurados por padrão.
- Ao incorporar um módulo reutilizável de S3 na base de IaC em workspaces de múltiplos ambientes (dev, staging, production).
- Ao garantir que as tags obrigatórias e a convenção de naming com prefixo `hvt-` sejam aplicadas automaticamente.

## Exemplo de uso

```hcl
module "s3_app_assets" {
  source = "../../modules/s3-bucket"

  bucket_name = "app-assets"
  environment = "production"
  owner       = "plataforma"
  cost_center = "CC-1042"
}
```

## Output

[modules/s3-bucket](modules/s3-bucket)