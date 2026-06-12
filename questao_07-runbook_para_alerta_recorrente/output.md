## Output

---

# RUNBOOK — [CRITICAL] High Memory Usage on Chronos API Pods (>85% for 10min)

**Alerta:** `[CRITICAL] High memory usage on Chronos API pods (>85% for 10min)`
**Ambiente:** EKS / namespace `production` / API Chronos
**Canal de plantão:** `#oncall-chronos`
**Escalação sênior:** `@chronos-core` (15 min comercial / 30 min fora)
**Tempo total máximo:** 15 minutos

---

## Índice

1. [Passo 1 — Confirmar estado dos pods e coletar métricas](#passo-1) `⏱ 0–2 min`
2. [Passo 2 — Analisar métricas no Prometheus (última 1h)](#passo-2) `⏱ 2–5 min`
3. [Passo 3 — Verificar volumetria e picos de uso da API](#passo-3) `⏱ 5–7 min`
4. [Passo 4 — Diagnóstico: memory leak vs subdimensionamento](#passo-4) `⏱ 7–9 min`
5. [Passo 5 — Ação imediata de mitigação](#passo-5) `⏱ 9–11 min`
6. [Passo 6 — Critérios de escalação](#passo-6) `⏱ 11–12 min`
7. [Passo 7 — Ajustes definitivos e validação pós-fix](#passo-7) `⏱ 12–15 min`
8. [Critérios de encerramento do incidente](#encerramento)

---

## Pré-requisitos

```bash
# Garantir contexto correto no kubectl
kubectl config current-context
kubectl config use-context <arn-do-cluster-eks>

# Namespace padrão para o plantão
export NS=production
export APP=chronos-api
```

---

<a name="passo-1"></a>
## Passo 1 — Confirmar estado dos pods e coletar métricas de memória
**Tempo máximo:** 2 minutos

```bash
# 1.1 — Listar pods e status
kubectl get pods -n $NS -l app=$APP -o wide

# 1.2 — Verificar uso de memória e CPU em tempo real
kubectl top pods -n $NS -l app=$APP --sort-by=memory

# 1.3 — Verificar se o HPA está em ação
kubectl get hpa -n $NS

# 1.4 — Inspecionar eventos recentes dos pods
kubectl get events -n $NS --sort-by='.lastTimestamp' | grep -i $APP | tail -20

# 1.5 — Detalhar pod com maior consumo (substituir <POD_NAME>)
kubectl describe pod <POD_NAME> -n $NS | grep -A5 "Limits\|Requests\|OOM\|Restart"
```

**Verificação esperada:**
- Pods em estado `Running`; se houver `OOMKilled` ou `CrashLoopBackOff`, pular direto para o Passo 5
- `kubectl top` exibe memória >85% do limit configurado em pelo menos 1 pod
- HPA mostrando réplicas entre 4–12; se já em 12, avaliar limite do cluster

**Escalar imediatamente se:** qualquer pod em `OOMKilled` + reinicializações > 3 nas últimas 2h

---

<a name="passo-2"></a>
## Passo 2 — Analisar métricas de memória no Prometheus (última 1h)
**Tempo máximo:** 3 minutos

> Abrir Grafana ou executar as queries abaixo via Prometheus UI / API.

```promql
# 2.1 — Uso atual de memória por pod (bytes)
container_memory_working_set_bytes{namespace="production", container="chronos-api"}

# 2.2 — Percentual do limit consumido por pod
(
  container_memory_working_set_bytes{namespace="production", container="chronos-api"}
  /
  container_spec_memory_limit_bytes{namespace="production", container="chronos-api"}
) * 100

# 2.3 — Tendência de crescimento da memória na última 1h (identifica leak)
increase(
  container_memory_working_set_bytes{namespace="production", container="chronos-api"}[1h]
)

# 2.4 — Taxa de crescimento por minuto (alerta se positivo e constante)
rate(
  container_memory_working_set_bytes{namespace="production", container="chronos-api"}[10m]
)

# 2.5 — Correlacionar com último deploy (tempo do rollout)
kube_deployment_status_observed_generation{namespace="production", deployment="chronos-api"}
```

**Verificação esperada:**
- Query 2.2: pods acima de 85% confirma o alerta
- Query 2.3/2.4: crescimento **constante e linear** → sinal de **memory leak**
- Query 2.3/2.4: crescimento **em degrau** correlacionado a horário de pico → sinal de **subdimensionamento**
- Verificar se pico coincide com horário do último deploy no Argo CD

---

<a name="passo-3"></a>
## Passo 3 — Verificar volumetria e picos de uso da API Chronos
**Tempo máximo:** 2 minutos

```promql
# 3.1 — Requisições por segundo na última 1h
sum(rate(http_requests_total{namespace="production", service="chronos-api"}[5m])) by (pod)

# 3.2 — Latência p99 (correlacionar memória alta com degradação de performance)
histogram_quantile(0.99,
  sum(rate(http_request_duration_seconds_bucket{namespace="production", service="chronos-api"}[5m]))
  by (le, pod)
)

# 3.3 — Erros HTTP 5xx
sum(rate(http_requests_total{namespace="production", service="chronos-api", status=~"5.."}[5m]))

# 3.4 — Verificar conexões abertas com Ledger (PostgreSQL)
pg_stat_activity_count{datname="ledger", state="active"}

# 3.5 — Verificar depth das filas SQS (Reactor)
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS \
  --metric-name ApproximateNumberOfMessagesVisible \
  --dimensions Name=QueueName,Value=reactor-queue \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Maximum
```

```bash
# 3.6 — Verificar logs no Beacon para erros de memória / GC / OOM
# (adaptar ao CLI do Beacon disponível no ambiente)
beacon logs search \
  --app chronos-api \
  --namespace production \
  --since 1h \
  --query "OutOfMemory OR GC overhead OR heap"
```

**Verificação esperada:**
- Pico de RPS coincide com horário do alerta → indica subdimensionamento
- RPS estável mas memória cresce → reforça hipótese de leak
- Filas SQS com backlog acumulado pode indicar processamento intensivo em memória

---

<a name="passo-4"></a>
## Passo 4 — Diagnóstico: Memory Leak vs Subdimensionamento
**Tempo máximo:** 2 minutos

### Árvore de Decisão

```
Memória >85% por 10 min?
│
├── Crescimento CONTÍNUO e LINEAR (mesmo com RPS estável)?
│   └── → MEMORY LEAK confirmado
│       ├── Correlaciona com deploy recente (< 48h)?
│       │   └── → ROLLBACK via Argo CD (ver Passo 5-A)
│       └── Não correlaciona com deploy?
│           └── → ESCALAR para @chronos-core + coletar heap dump (ver Passo 6)
│
└── Crescimento em DEGRAU / SPIKE associado a horário de pico ou alto RPS?
    └── → SUBDIMENSIONAMENTO (limits/requests abaixo do necessário)
        ├── HPA já em máximo (12 réplicas)?
        │   └── → AJUSTE DE LIMITS no deployment (ver Passo 5-B) + escalar se crítico
        └── HPA com capacidade disponível (< 12)?
            └── → FORÇAR SCALE HORIZONTAL temporário (ver Passo 5-C)
                + ajustar limits definitivamente no ticket (ver Passo 7)
```

**Critério de confirmação de leak:**
- `rate(container_memory_working_set_bytes[10m])` positivo e constante por > 30 min sem correlação com carga

**Critério de confirmação de subdimensionamento:**
- Pico de memória correlaciona com pico de RPS no mesmo intervalo de tempo

---

<a name="passo-5"></a>
## Passo 5 — Ação Imediata de Mitigação
**Tempo máximo:** 2 minutos

### 5-A — Memory Leak + Deploy Recente: ROLLBACK via Argo CD

```bash
# Verificar histórico de deploys
argocd app history chronos-api

# Rollback para a versão anterior (substituir <REVISION> pelo número anterior)
argocd app rollback chronos-api <REVISION>

# Monitorar rollout
kubectl rollout status deployment/chronos-api -n $NS

# Confirmar versão após rollback
argocd app get chronos-api | grep "Image\|Revision"
```

### 5-B — Subdimensionamento + HPA no máximo: AJUSTE TEMPORÁRIO DE LIMITS

```bash
# Aumentar memory limit temporariamente (ex: de 512Mi para 768Mi)
kubectl set resources deployment/chronos-api \
  -n $NS \
  --limits=memory=768Mi \
  --requests=memory=512Mi

# Acompanhar rollout
kubectl rollout status deployment/chronos-api -n $NS

# Verificar novos pods com limit ajustado
kubectl get pods -n $NS -l app=$APP -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].resources}{"\n"}{end}'
```

### 5-C — Subdimensionamento + HPA com capacidade: SCALE HORIZONTAL MANUAL

```bash
# Forçar scale para o máximo permitido pelo HPA
kubectl scale deployment/chronos-api -n $NS --replicas=12

# Verificar distribuição de memória após scale
kubectl top pods -n $NS -l app=$APP --sort-by=memory
```

**Verificação esperada após mitigação:**
- Uso de memória cai abaixo de 75% em até 5 minutos
- Sem novos pods em `OOMKilled`
- HPA estabilizando réplicas
- Alerta resolve automaticamente no Prometheus/Grafana

---

<a name="passo-6"></a>
## Passo 6 — Critérios de Escalação para @chronos-core
**Tempo máximo:** 1 minuto

### Escalar IMEDIATAMENTE se:

| Situação | Ação |
|---|---|
| Pods em `OOMKilled` com restarts > 3 nas últimas 2h | Notificar `@chronos-core` no Slack + abrir incidente P1 |
| Memory leak **sem** deploy recente identificado | Escalar para análise de heap/profiling |
| Rollback falhou ou trouxe nova instabilidade | Escalar para decisão de hotfix |
| Degradação de SLA visível (latência p99 > 2s ou erros 5xx > 1%) | Escalar independentemente da causa |
| HPA em máximo (12 réplicas) e memória ainda crescendo | Escalar + avaliar expansão de nodegroup no EKS |
| Incidente >10 min sem redução do alerta | Escalar imediatamente |

### Template de notificação para `#oncall-chronos`:

```
@chronos-core — Incidente em andamento
Alerta: [CRITICAL] High Memory Usage Chronos API
Horário início: HH:MM (UTC-3)
Status atual: [descrever — ex: 3 pods >90%, 1 OOMKilled]
Ações executadas: [rollback / scale / ajuste de limits]
Resultado: [mitigado parcialmente / não resolvido]
Próximo passo necessário: [heap dump / hotfix / expansão cluster]
Runbook: questao_07-runbook_para_alerta_recorrente
```

---

<a name="passo-7"></a>
## Passo 7 — Ajustes Definitivos e Critério de Validação Pós-Fix
**Tempo máximo:** 3 minutos (planejamento; implementação em ticket separado)

### 7.1 — Se causa raiz for SUBDIMENSIONAMENTO

```bash
# Calcular percentil 95 de uso real de memória nas últimas 2 semanas
quantile_over_time(0.95,
  container_memory_working_set_bytes{namespace="production", container="chronos-api"}[14d]
)
```

- Definir novo `requests` = p50 do uso real + 20% de buffer
- Definir novo `limits` = p95 do uso real + 30% de buffer
- Submeter PR no repositório `hvt/chronos-api` com ajuste no `deployment.yaml`
- Realizar deploy via Argo CD em horário de baixo tráfego

```bash
# Validação pós-ajuste (monitorar por 24h)
# Verificar se uso se mantém abaixo de 70% do novo limit
(
  container_memory_working_set_bytes{namespace="production", container="chronos-api"}
  /
  container_spec_memory_limit_bytes{namespace="production", container="chronos-api"}
) * 100
# Esperado: < 70% em regime normal, < 85% em pico
```

### 7.2 — Se causa raiz for MEMORY LEAK

- Abrir issue em `hvt/chronos-api` com label `type: memory-leak` + evidências (gráficos Prometheus)
- Solicitar ao `@chronos-core` coleta de heap dump no próximo evento:

```bash
# Coletar heap dump do pod com maior consumo (substituir <POD_NAME>)
kubectl exec -n $NS <POD_NAME> -- kill -USR1 1
# (ajustar conforme runtime: Java usa jmap, Node usa --inspect, Go usa pprof)

# Copiar dump para análise
kubectl cp $NS/<POD_NAME>:/tmp/heapdump.hprof ./heapdump-$(date +%Y%m%d-%H%M).hprof
```

- Configurar alerta de pré-aviso em 70% de memória para detecção antecipada
- Considerar configuração de `startupProbe` / `readinessProbe` com reinício controlado como mitigação temporária

### 7.3 — Validação pós-fix (ambos os cenários)

**Critério de sucesso após 48h:**
- Nenhum alerta `[CRITICAL] High memory usage` disparado
- `kubectl top pods` mostrando todos os pods abaixo de 75% do limit
- HPA estabilizado entre 4–6 réplicas em horário normal
- Dashboard Grafana sem anomalias no painel de memória

---

<a name="encerramento"></a>
## Critérios de Encerramento do Incidente

### Encerrar quando TODOS os critérios abaixo forem atendidos:

| Critério | Como verificar |
|---|---|
| Todos os pods em `Running` sem restarts recentes | `kubectl get pods -n production -l app=chronos-api` |
| Uso de memória < 75% em todos os pods | `kubectl top pods -n production -l app=chronos-api` |
| Alerta resolvido no Prometheus/Grafana | Dashboard Chronos — painel Memory Usage |
| Sem erros 5xx acima da baseline | Query 3.3 do Passo 3 |
| HPA estável (sem scale events contínuos) | `kubectl describe hpa -n production` |
| Causa raiz documentada | Ticket/issue criado em `hvt/chronos-api` |

### Post-mortem

Criar post-mortem no canal `#oncall-chronos` com:
- Timeline do incidente
- Causa raiz identificada
- Ação de mitigação aplicada
- Ação definitiva planejada + owner + prazo
- Proposta de melhoria de alerta (ex: adicionar alerta em 70% como pré-aviso)

---

*Runbook criado em: 2026-06-07 | Maintainer: SRE On-call | Repositório: hvt/chronos-api*
