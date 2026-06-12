---
nome: Automatizar Backup Diário de Banco PostgreSQL
descricao: Gera um script Bash de backup automático do PostgreSQL com compactação gzip, upload para S3 e rotação de backups antigos.
versao: 1.0.0
tags: [backup, postgresql, bash, aws-s3, automação]
modelo: Claude Sonnet 4.6
inputs:
  - nome: host
    descricao: Endereço do servidor PostgreSQL onde o script será executado
  - nome: porta
    descricao: Porta de conexão do PostgreSQL
  - nome: banco
    descricao: Nome do banco de dados a ser copiado
  - nome: usuario_backup
    descricao: Usuário PostgreSQL com permissão de leitura para o dump
  - nome: bucket_s3
    descricao: Nome do bucket S3 de destino para armazenamento dos backups
  - nome: regiao_aws
    descricao: Região AWS onde o bucket S3 está alocado
  - nome: so_instancia
    descricao: Sistema operacional da instância onde o script será executado
  - nome: diretorio_trabalho
    descricao: Caminho local com espaço suficiente para armazenar o dump temporário
  - nome: tamanho_dump
    descricao: Estimativa do tamanho médio do dump compactado, usada para validação de espaço livre
---

# Automatizar Backup Diário de Banco PostgreSQL

## Objetivo

Gerar um script Bash de backup automático diário para um banco PostgreSQL, cobrindo todas as etapas da rotina operacional: dump via `pg_dump`, compactação com `gzip`, upload para bucket S3, rotação automática de backups com mais de 30 dias, log local com timestamp e registro de cron para execução diária. O script deve sair com exit codes distintos por etapa para facilitar triagem em alertas e automações.

## Quando usar

- Quando for necessário automatizar o backup diário de um banco PostgreSQL em ambiente de produção.
- Quando os backups precisam ser armazenados em bucket S3 e rotacionados automaticamente por política de retenção.
- Quando a credencial do banco é gerenciada via AWS Secrets Manager injetada por IAM role, sem armazenar senha em disco.
- Quando a instância executa Ubuntu e o script precisa ser operável tanto por cron quanto manualmente por SREs.

## Exemplo de uso

```bash
# Copiar o script para o servidor
sudo cp ledger_backup.sh /opt/scripts/ledger_backup.sh
sudo chmod +x /opt/scripts/ledger_backup.sh

# Registrar a cron (executa diariamente às 02:00)
sudo /opt/scripts/ledger_backup.sh --install-cron

# Execução manual (PGPASSWORD deve estar populada pela IAM role)
sudo /opt/scripts/ledger_backup.sh
```

## Limitações conhecidas

- O script pressupõe autenticação via IAM role da instância; outros métodos de injeção de credencial (ex.: `.pgpass`, Vault) exigem adaptação.
- Validação de espaço livre é baseada na estimativa de tamanho do dump fornecida como input; dumps maiores que o estimado podem falhar na etapa de compactação.
- A rotação de backups no S3 usa `s3api list-objects-v2` com filtro por `LastModified`; objetos versionados ou com lifecycle rules no bucket podem interferir no comportamento esperado.