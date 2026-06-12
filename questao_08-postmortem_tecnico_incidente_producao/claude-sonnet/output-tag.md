# POST-MORTEM TÉCNICO — INCIDENTE DE PRODUÇÃO

---

## Título do Incidente

**[SEV-1] Esgotamento de Pool de Conexões e Circuit Breaker Aberto no `chronos-api` após Deploy v2.48.0 — Decisão Rollback vs Scaling Emergencial**

---

## Data, Duração e Severidade

| Campo                    | Valor                                                                          |
|--------------------------|--------------------------------------------------------------------------------|
| **Data**                 | 2026-04-24                                                                     |
| **Início da degradação** | ~13:30 UTC (p99 420ms, err_rate 0.2%)                                          |
| **Pico crítico**         | 14:20 UTC (p99 8.100ms, err_rate 11.7%, circuit breaker OPEN)                  |
| **Duração observada**    | ~50 minutos de degradação progressiva (incidente em curso)                     |
| **Severidade**           | **SEV-1** — impacto direto ao usuário, circuit breaker aberto, fila acumulando |
| **Deploy precursor**     | `chronos-api` v2.48.0 — ArgoCD sync em 2026-04-23 18:42:11 UTC                |
| **Serviços afetados**    | chronos-api, Reactor (fila `chronos-transactions`), Ledger (RDS)               |

---

## Resumo Executivo

Aproximadamente 19h30 após o deploy da versão v2.48.0 do `chronos-api`, o aumento natural de tráfego do horário comercial (de 1.200 para 2.650 req/s) tornou crítico um conjunto de problemas latentes introduzidos pelo deploy. O serviço atingiu 11,7% de taxa de erro, latência p99 de 8,1s e o circuit breaker do `ledger-client` abriu automaticamente com 87% de falhas (limiar: 50%).

O sistema está no limite operacional em múltiplas dimensões simultaneamente: pool de conexões do aplicativo esgotado (20/20 por pod, 147 aguardando), conexões RDS em 240/250 (96%), HPA no máximo (12/12 pods) e fila Reactor acumulando 50.127 mensagens a ~800/min.

A análise de causa raiz aponta três mudanças no changelog v2.48.0 como fatores combinados: refatoração do pool de conexões com parâmetros insuficientes para produção, redução do timeout de 5s para 2s gerando cascata de timeouts e retentativas, e novo endpoint de batch consumindo múltiplas conexões por requisição.

**Recomendação:** Rollback imediato para v2.47.0. O scaling emergencial alivia sintomas sem resolver a causa raiz, é mais lento e expõe o sistema a riscos adicionais durante a execução.

---

## Timeline

```
2026-04-23 18:42:11 UTC  [DEPLOY]   ArgoCD sync: chronos-api v2.47.0 → v2.48.0
                                     Ativo: novo pool de conexões (biblioteca interna),
                                     timeout Ledger reduzido 5s→2s, endpoint /batch,
                                     psycopg 3.1.18→3.2.0. Sem alertas imediatos.
                                     Tráfego baixo (período noturno).

2026-04-24 13:30 UTC     [WARN]     p99=420ms, req=1.200/s, err=0.2%
                                     Degradação ainda dentro de SLO, mas acima do
                                     baseline histórico. Tráfego comercial iniciando.

2026-04-24 13:45 UTC     [WARN]     p99=510ms (+21%), req=1.450/s, err=0.3%
                                     Crescimento de tráfego começando a pressionar
                                     o pool de conexões.

2026-04-24 14:00 UTC     [ALERTA]   p99=780ms, req=1.780/s, err=0.8%
                                     SLO de latência possivelmente violado.
                                     Filas de espera no pool começando a crescer.

2026-04-24 14:10 UTC     [CRÍTICO]  p99=2.400ms, req=2.100/s, err=4.5%
                                     Pool saturado. Primeiros timeouts de 2.000ms
                                     em massa. HPA atingindo capacidade máxima.

2026-04-24 14:15 UTC     [CRÍTICO]  p99=5.200ms, req=2.400/s, err=8.2%
                                     Conexões RDS em ~230/250. Reactor lag crescendo.

2026-04-24 14:19:48 UTC  [FALHA]    Log: "connection pool exhausted (max=20,
                                     active=20, waiting=147)"

2026-04-24 14:19:49 UTC  [FALHA]    Log: "query timeout after 2000ms"
                                     Log: "POST /v2/transactions/batch failed:
                                     context deadline exceeded"

2026-04-24 14:19:51 UTC  [FALHA]    Circuit breaker ledger-client OPEN (87%)
                                     Reactor para de consumir: fila acumula.

2026-04-24 14:20 UTC     [FALHA]    p99=8.100ms, req=2.650/s, err=11.7%
                                     Conexões RDS: 240/250. Consumer lag: 18min.
                                     Fila Reactor: 50.127 mensagens (+800/min).
                                     *** MOMENTO ATUAL — INCIDENTE EM CURSO ***
```

---

## Análise de Causa Raiz — 5 Causas em Ordem de Probabilidade

---

### Causa #1 — Refatoração do Pool de Conexões com Capacidade Insuficiente para Produção

**Probabilidade: MUITO ALTA**

**Evidências:**
- Log confirma `connection pool exhausted (max=20, active=20, waiting=147)` — 147 requisições aguardando em apenas 1 pod
- O changelog indica que o pool foi "movido para nova biblioteca interna", indicando mudança de implementação, não apenas de parâmetros
- 12 pods × 20 conexões = 240 conexões abertas ao RDS, tocando exatamente o limite de 250
- A nova biblioteca pode ter comportamento diferente de reaproveitamento de conexões (keep-alive, timeouts de idle, validação de conexão), mais agressivo que a anterior
- O crash só aconteceu com tráfego de pico (~19h após o deploy), confirmando que o problema é de capacidade sob carga

**Comandos/Métricas AWS para Validar:**

```bash
# 1. Verificar conexões ativas no RDS (CloudWatch)
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=ledger-rds \
  --start-time 2026-04-24T13:00:00Z \
  --end-time 2026-04-24T14:25:00Z \
  --period 60 \
  --statistics Maximum \
  --output table

# 2. Verificar logs do pod para configuração do pool
kubectl logs chronos-api-79c4d8b9-xk2jp --since=2h | \
  grep -E "pool|connection|max_connections|pool_size|min_conn|max_conn"

# 3. Ver variáveis de ambiente do pod (configuração do pool)
kubectl exec chronos-api-79c4d8b9-xk2jp -- env | \
  grep -E "POOL|CONN|LEDGER|DB_"

# 4. Comparar configuração entre versões via ArgoCD
argocd app diff chronos-api --revision v2.47.0

# 5. RDS Performance Insights — conexões por aplicação
aws pi get-resource-metrics \
  --service-type RDS \
  --identifier db-XXXXXXXXXX \
  --metric-queries '[{"Metric":"db.Connections.dbConnections"}]' \
  --start-time 2026-04-24T13:30:00Z \
  --end-time 2026-04-24T14:25:00Z \
  --period-in-seconds 60
```

**Ação Corretiva Imediata:**
Rollback para v2.47.0 (restaura o pool original). Se optar por scaling, aumentar `POOL_MAX_SIZE` de 20 para 50 no ConfigMap do deployment e restartar os pods de forma rolling, mas isso requer que o RDS suporte 12×50=600 conexões (limite atual 250 → requer modificação de instância antes).

---

### Causa #2 — Redução do Timeout do Ledger de 5s para 2s Causando Cascata de Timeouts e Retentativas

**Probabilidade: ALTA**

**Evidências:**
- Log confirma `query timeout after 2000ms` com a query `SELECT ... FROM transactions WHERE ...`
- A query provavelmente levava entre 2s e 5s sob carga de pico (dentro do SLO anterior)
- Cada timeout gera um retry que ocupa uma nova conexão do pool, multiplicando a pressão
- O novo endpoint `/batch` processa múltiplas transações por requisição, com queries potencialmente mais lentas
- Redução de timeout agressiva sem análise do P95/P99 histórico das queries do Ledger

**Comandos/Métricas AWS para Validar:**

```bash
# 1. Verificar latência de queries no RDS (CloudWatch)
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ReadLatency \
  --dimensions Name=DBInstanceIdentifier,Value=ledger-rds \
  --start-time 2026-04-24T13:00:00Z \
  --end-time 2026-04-24T14:25:00Z \
  --period 60 \
  --statistics p99 \
  --output table

# 2. Verificar slow query log do RDS
aws rds describe-db-log-files \
  --db-instance-identifier ledger-rds \
  --filename-contains "slowquery"

aws rds download-db-log-file-portion \
  --db-instance-identifier ledger-rds \
  --log-file-name slowquery/mysql-slowquery.log \
  --output text | tail -100

# 3. CloudWatch Logs Insights — queries acima de 2s
aws logs start-query \
  --log-group-name /aws/rds/instance/ledger-rds/postgresql \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message
    | filter @message like /duration/
    | filter @message like /[2-9][0-9]{3,} ms/
    | stats count() by bin(1m)'

# 4. RDS Performance Insights — top queries por latência
aws pi get-resource-metrics \
  --service-type RDS \
  --identifier db-XXXXXXXXXX \
  --metric-queries '[{"Metric":"db.SQL.mean_latency","GroupBy":{"Group":"db.sql","Limit":10}}]' \
  --start-time 2026-04-24T14:00:00Z \
  --end-time 2026-04-24T14:25:00Z \
  --period-in-seconds 60
```

**Ação Corretiva Imediata:**
Rollback para v2.47.0 (restaura timeout de 5s). Se optar por hotfix, alterar variável de ambiente `LEDGER_TIMEOUT_MS` de `2000` para `5000` no ConfigMap e fazer rolling restart. Requer validar se a variável existe e é respeitada pela nova biblioteca.

---

### Causa #3 — Novo Endpoint `POST /v2/transactions/batch` Multiplicando Conexões por Requisição

**Probabilidade: ALTA**

**Evidências:**
- Log mostra `POST /v2/transactions/batch failed: context deadline exceeded` como primeiro erro do handler
- Operações em lote tipicamente abrem uma transação de banco por item do batch ou por operação agregada, multiplicando o uso do pool
- O endpoint foi adicionado nesse mesmo deploy, sem histórico de carga em produção
- O tráfego cresceu de 1.200 para 2.650 req/s — parte desse crescimento pode ser chamadas ao endpoint batch
- O esgotamento do pool (147 aguardando) é desproporcional ao tamanho do pool (20), sugerindo retenção longa de conexões por operações complexas

**Comandos/Métricas AWS para Validar:**

```bash
# 1. CloudWatch Logs Insights — volume de chamadas por endpoint
aws logs start-query \
  --log-group-name /ecs/chronos-api \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message
    | filter @message like /POST \/v2\/transactions\/batch/
    | stats count() by bin(1m)
    | sort @timestamp desc'

# 2. Verificar duração média do endpoint batch vs outros endpoints
aws logs start-query \
  --log-group-name /ecs/chronos-api \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, endpoint, duration_ms
    | filter ispresent(endpoint) and ispresent(duration_ms)
    | stats avg(duration_ms), p99(duration_ms) by endpoint
    | sort p99_duration_ms desc'

# 3. Verificar se o endpoint batch possui rate limiting ou tem EXPLAIN plan custoso
kubectl exec chronos-api-79c4d8b9-xk2jp -- \
  curl -s http://localhost:8080/metrics | grep -E "batch|transactions"

# 4. X-Ray / Distributed Tracing — latência do endpoint
aws xray get-service-graph \
  --start-time 2026-04-24T14:00:00 \
  --end-time 2026-04-24T14:25:00
```

**Ação Corretiva Imediata:**
Rollback para v2.47.0 (remove o endpoint). Alternativa de menor risco sem rollback: colocar um rate limit emergencial no API Gateway ou ALB para o endpoint `/v2/transactions/batch` (ex: 10 req/s), reduzindo a pressão enquanto se prepara o rollback ou hotfix.

```bash
# Rate limit emergencial no ALB (se aplicável)
aws elbv2 create-rule \
  --listener-arn arn:aws:elasticloadbalancing:... \
  --conditions '[{"Field":"path-pattern","Values":["/v2/transactions/batch"]}]' \
  --actions '[{"Type":"fixed-response","FixedResponseConfig":{"StatusCode":"429"}}]' \
  --priority 1
```

---

### Causa #4 — Comportamento de psycopg 3.2.0 Diferente do 3.1.18 na Gestão de Conexões

**Probabilidade: MÉDIA**

**Evidências:**
- O bump `psycopg 3.1.18 → 3.2.0` é uma versão minor com potencial de breaking changes em comportamento de pool e tratamento de erros
- O log mostra `connection reset by peer` (erro 14:19:50), que pode indicar que o driver está fechando conexões prematuramente ou de forma incorreta
- A combinação de nova biblioteca de pool + nova versão do driver é um vetor de compatibilidade não testado em produção
- Erros de `connection reset by peer` sob carga são assinatura de problemas de keep-alive ou handshake

**Comandos/Métricas AWS para Validar:**

```bash
# 1. Verificar erros específicos do psycopg nos logs
kubectl logs -l app=chronos-api --since=1h | \
  grep -E "psycopg|OperationalError|InterfaceError|connection reset|SSL|FATAL"

# 2. CloudWatch Logs Insights — frequência de "connection reset by peer"
aws logs start-query \
  --log-group-name /ecs/chronos-api \
  --start-time $(date -d '2 hours ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message
    | filter @message like /connection reset/
    | stats count() by bin(5m)'

# 3. Comparar versão do psycopg no ambiente de staging
kubectl exec -n staging chronos-api-staging-xxxxx -- \
  pip show psycopg | grep Version

# 4. RDS CloudWatch — AbortedClients (conexões fechadas pelo cliente abruptamente)
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name NetworkTransmitThroughput \
  --dimensions Name=DBInstanceIdentifier,Value=ledger-rds \
  --start-time 2026-04-24T13:30:00Z \
  --end-time 2026-04-24T14:25:00Z \
  --period 60 \
  --statistics Sum
```

**Ação Corretiva Imediata:**
Rollback para v2.47.0 (retorna psycopg 3.1.18). Não é possível isolar apenas o bump do psycopg em produção sem rollback completo.

---

### Causa #5 — Queries Lentas no Ledger por Ausência de Índice para o Endpoint Batch

**Probabilidade: MÉDIA-BAIXA**

**Evidências:**
- Log mostra `SELECT ... FROM transactions WHERE ...` atingindo timeout de 2.000ms
- Novo endpoint de batch provavelmente executa queries de seleção em `transactions` com filtros não utilizados anteriormente
- Sob alta concorrência, table scans ou índices ineficientes causam lock contention que aumenta drasticamente a latência
- O RDS está em 240/250 conexões: alta contagem de conexões ativas aumenta a pressão de locking
- CPU do RDS não foi mencionada como crítica nos dados fornecidos, mas I/O pode estar saturado

**Comandos/Métricas AWS para Validar:**

```bash
# 1. RDS Performance Insights — wait events (I/O, locks)
aws pi get-resource-metrics \
  --service-type RDS \
  --identifier db-XXXXXXXXXX \
  --metric-queries '[{"Metric":"db.load.avg","GroupBy":{"Group":"db.wait_event","Limit":5}}]' \
  --start-time 2026-04-24T14:00:00Z \
  --end-time 2026-04-24T14:25:00Z \
  --period-in-seconds 60

# 2. CloudWatch — IOPS e CPU do RDS
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ReadIOPS \
  --dimensions Name=DBInstanceIdentifier,Value=ledger-rds \
  --start-time 2026-04-24T13:30:00Z \
  --end-time 2026-04-24T14:25:00Z \
  --period 60 \
  --statistics Maximum

# 3. Verificar se há índices na tabela transactions para os novos filtros
# Conectar ao RDS (via bastion ou RDS Proxy):
psql -h ledger-rds.xxxx.rds.amazonaws.com -U admin -d ledger \
  -c "SELECT indexname, indexdef FROM pg_indexes WHERE tablename='transactions';"

# 4. EXPLAIN ANALYZE da query do endpoint batch
psql -h ledger-rds.xxxx.rds.amazonaws.com -U admin -d ledger \
  -c "EXPLAIN (ANALYZE, BUFFERS) SELECT ... FROM transactions WHERE ...;"

# 5. Verificar autovacuum pendente (tabela inchada)
psql -h ledger-rds.xxxx.rds.amazonaws.com -U admin -d ledger \
  -c "SELECT relname, n_dead_tup, last_autovacuum FROM pg_stat_user_tables
      WHERE relname='transactions';"
```

**Ação Corretiva Imediata:**
Rollback para v2.47.0 elimina a query problemática. Se optar por manter a versão, criar índice em produção de forma concorrente (sem lock):
```sql
CREATE INDEX CONCURRENTLY idx_transactions_batch
ON transactions (coluna_filtro_batch)
WHERE condicao_relevante;
```

---

## Árvore de Decisão: Rollback vs Scaling Emergencial

```
INCIDENTE ATIVO — SEV-1
│
├─ Causa raiz é conhecida? ──YES──► Mudança de código/config introduzida
│                                   pelo deploy v2.48.0 (timeout, pool, batch)
│                                         │
│                                         ▼
│                              O scaling emergencial resolve
│                              a causa raiz?
│                                │
│                                ├─ NÃO: O timeout de 2s permanece.
│                                │       O endpoint batch permanece.
│                                │       O novo pool permanece.
│                                │       Scaling apenas adia a saturação.
│                                │
│                                └─► DECISÃO: ROLLBACK ✓ (recomendado)
│
├─ Rollback é viável? ──────YES──► v2.47.0 está disponível no registry
│                                  ArgoCD permite rollback de 1 clique
│                                  Tempo estimado: 8–15 min
│                                  Risco: baixo (versão estável anterior)
│
└─ Scaling emergencial ────────►  Aumentar RDS max_connections: 30–60 min
   (alternativa de contingência)  Requer modify-db-instance + reboot RDS
   se rollback bloqueado           OU PgBouncer deployment emergencial
                                  Aumentar pool por pod: rolling restart
                                  Tempo estimado: 45–90 min
                                  Risco: ALTO (reboot RDS gera downtime adicional)
                                  Resultado: alivia sintoma, não resolve causa
```

### Estimativa de Tempo por Decisão

| Ação                                          | Tempo Estimado | Risco      | Resultado           |
|-----------------------------------------------|----------------|------------|---------------------|
| **Rollback v2.47.0 via ArgoCD**               | 8–15 min       | Baixo      | Resolve causa raiz  |
| Rollback manual via kubectl                   | 15–25 min      | Baixo      | Resolve causa raiz  |
| Rate limit emergencial no ALB (paliativo)     | 5–10 min       | Muito Baixo| Alivia parcialmente |
| Aumentar pool via ConfigMap (hotfix parcial)  | 15–20 min      | Baixo-Médio| Alivia sintoma      |
| Aumentar RDS max_connections (modify)         | 30–60 min      | Alto       | Alivia sintoma      |
| Aumentar RDS max_connections (parameter group)| 20–30 min + reboot | Alto   | Alivia sintoma      |
| Deploy PgBouncer como connection pooler       | 60–90 min      | Alto       | Alivia sintoma      |
| Hotfix completo (corrigir pool + timeout)     | 2–4 horas      | Médio      | Resolve causa raiz  |

---

## Roteiro Detalhado de Execução

### OPÇÃO A — Rollback via ArgoCD (RECOMENDADO)

**Pré-requisitos:** Acesso ao ArgoCD com permissão de sync/rollback na aplicação `chronos-api`.

**Tempo total estimado: 8–15 minutos**

```bash
# PASSO 1 — Confirmar versão atual e versão alvo (1 min)
argocd app get chronos-api | grep -E "Image|Revision|Status"
# Confirmar que a versão atual é v2.48.0 e que v2.47.0 está disponível

# PASSO 2 — Verificar histórico de syncs disponíveis (1 min)
argocd app history chronos-api
# Identificar o ID do sync correspondente ao v2.47.0

# PASSO 3 — Executar rollback (2–3 min para o ArgoCD iniciar)
argocd app rollback chronos-api <HISTORY_ID>
# Ou via Git: reverter o commit no repositório de manifests e fazer sync manual

# PASSO 4 — Monitorar o rollout (5–10 min)
kubectl rollout status deployment/chronos-api -n production --timeout=600s
watch -n5 'kubectl get pods -n production -l app=chronos-api'

# PASSO 5 — Verificar que os pods estão em Running com a imagem correta
kubectl get pods -n production -l app=chronos-api -o jsonpath=\
  '{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'

# PASSO 6 — Validar recuperação das métricas (após pods estabilizarem)
# Aguardar 2–3 minutos e verificar:
kubectl top pods -n production -l app=chronos-api

# Verificar pool de conexões nos logs
kubectl logs -l app=chronos-api -n production --since=2m | \
  grep -E "pool|connection|ERROR|WARN" | tail -30

# PASSO 7 — Verificar drenagem da fila Reactor
# A fila deve começar a drenar após o circuit breaker fechar
kubectl exec -n production reactor-xxxxx -- \
  kafka-consumer-groups.sh --bootstrap-server kafka:9092 \
  --group chronos-transactions --describe
```

**Critérios de sucesso do rollback:**
- Todos os pods em `Running` com imagem v2.47.0
- `err_rate < 1%` nas métricas do Beacon após 5 minutos
- `p99_latency < 600ms` após 5 minutos
- Nenhum `connection pool exhausted` nos logs
- Consumer lag do Reactor começando a diminuir
- Conexões RDS caindo abaixo de 150

---

### OPÇÃO B — Scaling Emergencial (CONTINGÊNCIA — apenas se rollback bloqueado)

**Use apenas se:** rollback estiver bloqueado por dependência de dados do novo endpoint, incompatibilidade de schema, ou decisão de negócio.

**Tempo total estimado: 45–90 minutos**

#### Fase B.1 — Alívio imediato via rate limit no batch endpoint (5–10 min)

```bash
# Rate limit emergencial no API Gateway para /v2/transactions/batch
aws apigateway create-usage-plan \
  --name "emergency-batch-throttle" \
  --throttle burstLimit=5,rateLimit=10

# Ou via ALB — redirecionar batch para resposta 429 temporária
# (Reduz a pressão no pool enquanto o scaling é executado)
```

#### Fase B.2 — Aumentar pool de conexões por pod (15–20 min)

```bash
# PASSO 1 — Editar ConfigMap com novo tamanho de pool
kubectl edit configmap chronos-api-config -n production
# Alterar: LEDGER_POOL_MAX_SIZE: "20"  →  LEDGER_POOL_MAX_SIZE: "15"
# (ATENÇÃO: Reduzir para 15 para não ultrapassar 12×15=180 < 250 no RDS)
# E aumentar timeout: LEDGER_TIMEOUT_MS: "2000"  →  LEDGER_TIMEOUT_MS: "5000"

# PASSO 2 — Rolling restart para aplicar o ConfigMap
kubectl rollout restart deployment/chronos-api -n production

# PASSO 3 — Monitorar rolling restart
kubectl rollout status deployment/chronos-api -n production --timeout=300s
```

#### Fase B.3 — Aumentar max_connections do RDS via Parameter Group (20–30 min + reboot)

```bash
# PASSO 1 — Verificar parameter group atual
aws rds describe-db-instances \
  --db-instance-identifier ledger-rds \
  --query 'DBInstances[0].DBParameterGroups'

# PASSO 2 — Criar novo parameter group com limite maior
aws rds create-db-parameter-group \
  --db-parameter-group-name ledger-rds-emergency \
  --db-parameter-group-family postgres15 \
  --description "Emergency: increased max_connections"

aws rds modify-db-parameter-group \
  --db-parameter-group-name ledger-rds-emergency \
  --parameters "ParameterName=max_connections,ParameterValue=500,ApplyMethod=pending-reboot"

# PASSO 3 — Aplicar o parameter group (requer reboot do RDS — ~5 min de downtime)
aws rds modify-db-instance \
  --db-instance-identifier ledger-rds \
  --db-parameter-group-name ledger-rds-emergency \
  --apply-immediately

# ⚠️ ATENÇÃO: --apply-immediately causa reboot do RDS.
# Coordenar com o time: isto vai gerar downtime adicional de ~3–5 min.

# PASSO 4 — Monitorar reboot do RDS
aws rds wait db-instance-available \
  --db-instance-identifier ledger-rds

aws rds describe-db-instances \
  --db-instance-identifier ledger-rds \
  --query 'DBInstances[0].DBInstanceStatus'

# PASSO 5 — Verificar novo limite aplicado
psql -h ledger-rds.xxxx.rds.amazonaws.com -U admin \
  -c "SHOW max_connections;"
```

#### Fase B.4 — Verificar drenagem da fila após o scaling

```bash
# Acompanhar consumer lag do Reactor a cada 2 minutos
watch -n 120 'kafka-consumer-groups.sh \
  --bootstrap-server kafka:9092 \
  --group chronos-transactions \
  --describe | grep -E "TOPIC|LAG"'

# Critério de sucesso: LAG deve estar decrescendo.
# Tempo estimado para dreno de 50.127 mensagens a 800/s: ~63 segundos
# de processamento pleno. Se o consumer lag não reduzir em 10 min
# após o scaling, escalar também os pods do Reactor.
```

---

## Causa Raiz

A causa raiz é **uma combinação de três mudanças do deploy v2.48.0**, todas relacionadas ao gerenciamento de conexões com o Ledger:

1. **Refatoração do pool de conexões** para nova biblioteca interna com parâmetros (`max=20`) dimensionados para ambiente de testes, não para carga de produção com 12 pods no HPA máximo.

2. **Redução do timeout de 5s para 2s** sem análise do percentil P95/P99 histórico das queries do Ledger em horário de pico, causando timeouts em cascata e retentativas que multiplicam o uso do pool.

3. **Novo endpoint `POST /v2/transactions/batch`** que realiza operações com múltiplas conexões do pool por requisição, acelerando o esgotamento sob carga crescente.

O **fator de ativação** foi o crescimento natural de tráfego do horário comercial (1.200→2.650 req/s), que ocorre ~19 horas após o deploy, fora da janela de monitoramento intensivo pós-deploy.

---

## Ações Corretivas

| # | Ação                                                                 | Responsável             | Prazo          | Status    |
|---|----------------------------------------------------------------------|-------------------------|----------------|-----------|
| 1 | Executar rollback para v2.47.0 via ArgoCD                            | SRE on-call             | Imediato       | URGENTE   |
| 2 | Confirmar drenagem da fila Reactor após rollback                     | SRE on-call             | +15 min        | Pendente  |
| 3 | Validar métricas do Beacon (err_rate < 1%, p99 < 600ms)              | SRE on-call             | +20 min        | Pendente  |
| 4 | Comunicar stakeholders sobre rollback e status                       | Eng. Manager / Tech Lead| +30 min        | Pendente  |
| 5 | Escalar Reactor se fila não drenar em 30 min após rollback           | SRE on-call             | +45 min        | Condicional|
| 6 | Análise detalhada dos logs do Reactor para mensagens com erro        | Dev Team                | +2 horas       | Pendente  |
| 7 | Revisar parametrização do pool para produção na v2.48.0              | Dev Team (dono da lib)  | +1 dia útil    | Pendente  |
| 8 | Análise de impacto nas mensagens acumuladas (duplicatas, ordem)      | Dev Team / Produto      | +1 dia útil    | Pendente  |
| 9 | Load test da v2.48.0 corrigida em staging com carga de produção      | QA / SRE                | Antes do redeploy | Pendente |

---

## Ações Preventivas

| # | Ação                                                                                    | Responsável      | Prazo       |
|---|-----------------------------------------------------------------------------------------|------------------|-------------|
| 1 | **Definir SLO de pool de conexões**: alarme CloudWatch quando conexões RDS > 70% do limite | SRE / Platform  | 1 semana    |
| 2 | **Load test obrigatório** para PRs que alterem cliente de banco, pool ou timeout         | Dev Process      | 2 semanas   |
| 3 | **Canary deploy** para mudanças de bibliotecas de infraestrutura (mínimo 10% do tráfego por 2h) | Platform / ArgoCD | 2 semanas  |
| 4 | **Análise P95/P99 histórico** como pré-requisito para qualquer redução de timeout        | Dev Process (RFC) | 1 semana   |
| 5 | **Monitoramento de consumer lag** do Reactor com alerta se lag > 5 minutos              | SRE / Platform   | 1 semana    |
| 6 | **Revisar janela de observação pós-deploy**: estender de 1h para 4h em dias úteis        | SRE Process      | 1 semana    |
| 7 | **Documentar limites de capacidade do RDS** no runbook: max_connections, uso por pod    | SRE              | 3 dias úteis|
| 8 | **Circuit breaker tunning**: revisar threshold (atual 50%) e janela de fechamento        | Dev Team         | 2 semanas   |
| 9 | **Teste de regressão de performance** automatizado no pipeline CI para o cliente Ledger  | Dev / QA         | 1 mês       |
| 10| **RDS Proxy**: avaliar adoção para desacoplar conexões da aplicação do limite do RDS    | Platform / Arquitetura | 1 mês |

---

## Checklist de Validação Pós-Resolução

```
[ ] Todos os pods chronos-api rodando v2.47.0
[ ] err_rate < 0.5% por 10 minutos consecutivos
[ ] p99_latency < 500ms por 10 minutos consecutivos
[ ] Conexões RDS < 100 (pool de v2.47.0 restaurado)
[ ] Circuit breaker ledger-client em estado CLOSED
[ ] Consumer lag do Reactor decrescendo consistentemente
[ ] Nenhuma mensagem em dead-letter queue do Reactor
[ ] Comunicação de resolução enviada para stakeholders
[ ] Retrospectiva agendada (dentro de 48h)
```

---

*Documento gerado para o time de plantão em 2026-04-24. Autor: SRE on-call. Revisão necessária após resolução do incidente.*
