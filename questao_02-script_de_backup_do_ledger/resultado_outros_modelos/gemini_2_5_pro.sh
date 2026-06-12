# SCRIPT GERADO PELO MODELO GEMINI 2.5 PRO

#!/bin/bash
#
# postgres_backup.sh
#
# Autor: GitHub Copilot
# Data: 2026-06-12
#
# Descrição:
#   Este script realiza o backup diário de uma base de dados PostgreSQL.
#   As principais funcionalidades incluem:
#   1. Executar o dump do banco de dados usando pg_dump.
#   2. Compactar o arquivo de dump usando gzip.
#   3. Enviar o backup compactado para um bucket no AWS S3.
#   4. Rotacionar os backups, mantendo apenas os últimos 30 dias (localmente e no S3).
#   5. Registrar todas as operações em um arquivo de log com timestamps.
#   6. Sair com um código de erro apropriado em caso de falha.
#
# Pré-requisitos:
#   - 'postgresql-client' (para pg_dump) e 'aws-cli' instalados.
#   - A variável de ambiente PGPASSWORD deve ser exportada com a senha do banco.
#     (Ex: export PGPASSWORD="sua_senha_segura")
#   - A instância deve ter uma IAM Role com permissões para acessar o AWS Secrets Manager
#     e para ler/escrever/deletar objetos no bucket S3 de destino.
#
# Uso:
#   ./postgres_backup.sh
#
# Agendamento com Cron (execução diária às 02:00):
#   0 2 * * * /caminho/completo/para/postgres_backup.sh
#

# --- Variáveis Configuráveis ---

# Banco de Dados
DB_HOST="ledger-db.internal.hvt.io"
DB_PORT="5432"
DB_NAME="ledger_prod"
DB_USER="backup_user"

# AWS S3
S3_BUCKET="hvt-ledger-backups"
AWS_REGION="us-east-1"

# Diretórios e Arquivos
BACKUP_DIR="/var/backups/ledger"
LOG_FILE="/var/log/ledger-backup.log"
DATE_FORMAT=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_FILE_NAME="${DB_NAME}_${DATE_FORMAT}.sql.gz"
BACKUP_FILE_PATH="${BACKUP_DIR}/${BACKUP_FILE_NAME}"

# Rotação (em dias)
RETENTION_DAYS=30

# --- Funções Auxiliares ---

# Função para registrar mensagens no log
log() {
    local message="$1"
    echo "$(date +"%Y-%m-%d %H:%M:%S") - ${message}" | tee -a "${LOG_FILE}"
}

# Função para tratar erros e sair
handle_error() {
    local message="$1"
    local exit_code="$2"
    log "ERRO: ${message}"
    exit "${exit_code}"
}

# --- Início da Execução ---

# Garante que o diretório de log e backup existam
mkdir -p "$(dirname ${LOG_FILE})"
mkdir -p "${BACKUP_DIR}"

log "--- Início do script de backup do banco '${DB_NAME}' ---"

# 1. Validação da variável de ambiente PGPASSWORD
if [ -z "${PGPASSWORD}" ]; then
    handle_error "A variável de ambiente PGPASSWORD não está definida." 1
fi

# 2. Execução do Backup com pg_dump e compactação com gzip
log "Realizando dump do banco de dados '${DB_NAME}' para '${BACKUP_FILE_PATH}'..."
pg_dump -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -F c -b -v | gzip > "${BACKUP_FILE_PATH}"

# Verifica o status de saída do pipe (pg_dump e gzip)
# ${PIPESTATUS[0]} é o exit code do pg_dump
# ${PIPESTATUS[1]} é o exit code do gzip
if [ "${PIPESTATUS[0]}" -ne 0 ] || [ "${PIPESTATUS[1]}" -ne 0 ]; then
    handle_error "Falha ao executar pg_dump ou gzip. Código de saída pg_dump: ${PIPESTATUS[0]}, gzip: ${PIPESTATUS[1]}." 2
fi

log "Dump e compactação concluídos com sucesso."

# 3. Upload para o AWS S3
log "Enviando arquivo '${BACKUP_FILE_NAME}' para o bucket S3 's3://${S3_BUCKET}/'..."
aws s3 cp "${BACKUP_FILE_PATH}" "s3://${S3_BUCKET}/${BACKUP_FILE_NAME}" --region "${AWS_REGION}"

if [ $? -ne 0 ]; then
    handle_error "Falha ao enviar o backup para o S3." 3
fi

log "Upload para o S3 concluído com sucesso."

# 4. Rotação de Backups Antigos

# Rotação local
log "Rotacionando backups locais no diretório '${BACKUP_DIR}' (mantendo ${RETENTION_DAYS} dias)..."
find "${BACKUP_DIR}" -type f -name "*.sql.gz" -mtime +"${RETENTION_DAYS}" -print -delete | while read -r file; do
    log "Backup local removido: ${file}"
done

if [ $? -ne 0 ]; then
    log "Aviso: Ocorreu um problema ao tentar rotacionar os backups locais."
fi

# Rotação no S3
log "Rotacionando backups no S3 (mantendo ${RETENTION_DAYS} dias)..."
# Lista todos os objetos, extrai a data do nome do arquivo, e deleta se for mais antigo que RETENTION_DAYS
aws s3api list-objects --bucket "${S3_BUCKET}" --query "Contents[?LastModified<\`$(date --date='-${RETENTION_DAYS} days' +%Y-%m-%d)\`].[Key]" --output text | tr '\t' '\n' | while read -r key; do
    if [ -n "$key" ]; then
        log "Backup do S3 para remoção: ${key}"
        aws s3 rm "s3://${S3_BUCKET}/${key}"
        if [ $? -ne 0 ]; then
            log "Aviso: Falha ao remover o objeto '${key}' do S3."
        fi
    fi
done

log "Rotação de backups concluída."
log "--- Fim do script de backup ---"

exit 0
