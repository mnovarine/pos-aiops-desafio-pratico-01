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

## Modelo

Claude Sonnet 4.6

## Output

Script de Backup → [ledger_backup.sh](ledger_backup.sh)

## Output do Prompt

Script criado em questao_02-script_de_backup_do_ledger/ledger_backup.sh. Destaques do que foi implementado:

**Etapas do backup (com exit codes distintos):**

- `check_prerequisites` (exit 1) — valida `pg_dump`, `gzip`, `aws`, `PGPASSWORD` e espaço livre (mínimo 20 GB de margem)
- `run_pg_dump` (exit 2) — dump em formato plain via `PGPASSWORD` do ambiente, nunca hardcoded
- `compress_dump` (exit 3) — `gzip --fast` para minimizar a janela de uso de disco
- `upload_to_s3` (exit 4) — `aws s3 cp` para `s3://hvt-ledger-backups/daily/` com storage class `STANDARD_IA`
- `rotate_old_backups` (exit 5) — `s3api list-objects-v2` filtra por `LastModified` e remove backups com mais de 30 dias
- `cleanup_local` — remove o `.gz` temporário após upload bem-sucedido

Segurança: `PGPASSWORD` nunca aparece no log nem em argumentos de linha de comando; credencial injetada exclusivamente via IAM role da instância.


### Instalação

```bash
# Copiar o script para o servidor
sudo cp ledger_backup.sh /opt/scripts/ledger_backup.sh
sudo chmod +x /opt/scripts/ledger_backup.sh

# Registrar a cron (executa diariamente às 02:00)
sudo /opt/scripts/ledger_backup.sh --install-cron

# Verificar a cron registrada
crontab -l
```

### Execução manual

```bash
# PGPASSWORD deve estar populada pelo AWS Secrets Manager via IAM role
sudo /opt/scripts/ledger_backup.sh
```

### Estrutura do bucket S3

```
s3://hvt-ledger-backups/
└── daily/
    ├── ledger_prod_20260101_020001.dump.gz
    ├── ledger_prod_20260102_020001.dump.gz
    └── ...  (últimos 30 dias mantidos automaticamente)
```

### Decisões de projeto

| Decisão | Justificativa |
|---|---|
| `set -euo pipefail` | Falha rápida em qualquer erro não tratado |
| `--format=plain` no pg_dump | Compatível com restauração via `psql` sem dependência de versão do pg_restore |
| `gzip --fast` | Prioriza velocidade; reduz janela de backup no disco (~12 GB compactados) |
| `STANDARD_IA` no S3 | Backups são acessados raramente; reduz custo de armazenamento |
| Exit codes distintos (1-5) | Facilita triagem em alertas e automações de observabilidade |
| `PGPASSWORD` via IAM role | Evita credencial em disco; segue princípio de least-privilege |
| Rotação via `s3api list-objects-v2` | Permite filtro por `LastModified` sem dependência de nome de arquivo |