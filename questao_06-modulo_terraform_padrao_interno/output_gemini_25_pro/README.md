
# Módulo Terraform para S3 Bucket

Este módulo provisiona um bucket Amazon S3 com um conjunto de melhores práticas de segurança e governança.

## Funcionalidades

- **Nomenclatura Padronizada**: Usa o prefixo `hvt-` e o ambiente no nome do bucket.
- **Versionamento**: Habilitado para manter o histórico de objetos.
- **Criptografia**: Suporta SSE-S3 (padrão) ou SSE-KMS para criptografia no lado do servidor.
- **Bloqueio de Acesso Público**: Todas as configurações de bloqueio de acesso público estão ativadas.
- **Logging**: Configura o logging de acesso ao servidor, enviando logs para um bucket de destino.
- **Tags Obrigatórias**: Aplica as tags `Owner`, `CostCenter` e `Environment` a todos os recursos.

## Exemplo de Uso

```hcl
module "s3_secure_bucket" {
  source = "./modules/s3-bucket"

  bucket_name     = "meu-bucket-seguro"
  environment     = "production"
  owner           = "equipe-alpha"
  cost_center     = "12345"
  log_bucket_name = "meu-bucket-de-logs"
  
  # Opcional: Para usar SSE-KMS
  # kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/sua-chave-kms"

  tags = {
    Project = "Projeto Secreto"
  }
}
```

## Entradas (Inputs)

| Nome            | Descrição                                                                                             | Tipo       | Padrão | Obrigatório |
|-----------------|-------------------------------------------------------------------------------------------------------|------------|--------|:-----------:|
| `bucket_name`   | O nome do bucket S3. Será prefixado com 'hvt-'.                                                       | `string`   | -      |     sim     |
| `environment`   | Ambiente de implantação (ex: dev, staging, production).                                               | `string`   | -      |     sim     |
| `owner`         | O proprietário do recurso.                                                                            | `string`   | -      |     sim     |
| `cost_center`   | O centro de custo associado ao recurso.                                                               | `string`   | -      |     sim     |
| `log_bucket_name`| O nome do bucket S3 para armazenar os logs de acesso.                                                 | `string`   | -      |     sim     |
| `kms_key_id`    | O ID da chave KMS para criptografia do lado do servidor. Se não for fornecido, SSE-S3 será usado.       | `string`   | `null` |     não     |
| `tags`          | Um mapa de tags para adicionar ao bucket S3.                                                          | `map(string)`| `{}`   |     não     |

## Saídas (Outputs)

| Nome             | Descrição                |
|------------------|--------------------------|
| `s3_bucket_arn`  | O ARN do bucket S3.      |
| `s3_bucket_name` | O nome do bucket S3.     |
```
