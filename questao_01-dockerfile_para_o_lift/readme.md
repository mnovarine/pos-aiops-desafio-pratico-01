## Prompt

```
# Role
Você é um engenheiro sênior responsável por migrar aplicações que rodam em VM para um ambiente kubernetes.

# Task
Crie um dockerfile com a aplicação python no path /lift. O docker file deve conter as variáveis de ambiente DATABASE_URL e API_KEY, e o comando a ser executado para iniciar a aplicação deve ser "gunicorn --bind 0.0.0.0:8080 --workers 4 app:app". Utilizar as melhores práticas para criação de dockerfile, para reduzir ao máximo o tamanho da imagem.

# Format
Arquivo dockerfile comentado com cabeçalho explicando uso de como criar uma imagem e variáveis configuráveis no topo do arquivo.
```

## Modelo

Claude Sonnet 4.6

## Output

Multi-stage build (2 estágios):

- `builder` — usa `python:3.12-alpine` com `gcc`, `musl-dev` e `libpq-dev` apenas para compilar as dependências (incluindo `psycopg2-binary` que precisa de headers C). Os pacotes são instalados em `/install`.
- `runtime` — copia somente os pacotes compilados do estágio anterior; ferramentas de build não chegam à imagem final.

Outras boas práticas aplicadas:

- Base `alpine` (imagem mínima ~50 MB vs ~900 MB do `python:3.12`)
- `--no-cache-dir` no `pip install` elimina cache desnecessário
- Usuário não-root (`appuser`) para segurança
- `ENV DATABASE_URL=""` e `ENV API_KEY=""` declaradas explicitamente, sobrescritas via -e em tempo de execução
- `EXPOSE 8080` documenta a porta do serviço

Dockerfile

```dockerfile
# =============================================================================
# Dockerfile — Aplicação LIFT (Python/Flask + Gunicorn)
# =============================================================================
#
# COMO CONSTRUIR A IMAGEM:
#   docker build -t lift:latest .
#
# COMO EXECUTAR O CONTAINER:
#   docker run -d \
#     -e DATABASE_URL="postgresql://user:password@host:5432/dbname" \
#     -e API_KEY="sua-api-key-aqui" \
#     -p 8080:8080 \
#     lift:latest
#
# VARIÁVEIS DE AMBIENTE CONFIGURÁVEIS:
#   DATABASE_URL  — String de conexão com o banco de dados (ex.: postgresql://user:pass@host:5432/db)
#   API_KEY       — Chave de API utilizada pela aplicação
#
# =============================================================================

# -------------------------------------
# Estágio 1: builder
# Instala dependências de compilação e gera os pacotes Python em /install.
# Separar este estágio evita incluir compiladores e headers na imagem final.
# -------------------------------------
FROM python:3.12-alpine AS builder

# Dependências de sistema necessárias apenas para compilar extensões C (psycopg2, etc.)
RUN apk add --no-cache \
    gcc \
    musl-dev \
    libpq-dev

WORKDIR /build

COPY requirements.txt .

# --no-cache-dir  → não salva cache do pip (reduz tamanho)
# --prefix        → instala pacotes em diretório isolado para copiar no próximo estágio
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# -------------------------------------
# Estágio 2: runtime
# Imagem final mínima, sem ferramentas de build.
# -------------------------------------
FROM python:3.12-alpine AS runtime

# Dependências de runtime do PostgreSQL (libpq)
RUN apk add --no-cache libpq

# Cria usuário não-root para executar a aplicação (princípio do menor privilégio)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copia pacotes Python instalados no estágio builder
COPY --from=builder /install /usr/local

# Copia o código-fonte da aplicação
COPY --chown=appuser:appgroup . .

# Variáveis de ambiente obrigatórias — sobrescreva ao executar o container
ENV DATABASE_URL=""
ENV API_KEY=""

# Porta exposta pelo Gunicorn
EXPOSE 8080

# Troca para usuário não-root antes de iniciar o processo
USER appuser

# Inicia a aplicação com Gunicorn
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "4", "app:app"]
```