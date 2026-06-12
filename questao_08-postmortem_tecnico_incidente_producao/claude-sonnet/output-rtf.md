# POST-MORTEM TÉCNICO — INCIDENTE DE PRODUÇÃO

---

## Título do Incidente

**[SEV-1] Degradação crítica do serviço `chronos-api`: esgotamento de pool de conexões ao Ledger com circuit breaker aberto e acúmulo massivo de mensagens no Reactor**

---

## Data, Duração e Severidade

| Campo            | Valor                                                                 |
|------------------|-----------------------------------------------------------------------|
| **Data**         | 2026-04-24                                                            |
| **Início detectado** | ~14:00 UTC (primeiro sinal claro de degradação: err_rate 0.8%, p99 780ms) |
| **Pico do incidente** | 14:20 UTC (err_rate 11.7%, p99 8100ms, circuit breaker OPEN)     |
| **Duração até agora** | ~20 min de degradação progressiva (incidente em curso)           |
| **Severidade**   | **SEV-1** — impacto direto ao usuário final, circuit breaker aberto, fila de mensagens acumulando sem drenagem |
| **Deploy suspeito** | `chronos-api` v2.48.0 — ArgoCD sync em 2026-04-23 18:42:11 UTC   |

---

## Resumo Executivo

Aproximadamente 19h30 após o deploy da versão v2.48.0 do serviço `chronos-api`, iniciou-se uma degradação progressiva que culminou em falha crítica às 14:20 UTC. O serviço atingiu 11.7% de taxa de erro, latência p99 de 8,1 segundos e o circuit breaker do cliente Ledger foi aberto automaticamente (limiar de 50%, atual 87%).

O cluster está no limite operacional: HPA em capacidade máxima (12/12 pods), conexões RDS em 240/250 (96%), e 50.127 mensagens acumuladas na fila `chronos-transactions` do Reactor, com consumer lag de 18 minutos e crescendo ~800 mensagens/min.

A correlação entre os artefatos do changelog v2.48.0 e os sintomas observados aponta como causa raiz a combinação de: (1) refatoração do pool de conexões do cliente Ledger com parâmetros incompatíveis com a carga de produção, (2) redução do timeout de 5s para 2s causando timeouts em cascata, e (3) o novo endpoint `POST /v2/transactions/batch` multiplicando a pressão sobre o pool. Scaling emergencial do RDS aliviaria sintomas mas não resolveria a causa raiz. **Recomenda-se rollback imediato para v2.47.0.**

---

## Timeline

```
2026-04-23 18:42:11 UTC  →  ArgoCD sincroniza chronos-api v2.48.0 em produção
                              Changelog crítico:
                               - Endpoint POST /v2/transactions/batch adicionado
                               - Pool de conexões migrado para nova biblioteca interna
                               - psycopg 3.1.18 → 3.2.0
                               - Timeout do Ledger: 5s → 2s

2026-04-24 13:30 UTC     →  Baseline aparentemente normal:
                              p99=420ms, req_rate=1200/s, err_rate=0.2%
                              (possível tráfego baixo durante a madrugada; janela sem alertas)

2026-04-24 13:45 UTC     →  Primeiro sinal de deterioração leve:
                              p99=510ms (+21%), err_rate=0.3%

2026-04-24 14:00 UTC     →  Degradação visível: p99=780ms, err_rate=0.8%
                              Início do aumento de req_rate (1780/s) — possível início de retries

2026-04-24 14:10 UTC     →  Ponto de inflexão: p99=2400ms, err_rate=4.5%
                              HPA provavelmente atingiu máximo (12 pods)
                              Conexões RDS começam a se aproximar do limite

2026-04-24 14:15 UTC     →  Cascata em andamento: p99=5200ms, err_rate=8.2%
                              Pool: 20 conexões ativas, 147 requisições aguardando por pod

2026-04-24 14:19:48 UTC  →  LOG: "connection pool exhausted (max=20, active=20, waiting=147)"
2026-04-24 14:19:49 UTC  →  LOG: "query timeout after 2000ms"
2026-04-24 14:19:49 UTC  →  LOG: "POST /v2/transactions/batch failed: context deadline exceeded"
2026-04-24 14:19:50 UTC  →  LOG: "connection reset by peer"
2026-04-24 14:19:51 UTC  →  LOG: "circuit-breaker ledger-client OPEN (threshold 50%, current 87%)"
2026-04-24 14:19:52 UTC  →  LOG: "reactor failed to publish message: chronos-api upstream error"

2026-04-24 14:20 UTC     →  Estado crítico confirmado:
                              p99=8100ms, err_rate=11.7%, req_rate=2650/s
                              RDS: 240/250 conexões ativas
                              Fila Reactor: 50.127 mensagens, lag 18 min (+800/min)
                              INCIDENTE DECLARADO — SEV-1
```

---

## Análise dos Problemas Relacionados ao Deploy v2.48.0

### Problema 1 — Refatoração do pool de conexões com parâmetros subdimensionados

A migração do pool para uma nova biblioteca interna introduziu uma configuração `max=20` conexões por pod. Com 12 pods em produção:

```
12 pods × 20 conexões = 240 conexões totais ao RDS
```

Este valor representa **96% do limite configurado do RDS (250)**, sem margem para spikes. O pool anterior (v2.47.0) provavelmente tinha configuração diferente ou distribuição diferente das conexões. A nova biblioteca pode ter alterado o comportamento de acquire/release de conexões, especialmente sob contenção.

### Problema 2 — Redução do timeout de 5s para 2s sem validação de carga real

O timeout foi reduzido de 5000ms para 2000ms sem análise das queries lentas de produção. Queries que anteriormente completavam entre 2s e 5s (lentas, mas funcionais) agora retornam `context deadline exceeded`, **sem liberar a conexão corretamente** antes do timeout — o que é comportamento conhecido em certas versões do psycopg sob cancelamento abrupto de contexto. Resultado: conexões ficam presas no pool até expirar por TCP (`connection reset by peer`), amplificando o esgotamento.

### Problema 3 — Novo endpoint `POST /v2/transactions/batch` multiplica pressão sobre o pool

O endpoint de batch processa múltiplas transações por requisição HTTP, cada uma possivelmente abrindo uma conexão ao Ledger (ou usando mais tempo de pool por conexão aberta). Com o aumento natural de tráfego (1200→2650 req/s), este endpoint pode ter sido ativado por clientes/workflows, amplificando o consumo de conexões por request.

### Problema 4 — Bump de psycopg 3.1.18 → 3.2.0 não testado sob carga

A versão 3.2.0 do psycopg introduziu mudanças no gerenciamento de conexões assíncronas e no comportamento de cancelamento de queries. Sem testes de carga com a nova versão, o comportamento em cenário de contenção de conexões é desconhecido e pode estar amplificando os problemas 1 e 2.

### Problema 5 — Ausência de alerta proativo no período pós-deploy

O deploy ocorreu às 18:42 UTC (véspera). O incidente levou ~19h30 para se manifestar criticamente — possivelmente por baixo tráfego noturno mascarando o problema. Não há registro de alerta disparado entre 13:30 e 14:10 UTC, quando a degradação já era mensurável.

---

## Causa Raiz

**Causa raiz primária:** A refatoração do cliente Ledger (v2.48.0) introduziu um pool de conexões com `max=20` por pod que, sob a carga de produção de pico (12 pods × 20 = 240 conn ≈ 96% do limite RDS), combinada com a redução do timeout para 2s e o novo endpoint de batch, resultou em esgotamento completo do pool, timeouts em cascata, abertura do circuit breaker e interrupção da publicação de mensagens no Reactor.

**Contribuição secundária:** O bump de psycopg para 3.2.0 pode estar alterando o comportamento de liberação de conexões sob timeout, agravando o esgotamento do pool.

**Fator de latência no diagnóstico:** O problema estava latente desde o deploy (18:42 UTC) mas só se manifestou com o aumento de tráfego durante o horário de pico do dia seguinte.

---

## Árvore de Decisão: Rollback vs. Scaling Emergencial

```
INCIDENTE SEV-1 — chronos-api degradação crítica
│
├─► CAUSA É LIMITAÇÃO DE INFRAESTRUTURA APENAS? (ex: crescimento orgânico de tráfego)
│   │
│   ├─ SIM → Scaling emergencial pode ser a solução
│   │
│   └─ NÃO → Causa é o código/configuração do deploy v2.48.0
│              │
│              ▼
│         ROLLBACK é a solução definitiva  ◄─────────── NOSSO CASO
│
├─► SCALING EMERGENCIAL resolve o problema?
│   │
│   ├─ Aumentar RDS max_connections: 250 → 500
│   │   ✗ Não resolve timeout de 2s (queries ainda vão timeout)
│   │   ✗ Não resolve comportamento do novo pool (biblioteca interna)
│   │   ✗ Não resolve batch endpoint multiplicando conexões
│   │   ✗ Requer reinicialização do RDS (potencial downtime adicional)
│   │   ✓ Alivia temporariamente a pressão de conexões
│   │
│   └─ Aumentar pool por pod: 20 → 40 (configmap + rolling restart)
│       ✗ Apenas dobra o problema: 12 × 40 = 480 conn (excede RDS atual de 250)
│       ✗ Requer mudança de configuração + rolling restart dos pods
│       ✗ Não resolve timeout de 2s
│       ✓ Reduz waiting queue por pod temporariamente
│
└─► ROLLBACK para v2.47.0
    ✓ Reverte pool para configuração testada e estável
    ✓ Reverte timeout para 5s (queries voltam a completar)
    ✓ Remove endpoint batch (que amplifica pressão)
    ✓ Reverte psycopg para versão estabilizada em produção
    ✓ Tempo de execução: 10-15 minutos
    ✓ Solução definitiva para a causa raiz
    ⚠ Fila do Reactor (50k+ mensagens) precisará ser drenada após recovery
    ⚠ Mensagens acumuladas durante o incidente devem ser monitoradas para reprocessamento

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DECISÃO RECOMENDADA: ROLLBACK IMEDIATO PARA v2.47.0
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Comparativo de opções

| Critério                         | Rollback v2.47.0          | Scaling Emergencial          |
|----------------------------------|---------------------------|------------------------------|
| **Tempo de execução**            | 10–15 min                 | 30–50 min                    |
| **Resolve causa raiz**           | ✅ Sim                    | ❌ Não                       |
| **Risco de downtime adicional**  | Baixo (rolling restart)   | Alto (restart RDS)           |
| **Resolve timeout 2s**           | ✅ Sim (reverte para 5s)  | ❌ Não                       |
| **Resolve pool exhaustion**      | ✅ Sim                    | Parcialmente (alivia)        |
| **Resolve circuit breaker**      | ✅ Sim (após recovery)    | ❌ Pode persistir            |
| **Fila do Reactor**              | Drena após recovery       | Continua crescendo           |
| **Complexidade de execução**     | Baixa                     | Alta                         |
| **Requer aprovação adicional**   | Não                       | Sim (RDS change)             |

---

## Roteiro de Execução

### OPÇÃO A (RECOMENDADA): Rollback para v2.47.0

**Tempo estimado total: 10–15 minutos**

#### Pré-condições (verificar antes de iniciar)

```bash
# 1. Confirmar versão atual em produção
kubectl get deployment chronos-api -n production \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: chronos-api:v2.48.0

# 2. Confirmar que a imagem v2.47.0 existe no registry
docker manifest inspect registry.internal/chronos-api:v2.47.0
# ou
skopeo inspect docker://registry.internal/chronos-api:v2.47.0

# 3. Verificar estado atual do ArgoCD
argocd app get chronos-api --server argocd.internal
```

#### Passo 1 — Desabilitar auto-sync no ArgoCD (evitar re-aplicação automática) [~1 min]

```bash
argocd app set chronos-api --sync-policy none \
  --server argocd.internal
```

#### Passo 2 — Executar rollback via ArgoCD [~2 min]

```bash
# Listar histórico de revisions do ArgoCD
argocd app history chronos-api --server argocd.internal

# Identificar o ID da revision correspondente ao deploy de v2.47.0
# (revision anterior ao deploy de 2026-04-23 18:42)

# Executar rollback para a revision identificada
argocd app rollback chronos-api <REVISION_ID> \
  --server argocd.internal
```

**Alternativa via kubectl (se ArgoCD indisponível):**

```bash
# Rollback direto do deployment
kubectl rollout undo deployment/chronos-api -n production

# Verificar que a revision anterior corresponde a v2.47.0
kubectl rollout history deployment/chronos-api -n production
```

#### Passo 3 — Monitorar o rolling restart dos pods [~5–8 min]

```bash
# Acompanhar o rollout em tempo real
kubectl rollout status deployment/chronos-api -n production --watch

# Em outro terminal, monitorar pods sendo substituídos
kubectl get pods -n production -l app=chronos-api --watch
```

> **Atenção:** Durante o rolling restart, os pods novos (v2.47.0) vão subindo enquanto os antigos (v2.48.0) são terminados gradualmente. A taxa de erro pode aumentar brevemente antes de melhorar.

#### Passo 4 — Verificar recuperação das métricas [~2 min após rollout]

```bash
# Verificar versão nos pods novos
kubectl get pods -n production -l app=chronos-api \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'

# Verificar se circuit breaker fechou (buscar nos logs)
kubectl logs -l app=chronos-api -n production --since=2m \
  | grep -E "circuit-breaker|pool exhausted|timeout"

# Verificar conexões RDS (aguardar queda abaixo de 150)
# (via Datadog/CloudWatch/Prometheus — métrica: db_connections_active)
```

#### Passo 5 — Verificar drenagem da fila do Reactor [monitoramento contínuo]

```bash
# Verificar consumer lag atual da fila chronos-transactions
# (via Kafka/SQS/RabbitMQ CLI conforme tecnologia utilizada)

# Exemplo para Kafka:
kafka-consumer-groups.sh --bootstrap-server kafka.internal:9092 \
  --describe --group chronos-reactor-consumer

# Aguardar consumer lag começar a diminuir (indica que Reactor voltou a consumir)
```

> **Atenção crítica:** As 50.127+ mensagens acumuladas devem ser processadas após o recovery. Monitorar se há mensagens com erro de processamento (dead-letter queue) que precisem de reprocessamento manual. Confirmar idempotência do processamento para evitar duplicações.

#### Passo 6 — Confirmar estabilização e comunicar [~1 min]

```bash
# Checklist de confirmação:
# [ ] Todos os 12 pods rodando v2.47.0
# [ ] err_rate < 0.5% por 5 minutos consecutivos
# [ ] p99 latency < 600ms
# [ ] Conexões RDS < 150/250
# [ ] Circuit breaker CLOSED
# [ ] Consumer lag do Reactor em queda

# Comunicar no canal de incidentes:
# "chronos-api rollback para v2.47.0 concluído. Métricas em normalização.
#  Monitorando fila Reactor (50k+ msgs). ETA drenagem: ~1h."
```

#### Passo 7 — Reabilitar auto-sync no ArgoCD (somente após estabilização total)

```bash
argocd app set chronos-api --sync-policy automated \
  --self-heal --server argocd.internal
# NOTA: Isso sincronizará com o HEAD do repositório — garantir que
# o HEAD aponte para v2.47.0 antes de reabilitar.
```

---

### OPÇÃO B (NÃO RECOMENDADA — apenas se rollback for inviável): Scaling Emergencial

**Tempo estimado total: 30–50 minutos**
**Risco: NÃO resolve a causa raiz. Medida paliativa.**

#### Passo 1 — Aumentar max_connections no RDS [~15–20 min]

> **Atenção:** Mudança de `max_connections` em RDS PostgreSQL requer modificação do parameter group e pode exigir **reinicialização da instância** (downtime adicional de 1–5 min).

```bash
# Via AWS CLI — modificar parameter group
aws rds modify-db-parameter-group \
  --db-parameter-group-name ledger-prod-pg \
  --parameters "ParameterName=max_connections,ParameterValue=500,ApplyMethod=pending-reboot"

# Verificar se há parameter group dinâmico disponível (sem reboot):
aws rds describe-db-parameters \
  --db-parameter-group-name ledger-prod-pg \
  --query "Parameters[?ParameterName=='max_connections']"
# Se ApplyType = 'static' → requer reboot
# Se ApplyType = 'dynamic' → aplica sem reboot

# Aplicar reboot (se necessário — confirmar com DBA/responsável):
aws rds reboot-db-instance --db-instance-identifier ledger-prod
# DOWNTIME: ~2–5 minutos de indisponibilidade total do banco
```

#### Passo 2 — Aumentar pool size no configmap do chronos-api [~5 min]

```bash
# Editar configmap com novo tamanho de pool
kubectl edit configmap chronos-api-config -n production
# Alterar: LEDGER_POOL_MAX_CONNECTIONS: "20" → "30"
# (com 12 pods: 12 × 30 = 360 conn — dentro dos 500 novos)

# Rolling restart para aplicar a nova configuração
kubectl rollout restart deployment/chronos-api -n production

# Monitorar rollout
kubectl rollout status deployment/chronos-api -n production --watch
```

#### Passo 3 — Monitorar se o scaling foi suficiente [~5–10 min]

```bash
# Verificar se err_rate cai abaixo de 2% após restart
# Verificar se circuit breaker fecha
# Se circuit breaker permanecer OPEN após 5 min → ESCALAR PARA ROLLBACK IMEDIATO
```

> **Critério de abort:** Se após 10 minutos do scaling o circuit breaker não fechar ou o err_rate não cair abaixo de 2%, executar rollback imediatamente (Opção A). Cada minuto adicional = ~800 mensagens a mais no Reactor.

---

## Causa Raiz Detalhada

### Diagrama de falha em cascata

```
Deploy v2.48.0
     │
     ├─► Pool refatorado: max=20/pod × 12 pods = 240 conn (96% do limite RDS)
     │
     ├─► Timeout reduzido: 5s → 2s (queries lentas agora expiram)
     │
     └─► Endpoint /v2/transactions/batch (múltiplas conn por request)
              │
              ▼
         Pico de tráfego (14:00 UTC)
              │
              ▼
         Queries lentas atingem 2s → timeout → conn não liberada limpa
              │
              ▼
         Pool por pod: active=20, waiting=147
              │
              ▼
         RDS: 240/250 conexões (sem margem)
              │
              ▼
         Novas requisições falham imediatamente (pool exhausted)
              │
              ▼
         Circuit breaker: 87% de erro → OPEN
              │
              ▼
         Reactor: não consegue publicar mensagens
              │
              ▼
         50k+ mensagens acumuladas, lag 18 min e crescendo
```

---

## Ações Corretivas

| # | Ação                                                                                    | Responsável            | Prazo         | Status   |
|---|-----------------------------------------------------------------------------------------|------------------------|---------------|----------|
| 1 | **Executar rollback para v2.47.0** conforme roteiro (Opção A)                           | SRE de plantão         | **Imediato**  | PENDENTE |
| 2 | Monitorar drenagem da fila `chronos-transactions` no Reactor após recovery              | SRE de plantão         | Imediato      | PENDENTE |
| 3 | Verificar mensagens na dead-letter queue e avaliar reprocessamento                      | SRE + Dev              | Imediato      | PENDENTE |
| 4 | Comunicar status ao CTO e stakeholders via canal de incidente                           | SRE de plantão         | Imediato      | PENDENTE |
| 5 | Revisar configuração do pool na nova biblioteca interna para v2.48.0                    | Dev responsável        | 2026-04-25    | PENDENTE |
| 6 | Validar comportamento do psycopg 3.2.0 sob contenção de conexões (benchmark)            | Dev + SRE              | 2026-04-25    | PENDENTE |
| 7 | Revisar timeout de 2s: validar p99 real das queries do Ledger antes de reduzir          | Dev responsável        | 2026-04-25    | PENDENTE |
| 8 | Definir limite seguro de conexões por pod com base no `max_connections` do RDS          | SRE + DBA              | 2026-04-25    | PENDENTE |
| 9 | Re-deploy de v2.48.0 somente após correccões dos itens 5–8 com testes de carga          | Dev + SRE              | 2026-04-28    | PENDENTE |

---

## Ações Preventivas

### Processo e cultura

| # | Ação Preventiva                                                                                                          | Responsável         | Prazo         |
|---|--------------------------------------------------------------------------------------------------------------------------|---------------------|---------------|
| 1 | Incluir **teste de carga obrigatório** (k6/Gatling) no pipeline de CI/CD para deploys que alteram cliente de DB ou pool  | Platform/SRE        | 2026-05-01    |
| 2 | Criar **checklist de deploy** com campos obrigatórios para mudanças de timeout, pool size e upgrade de driver de DB      | Dev Lead            | 2026-04-28    |
| 3 | Implementar **canary deploy** (5% → 25% → 100%) para serviços críticos como `chronos-api`                               | Platform/SRE        | 2026-05-15    |
| 4 | Definir **freeze window** de 12h pós-deploy para monitoramento de métricas antes de considerar deploy estável            | SRE + Dev Lead      | 2026-04-28    |

### Observabilidade e alertas

| # | Ação Preventiva                                                                                                          | Responsável         | Prazo         |
|---|--------------------------------------------------------------------------------------------------------------------------|---------------------|---------------|
| 5 | Criar alerta **PagerDuty/OpsGenie**: `db_pool_waiting > 10` por mais de 2 minutos → SEV-2                               | SRE                 | 2026-04-26    |
| 6 | Criar alerta: `db_connections_active / db_connections_max > 0.80` → SEV-2                                               | SRE + DBA           | 2026-04-26    |
| 7 | Criar alerta: `circuit_breaker_state == OPEN` → SEV-1 imediato                                                           | SRE                 | 2026-04-26    |
| 8 | Adicionar dashboard de **Reactor consumer lag** com threshold de alerta em 5 minutos de lag                              | SRE                 | 2026-04-27    |
| 9 | Incluir métricas de pool (active, waiting, idle) no Beacon/Prometheus via instrumentação do cliente Ledger               | Dev responsável     | 2026-04-29    |

### Infraestrutura e configuração

| # | Ação Preventiva                                                                                                          | Responsável         | Prazo         |
|---|--------------------------------------------------------------------------------------------------------------------------|---------------------|---------------|
| 10| Revisar `max_connections` do RDS Ledger: calcular headroom mínimo de 30% acima do baseline de produção                  | DBA + SRE           | 2026-04-27    |
| 11| Documentar e versionar no repositório a equação de dimensionamento de pool: `max_pod_connections = (rds_max × 0.7) / num_pods` | SRE + Dev Lead | 2026-04-28    |
| 12| Avaliar uso de **PgBouncer** (connection pooler externo) para desacoplar o pool da aplicação do limite do RDS           | DBA + SRE           | 2026-05-15    |

---

## Conclusão e Recomendação ao CTO

Com base na análise dos logs, métricas e changelog do deploy v2.48.0, a causa raiz do incidente é técnica e está **diretamente vinculada ao código introduzido no deploy de ontem**. O scaling emergencial aliviaria sintomas de conexões por aproximadamente 15–20 minutos, mas não resolve o timeout de 2s (queries continuarão expirando), não corrige potenciais bugs na nova biblioteca de pool e não remove o endpoint batch que está amplificando a pressão.

**Recomendação: Rollback imediato para v2.47.0 (10–15 minutos).**

O rollback é a ação com menor risco, menor tempo de execução e que resolve definitivamente a causa raiz. As correções necessárias para o v2.48.0 devem ser implementadas, testadas sob carga e re-deployadas após validação em staging com tráfego simulado de produção.

---

*Documento gerado pelo SRE de plantão em 2026-04-24 14:25 UTC.*
*Revisão pendente após resolução do incidente.*
