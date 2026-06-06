# terraform-hvt-s3-bucket

Módulo Terraform para provisionar um bucket S3 seguindo os padrões internos da HVT.

Funcionalidades incluídas:
- **Versionamento** habilitado por padrão
- **Criptografia** SSE-KMS (com chave CMK fornecida) ou SSE-S3 (AES256) como mínimo
- **Block Public Access** total (todos os quatro controles habilitados)
- **Ownership Controls** com `BucketOwnerEnforced` (ACLs desabilitadas)
- **Logging de acesso** configurável para bucket de destino
- **Tags obrigatórias** `Owner`, `CostCenter` e `Environment` em todos os recursos
- **Naming automático** no padrão `hvt-<bucket_name>-<environment>`

---

## Uso básico (SSE-S3)

```hcl
module "s3_app_assets" {
  source = "../../modules/s3-bucket"

  bucket_name  = "app-assets"
  environment  = "production"
  owner        = "plataforma"
  cost_center  = "CC-1042"

  logging_bucket = "hvt-s3-access-logs-production"
}
```

O bucket criado terá o nome `hvt-app-assets-production`.

---

## Uso com KMS (SSE-KMS)

```hcl
module "s3_data_lake" {
  source = "../../modules/s3-bucket"

  bucket_name  = "data-lake"
  environment  = terraform.workspace
  owner        = "engenharia-dados"
  cost_center  = "CC-2077"

  kms_key_arn    = "arn:aws:kms:us-east-1:123456789012:key/mrk-1234abcd-12ab-34cd-56ef-1234567890ab"
  logging_bucket = "hvt-s3-access-logs-${terraform.workspace}"
  logging_prefix = "data-lake/"

  additional_tags = {
    Project    = "analytics-platform"
    Compliance = "LGPD"
  }
}

output "data_lake_arn" {
  value = module.s3_data_lake.bucket_arn
}
```

---

## Inputs

| Nome | Descrição | Tipo | Padrão | Obrigatório |
|------|-----------|------|--------|:-----------:|
| `owner` | Time ou pessoa responsável pelo recurso (tag Owner) | `string` | — | sim |
| `cost_center` | Centro de custo para alocação de despesas (tag CostCenter) | `string` | — | sim |
| `environment` | Ambiente: `dev`, `staging` ou `production` | `string` | — | sim |
| `bucket_name` | Nome base do bucket em kebab-case, sem prefixo/sufixo | `string` | — | sim |
| `versioning_enabled` | Habilita versionamento de objetos | `bool` | `true` | não |
| `kms_key_arn` | ARN da chave KMS para SSE-KMS. `null` usa SSE-S3 | `string` | `null` | não |
| `logging_bucket` | ID do bucket de destino para logs de acesso. `null` desabilita | `string` | `null` | não |
| `logging_prefix` | Prefixo para os logs no bucket de destino | `string` | `null` | não |
| `additional_tags` | Tags extras a serem mescladas às tags obrigatórias | `map(string)` | `{}` | não |

---

## Outputs

| Nome | Descrição |
|------|-----------|
| `bucket_arn` | ARN do bucket S3 |
| `bucket_name` | Nome (ID) do bucket S3 |
| `bucket_domain_name` | Nome de domínio global do bucket |
| `bucket_regional_domain_name` | Nome de domínio regional do bucket |
| `bucket_hosted_zone_id` | Hosted zone ID (para Route 53 ALIAS) |

---

## Requisitos

| Nome | Versão |
|------|--------|
| terraform | >= 1.3.0 |
| aws | >= 5.0.0 |

---

## Convenções de naming

- Recursos AWS: `kebab-case` com prefixo `hvt-`
- Variáveis Terraform: `snake_case`
- Nome final do bucket: `hvt-<bucket_name>-<environment>`
- Tags obrigatórias em todos os recursos: `Owner`, `CostCenter`, `Environment`

---

## Notas de segurança

- Block Public Access está sempre habilitado em todos os quatro controles. Não existe variável para desabilitar este comportamento.
- ACLs estão desabilitadas via `BucketOwnerEnforced`. Todo o controle de acesso deve ser feito por Bucket Policy ou IAM.
- Quando `kms_key_arn` é informado, o `bucket_key_enabled` é ativado automaticamente para reduzir chamadas à API KMS e consequentemente os custos.
