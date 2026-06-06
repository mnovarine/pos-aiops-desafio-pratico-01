#!/usr/bin/env bash
# =============================================================================
# ledger_backup.sh — Backup automático diário do PostgreSQL para S3
# =============================================================================
#
# Descrição:
#   Realiza dump do banco ledger_prod, compacta com gzip e envia para o bucket
#   S3 hvt-ledger-backups. Mantém os últimos 30 dias de backups no bucket e
#   remove arquivos locais temporários após o envio. Registra todas as etapas
#   em /var/log/ledger-backup.log com timestamps.
#
# Pré-requisitos:
#   - postgresql-client instalado (pg_dump)
#   - awscli v2 instalado e configurado via IAM role da instância
#   - A variável PGPASSWORD deve estar disponível no ambiente (injetada pelo
#     AWS Secrets Manager via IAM role) ou em /etc/environment
#   - O usuário que executa o script deve ter permissão de escrita em
#     WORK_DIR e LOG_FILE
#
# Uso:
#   chmod +x /opt/scripts/ledger_backup.sh
#   /opt/scripts/ledger_backup.sh
#
# Cron (instalação — ver função install_cron abaixo):
#   0 2 * * * /opt/scripts/ledger_backup.sh
#
# Variáveis de ambiente obrigatórias:
#   PGPASSWORD  — senha do usuário de backup (não coloque no script!)
#
# Exit codes:
#   0  — sucesso completo
#   1  — erro de configuração / pré-requisito ausente
#   2  — falha no pg_dump
#   3  — falha na compactação
#   4  — falha no upload para S3
#   5  — falha na rotação de backups antigos no S3
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Variáveis configuráveis
# -----------------------------------------------------------------------------
DB_HOST="ledger-db.internal.hvt.io"
DB_PORT="5432"
DB_NAME="ledger_prod"
DB_USER="backup_user"

AWS_REGION="us-east-1"
S3_BUCKET="hvt-ledger-backups"
S3_PREFIX="daily"                        # prefixo/pasta dentro do bucket

WORK_DIR="/var/backups/ledger"           # diretório local de trabalho (80 GB livres)
LOG_FILE="/var/log/ledger-backup.log"
RETENTION_DAYS=30                        # quantidade de dias de backup a manter no S3

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
DUMP_FILE="${WORK_DIR}/${DB_NAME}_${TIMESTAMP}.dump"
GZ_FILE="${DUMP_FILE}.gz"
S3_KEY="${S3_PREFIX}/${DB_NAME}_${TIMESTAMP}.dump.gz"

# Espaço mínimo exigido em KB antes de iniciar (20 GB de margem sobre ~12 GB)
MIN_FREE_KB=$((20 * 1024 * 1024))

# -----------------------------------------------------------------------------
# Funções auxiliares
# -----------------------------------------------------------------------------

log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*" | tee -a "${LOG_FILE}"
}

die() {
    local exit_code="$1"
    shift
    log "ERROR" "$*"
    # Limpeza do arquivo temporário, se existir
    [[ -f "${DUMP_FILE}" ]] && rm -f "${DUMP_FILE}"
    [[ -f "${GZ_FILE}" ]]   && rm -f "${GZ_FILE}"
    exit "${exit_code}"
}

check_prerequisites() {
    log "INFO" "Verificando pré-requisitos..."

    for cmd in pg_dump gzip aws; do
        if ! command -v "${cmd}" &>/dev/null; then
            die 1 "Comando '${cmd}' não encontrado. Instale e tente novamente."
        fi
    done

    if [[ -z "${PGPASSWORD:-}" ]]; then
        die 1 "Variável de ambiente PGPASSWORD não está definida."
    fi

    if [[ ! -d "${WORK_DIR}" ]]; then
        log "INFO" "Criando diretório de trabalho: ${WORK_DIR}"
        mkdir -p "${WORK_DIR}" || die 1 "Falha ao criar ${WORK_DIR}."
    fi

    # Verifica espaço livre no diretório de trabalho
    local free_kb
    free_kb=$(df -k "${WORK_DIR}" | awk 'NR==2 {print $4}')
    if (( free_kb < MIN_FREE_KB )); then
        die 1 "Espaço livre insuficiente em ${WORK_DIR}: ${free_kb} KB disponíveis, mínimo ${MIN_FREE_KB} KB."
    fi

    log "INFO" "Pré-requisitos OK. Espaço livre: ${free_kb} KB."
}

run_pg_dump() {
    log "INFO" "Iniciando pg_dump de ${DB_NAME} em ${DB_HOST}:${DB_PORT}..."

    # --no-password: usa PGPASSWORD do ambiente; -Fc: formato custom para restore flexível
    # Redirecionamos stderr para o log sem expor a senha
    if ! PGPASSWORD="${PGPASSWORD}" pg_dump \
        --host="${DB_HOST}" \
        --port="${DB_PORT}" \
        --username="${DB_USER}" \
        --no-password \
        --format=plain \
        --verbose \
        "${DB_NAME}" > "${DUMP_FILE}" 2>>"${LOG_FILE}"; then
        rm -f "${DUMP_FILE}"
        die 2 "pg_dump falhou. Verifique o log para detalhes."
    fi

    local dump_size
    dump_size=$(du -sh "${DUMP_FILE}" | cut -f1)
    log "INFO" "pg_dump concluído. Tamanho do dump: ${dump_size}."
}

compress_dump() {
    log "INFO" "Compactando dump com gzip..."

    if ! gzip --fast "${DUMP_FILE}"; then
        die 3 "Falha na compactação do arquivo ${DUMP_FILE}."
    fi

    # gzip renomeia automaticamente para DUMP_FILE.gz
    local gz_size
    gz_size=$(du -sh "${GZ_FILE}" | cut -f1)
    log "INFO" "Compactação concluída. Tamanho do arquivo: ${gz_size} → ${GZ_FILE}."
}

upload_to_s3() {
    log "INFO" "Enviando ${GZ_FILE} para s3://${S3_BUCKET}/${S3_KEY}..."

    if ! aws s3 cp "${GZ_FILE}" "s3://${S3_BUCKET}/${S3_KEY}" \
        --region "${AWS_REGION}" \
        --storage-class STANDARD_IA \
        --no-progress 2>>"${LOG_FILE}"; then
        die 4 "Falha no upload para s3://${S3_BUCKET}/${S3_KEY}."
    fi

    log "INFO" "Upload concluído: s3://${S3_BUCKET}/${S3_KEY}."
}

rotate_old_backups() {
    log "INFO" "Iniciando rotação de backups com mais de ${RETENTION_DAYS} dias no S3..."

    local cutoff_date
    cutoff_date=$(date -d "-${RETENTION_DAYS} days" '+%Y-%m-%dT%H:%M:%S')

    # Lista objetos no bucket/prefix e filtra os mais antigos que o cutoff
    local old_keys
    old_keys=$(aws s3api list-objects-v2 \
        --bucket "${S3_BUCKET}" \
        --prefix "${S3_PREFIX}/" \
        --region "${AWS_REGION}" \
        --query "Contents[?LastModified<='${cutoff_date}'].Key" \
        --output text 2>>"${LOG_FILE}" || true)

    if [[ -z "${old_keys}" || "${old_keys}" == "None" ]]; then
        log "INFO" "Nenhum backup antigo encontrado para remoção."
        return 0
    fi

    local deleted=0
    while IFS= read -r key; do
        [[ -z "${key}" ]] && continue
        log "INFO" "Removendo backup antigo: s3://${S3_BUCKET}/${key}"
        if aws s3 rm "s3://${S3_BUCKET}/${key}" \
            --region "${AWS_REGION}" 2>>"${LOG_FILE}"; then
            (( deleted++ )) || true
        else
            log "WARN" "Falha ao remover s3://${S3_BUCKET}/${key}. Continuando..."
        fi
    done <<< "${old_keys}"

    if (( deleted > 0 )); then
        log "INFO" "Rotação concluída. ${deleted} backup(s) antigo(s) removido(s)."
    fi
}

cleanup_local() {
    log "INFO" "Removendo arquivo local temporário..."
    rm -f "${GZ_FILE}"
    log "INFO" "Limpeza local concluída."
}

install_cron() {
    # Função utilitária — execute manualmente UMA VEZ para registrar a cron.
    # Uso: bash ledger_backup.sh --install-cron
    local script_path
    script_path="$(realpath "$0")"
    local cron_line="0 2 * * * ${script_path} >> ${LOG_FILE} 2>&1"

    if crontab -l 2>/dev/null | grep -qF "${script_path}"; then
        echo "Cron já configurada para ${script_path}. Nenhuma alteração feita."
        return 0
    fi

    ( crontab -l 2>/dev/null; echo "${cron_line}" ) | crontab -
    echo "Cron instalada com sucesso: ${cron_line}"
}

# -----------------------------------------------------------------------------
# Ponto de entrada
# -----------------------------------------------------------------------------

if [[ "${1:-}" == "--install-cron" ]]; then
    install_cron
    exit 0
fi

log "INFO" "============================================================"
log "INFO" "Backup iniciado — banco: ${DB_NAME} | host: ${DB_HOST}"
log "INFO" "============================================================"

check_prerequisites
run_pg_dump
compress_dump
upload_to_s3
rotate_old_backups
cleanup_local

log "INFO" "Backup concluído com sucesso: s3://${S3_BUCKET}/${S3_KEY}"
log "INFO" "============================================================"

exit 0
