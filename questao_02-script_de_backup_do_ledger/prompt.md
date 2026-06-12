## Prompt

```
# Role
Você é um SRE sênior responsável por automatizar rotinas operacionais.

# Task
Crie um script Bash de backup automático diário para um banco PostgreSQL com pg_dump, incluindo compactação com gzip, subir o arquivo pro bucket S3 hvt-ledger-backups via aws s3 cp, rotação de backups antigos (manter últimos 30 dias) e sair com exit code adequado em caso de falha. A log de execução deverá ser armazenada localmente em /var/log/ledger-backup.log, contendo timestamp. Criar a cron com a execução diária.

Host onde será executado o script: ledger-db.internal.hvt.io
Porta: 5432
Banco: ledger_prod
Usuário de backup: backup_user
Senha: variável de ambiente PGPASSWORD, populada pelo AWS Secrets Manager via IAM role da instância
Região AWS: us-east-1
SO da instância: Ubuntu 22.04 LTS
Diretório de trabalho com 80 GB livres: /var/backups/ledger
Tamanho médio atual do dump compactado: ~12 GB

# Format
Script Bash comentado, com cabeçalho explicando uso e variáveis configuráveis no topo do arquivo.
```