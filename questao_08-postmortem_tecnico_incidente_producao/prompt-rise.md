## Prompt

```markdown
# Role
Você é um SRE responsável pelo plantão e por criar runbooks e procedimentos documentados e precisa gerar um documento de post-morten técnico para o CTO para decidir entre rollback do deploy v2.48.0 (que subiu ontem) e scaling emergencial (aumento de limits do RDS e do pool de conexões).

# Input
- Evento do deploy anterior (ontem, 18:42 UTC):
Deploy chronos-api: v2.47.0 -> v2.48.0
Argo CD sync: 2026-04-23 18:42:11 UTC
Changelog:
- Adicionado endpoint POST /v2/transactions/batch
- Refatorado cliente do Ledger (pool de conexoes movido para nova biblioteca interna)
- Bump de psycopg 3.1.18 -> 3.2.0
- Reduzido timeout do Ledger de 5s para 2s

- Métricas do Beacon nos últimos 30 minutos:
timestamp                p99_latency_ms   req_rate_s   err_rate_pct
2026-04-24 13:30 UTC     420              1200         0.2
2026-04-24 13:45 UTC     510              1450         0.3
2026-04-24 14:00 UTC     780              1780         0.8
2026-04-24 14:10 UTC     2400             2100         4.5
2026-04-24 14:15 UTC     5200             2400         8.2
2026-04-24 14:20 UTC     8100             2650         11.7

- Trecho do log do pod chronos-api-79c4d8b9-xk2jp:

2026-04-24 14:19:48 [ERROR] [ledger-client] connection pool exhausted (max=20, active=20, waiting=147)
2026-04-24 14:19:49 [WARN]  [ledger-client] query timeout after 2000ms: SELECT ... FROM transactions WHERE ...
2026-04-24 14:19:49 [ERROR] [handler] POST /v2/transactions/batch failed: context deadline exceeded
2026-04-24 14:19:50 [ERROR] [ledger-client] connection reset by peer
2026-04-24 14:19:51 [WARN]  [circuit-breaker] ledger-client OPEN (threshold 50%, current 87%)
2026-04-24 14:19:52 [ERROR] [reactor] failed to publish message: chronos-api upstream error

- Estado do Reactor (fila chronos-transactions):
50.127 mensagens acumuladas, crescendo a ~800/min.
Consumer lag atual: 18 minutos e aumentando.

- Estado do cluster:
Chronos: 12/12 pods running (HPA no máximo).
CPU médio dos pods: 62%.
Memória média dos pods: 71%.
Conexões ativas ao Ledger: 240/250 (limite do RDS).

# Steps
1. Analisar os eventos do deploy anterior
2. Analisar as métricas do Beacon
3. Analisar as logs do pod chronos-api
4. Analisar o estado do Reactor
5. Analisar o estado do cluster
6. Montar a timeline com os marcos críticos

# Expectation
Post-morten técnico para decidir entre rollback do deploy v2.48.0 (que subiu ontem) e scaling emergencial (aumento de limits do RDS e do pool de conexões):
- Árvore de decisão: rollback vs scaling emergencial
- Tempo estimado de cada descisão
- Analisar os possíveis problemas relacionados ao deplor da nova versão
- Roteiro detalhado de como executar cada passo de do rollback ou scaling

Use o formato:
- Título do incidente
- Data, duração, severidade
- Resumo executivo
- Timeline
- Causa raiz
- Ações corretivas (com responsável sugerido e prazo)
- Ações preventivas
```