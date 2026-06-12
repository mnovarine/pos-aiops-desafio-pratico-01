# Post-Mortem Técnico — Incidente de Produção

---

## Título do Incidente

**[SEV-1] Degradação Severa do chronos-api por Esgotamento de Pool de Conexões após Deploy v2.48.0**

---

## Metadados

| Campo | Valor |
|---|---|
| **Data do Incidente** | 2026-04-24 |
| **Início da Degradação** | 2026-04-24 ~13:30 UTC |
| **Detecção Crítica** | 2026-04-24 14:10 UTC |
| **Status atual** | Em andamento (aberto no momento da escrita) |
| **Duração até a escrita** | ~50 minutos de degradação progressiva |
| **Severidade** | SEV-1 (impacto direto em usuários finais, >10% de erro, circuit breaker aberto) |
| **Serviços impactados** | chronos-api, Reactor (fila chronos-transactions), Ledger (RDS) |
| **Deploy precursor** | chronos-api v2.47.0 → v2.48.0 (2026-04-23 18:42:11 UTC) |
| **Autor do post-mortem** | SRE on-call |

---

## Resumo Executivo

Na tarde de 2026-04-24, o serviço `chronos-api` entrou em degradação progressiva culminando em falha severa a partir das 14:10 UTC. A **causa raiz** é uma combinação de três mudanças introduzidas no deploy v2.48.0 (2026-04-23 18:42 UTC):

1. **Redução do timeout do Ledger de 5s para 2s** — queries legítimas que levam entre 2s e 5s agora expiram, gerando retentativas e pressão adicional sobre o pool.
2. **Refatoração do pool de conexões para nova biblioteca interna** — o novo pool mantém `max=20` conexões por pod; com 12 pods no HPA máximo, isso resulta em exatamente **240 conexões abertas ao RDS**, tocando o limite de 250.
3. **Novo endpoint `POST /v2/transactions/batch`** — operações em lote consomem múltiplas conexões do pool por requisição, acelerando o esgotamento sob carga alta.

O aumento natural de tráfego durante o horário comercial (de 1.200 para 2.650 req/s) foi o gatilho que tornou o problema crítico ~19 horas após o deploy. O circuit breaker do `ledger-client` abriu a 87% de falhas, paralisando o consumo do Reactor e acumulando mais de 50.000 mensagens na fila `chronos-transactions`.

**Recomendação imediata: executar rollback para v2.47.0.** O scaling emergencial é tecnicamente possível, mas mais lento, mais arriscado e não resolve o problema do timeout de 2s.

---

## Timeline dos Marcos Críticos

```
2026-04-23 18:42 UTC  [DEPLOY]  ArgoCD sync: chronos-api v2.47.0 → v2.48.0
                                 Novo pool de conexões ativo, timeout reduzido para 2s.

2026-04-24 13:30 UTC  [WARN]    p99=420ms, err=0.2% — primeiros sinais acima do baseline.
                                 Tráfego em 1.200 req/s; pool ainda não saturado.

2026-04-24 13:45 UTC  [WARN]    p99=510ms, err=0.3% — degradação acelerando com tráfego.
                                 Tráfego sobe para 1.450 req/s.

2026-04-24 14:00 UTC  [WARN]    p99=780ms, err=0.8% — queries do Ledger começam a tocar
                                 o timeout de 2s. Retentativas aumentam pressão no pool.
                                 Tráfego: 1.780 req/s.

2026-04-24 14:10 UTC  [CRIT]    p99=2.400ms, err=4.5% — LIMIAR CRÍTICO ULTRAPASSADO.
                                 HPA atinge máximo (12/12 pods). 12×20=240 conexões ao RDS.
                                 Tráfego: 2.100 req/s.

2026-04-24 14:15 UTC  [CRIT]    p99=5.200ms, err=8.2% — conexões RDS: 240/250.
                                 Pool exhausted: 147 requisições aguardando conexão.
                                 Tráfego: 2.400 req/s.

2026-04-24 14:19 UTC  [CRIT]    Logs do pod chronos-api-79c4d8b9-xk2jp:
                                 - "connection pool exhausted (max=20, active=20, waiting=147)"
                                 - "query timeout after 2000ms"
                                 - "POST /v2/transactions/batch failed: context deadline exceeded"
                                 - "connection reset by peer"
                                 - circuit-breaker ledger-client OPEN (threshold 50%, atual 87%)
                                 - Reactor falha ao publicar mensagem.

2026-04-24 14:20 UTC  [CRIT]    p99=8.100ms, err=11.7% — colapso total do fluxo de
                                 transações. Reactor: 50.127 msgs acumuladas, lag=18min
                                 e crescendo a ~800/min. Tráfego: 2.650 req/s.

2026-04-24 ~14:25 UTC [NOW]     Post-mortem em escrita. Decisão pendente: rollback vs scaling.
```

---

## Análise da Causa Raiz

### Diagrama de Causa e Efeito (Fishbone)

```
                    ┌─────────────────────────────────────────┐
                    │  SEV-1: chronos-api em colapso (14:20)  │
                    └──────────────────┬──────────────────────┘
                                       │
          ┌────────────────────────────┼────────────────────────────┐
          │                            │                            │
          ▼                            ▼                            ▼
  Timeout 5s→2s              Pool refatorado              Endpoint /batch
  (queries legítimas         (comportamento mudado,        (N conexões por
   expiram → retries)         pool não compartilhado       requisição → pior
                              entre coroutines?)           caso de saturação)
          │                            │                            │
          └────────────────────────────┼────────────────────────────┘
                                       │
                                       ▼
                         Pool exhausted (max=20/pod)
                         12 pods × 20 = 240 conexões
                         RDS limite: 250 → 240/250 ativas
                                       │
                                       ▼
                    Queries enfileiradas → todos expiram em 2s
                    → mais retries → mais fila → loop positivo
                                       │
                                       ▼
                         Circuit breaker OPEN (87%)
                                       │
                          ┌────────────┴────────────┐
                          ▼                         ▼
                  API retornando             Reactor não publica
                  11.7% de erro             50k msgs acumuladas
```

### Evidências Correlacionadas

| Evidência | Interpretação |
|---|---|
| `connection pool exhausted (max=20, active=20, waiting=147)` | Cada pod tem exatamente 20 conexões disponíveis — refatoração não aumentou o pool |
| `12 pods × 20 conn = 240` e `RDS: 240/250` | Confirmação matemática: o limite do RDS é saturado pelo HPA no máximo |
| `query timeout after 2000ms` | O timeout de 2s é muito agressivo; queries de lote naturalmente levam mais tempo |
| `POST /v2/transactions/batch failed` | O novo endpoint é o principal consumidor das conexões em pool |
| CPU 62%, Memória 71% | Recursos computacionais dos pods **não são o gargalo** — descarta scaling horizontal |
| Circuit breaker a 87% com threshold de 50% | Degradação já ultrapassou ponto de recuperação automática |
| Reactor: 50k msgs, crescendo 800/min | Backpressure secundário — problema continuará mesmo após estabilização da API |

### Por que manifestou ~19h após o deploy?

O deploy foi às 18:42 UTC (horário de menor tráfego). O incidente só se tornou crítico às 14:10 UTC do dia seguinte porque:
- Tráfego noturno estava abaixo do limiar de saturação (~1.200 req/s)
- O aumento natural de tráfego no horário comercial empurrou o sistema para além do ponto crítico
- Com o novo pool + timeout menor, o sistema tem uma **capacidade efetiva menor** do que v2.47.0 para a mesma carga

---

## Árvore de Decisão: Rollback vs Scaling Emergencial

```
                    DECISÃO URGENTE
                         │
           ┌─────────────┴─────────────┐
           │                           │
     ROLLBACK v2.47.0          SCALING EMERGENCIAL
     (recomendado ✓)           (não recomendado ✗)
           │                           │
     Tempo: ~15-20 min          Tempo: ~45-90 min
           │                           │
     Risco: baixo               Risco: médio-alto
           │                           │
     ┌─────┴──────┐           ┌────────┴────────┐
     │            │           │                 │
  Resolve?     Perde?     Resolve o        Resolve o
     │            │       timeout?          pool?
     │            │           │                 │
    Sim:        Sim:         NÃO              Parcialmente:
  timeout,    endpoint      (2s ainda         Aumentar RDS
  pool,       /batch        causará           max_conn requer
  psycopg     e psycopg     cascata)          restart/reboot
  bump        bump                            de instância
                                              (janela de
                                              manutenção)
```

### Veredicto: **ROLLBACK é a ação correta**

**Razões para NÃO fazer scaling emergencial:**

1. O timeout de 2s é o acelerador da cascata — scaling não o corrige. Com mais conexões disponíveis, queries ainda vão expirar em 2s e gerar mais retries, saturando o pool maior em menos tempo.
2. Modificar `max_connections` no RDS pode exigir reinicialização da instância dependendo da classe (ex: `db.t3.*` requer reboot para alterações de parâmetros), adicionando downtime controlado no pior momento.
3. Aumentar o pool por pod via variável de ambiente requer um novo deploy — que é mais lento que um rollback pelo ArgoCD.
4. Scaling emergencial **não reverte** o psycopg bump (3.2.0), cuja regressão de comportamento com o novo pool não foi validada.
5. Mesmo que o scaling funcione, o Reactor tem 50k mensagens acumuladas que causarão spike de reconexão ao ser drenado.

**Únicos cenários onde scaling seria preferível:**
- Se v2.47.0 tiver um bug crítico de segurança que impeça o rollback
- Se o rollback for tecnicamente impossível (imagem não disponível no registry)

---

## Roteiro de Execução

### OPÇÃO A — Rollback para v2.47.0 (RECOMENDADO)

**Tempo estimado total: 15–20 minutos**

#### Passo 1 — Notificar stakeholders (2 min)
```
Slack #incidents:
[SEV-1] chronos-api: iniciando rollback para v2.47.0
Responsável: <SRE on-call>
ETA de estabilização: ~20 min a partir de agora
```

#### Passo 2 — Verificar disponibilidade da imagem v2.47.0 (1 min)
```bash
# Confirmar que a imagem existe no registry antes de prosseguir
kubectl -n chronos get deployment chronos-api \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Verificar tag v2.47.0 no registry (exemplo ECR)
aws ecr describe-images \
  --repository-name chronos-api \
  --image-ids imageTag=v2.47.0 \
  --query 'imageDetails[0].imagePushedAt'
```

#### Passo 3 — Executar rollback via ArgoCD (5 min)
```bash
# Opção A1 — Via ArgoCD CLI (preferencial — auditável)
argocd app rollback chronos-api --revision <git-sha-v2.47.0>

# Opção A2 — Via kubectl diretamente (se ArgoCD inacessível)
kubectl -n chronos set image deployment/chronos-api \
  chronos-api=<registry>/chronos-api:v2.47.0

# Acompanhar rolling update
kubectl -n chronos rollout status deployment/chronos-api --timeout=5m
```

> **Atenção:** Caso o ArgoCD esteja com auto-sync habilitado, desabilitar antes do rollback manual:
> ```bash
> argocd app set chronos-api --sync-policy none
> ```

#### Passo 4 — Monitorar estabilização (5 min)
```bash
# Verificar pods em execução com nova imagem
kubectl -n chronos get pods -l app=chronos-api \
  -o custom-columns='NAME:.metadata.name,IMAGE:.spec.containers[0].image,STATUS:.status.phase'

# Monitorar conexões ao RDS (deve cair de 240 para ~120 durante rolling)
watch -n5 'kubectl -n chronos exec -it deploy/chronos-api -- \
  python -c "import psycopg; print(psycopg.connect(os.environ[\"DB_URL\"]).execute(
    \"SELECT count(*) FROM pg_stat_activity WHERE application_name='"'"'chronos-api'"'"'\").fetchone())"'

# Verificar circuit breaker (deve fechar em ~30s após conexões se normalizarem)
kubectl -n chronos logs -l app=chronos-api --since=2m | grep circuit-breaker

# Acompanhar taxa de erro no Beacon
# Esperado: err_rate_pct < 1% em ~5 min após rollout completo
```

#### Passo 5 — Validar recuperação do Reactor (3 min)
```bash
# Verificar consumer lag (deve parar de crescer e começar a cair)
# Exemplo com Kafka CLI
kafka-consumer-groups.sh \
  --bootstrap-server <broker> \
  --describe \
  --group chronos-transactions-consumer | grep LAG

# Monitorar drenagem: lag esperado cair de 18min → <2min em ~30-40min
# NÃO reiniciar o Reactor — deixar drenar naturalmente para evitar spike de conexões
```

#### Passo 6 — Confirmar estabilização e comunicar (2 min)
```
Métricas de aceitação para fechar o incidente:
  ✓ err_rate_pct < 0.5% por 5 minutos consecutivos
  ✓ p99_latency_ms < 500ms
  ✓ Circuit breaker CLOSED
  ✓ RDS conexões < 160 (12 pods × ~13 conexões médias v2.47.0)
  ✓ Reactor consumer lag decrescendo

Slack #incidents:
[SEV-1 RESOLVED] chronos-api estabilizado em v2.47.0
Reactor drenando normalmente. Post-mortem completo em <link>.
```

---

### OPÇÃO B — Scaling Emergencial (NÃO RECOMENDADO — apenas se rollback for inviável)

**Tempo estimado total: 45–90 minutos**

#### Passo B1 — Aumentar max_connections no RDS (15–30 min)
```bash
# Verificar parameter group atual
aws rds describe-db-instances \
  --db-instance-identifier ledger-db \
  --query 'DBInstances[0].DBParameterGroups'

# Criar parameter group customizado (se ainda não existir)
aws rds create-db-cluster-parameter-group \
  --db-cluster-parameter-group-name ledger-db-custom \
  --db-parameter-group-family postgres15 \
  --description "Custom params for ledger-db"

# Modificar max_connections (de 250 para 500)
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name ledger-db-custom \
  --parameters "ParameterName=max_connections,ParameterValue=500,ApplyMethod=pending-reboot"

# ATENÇÃO: max_connections requer reboot da instância para aplicar
# Verificar se a mudança requer reboot:
aws rds describe-db-parameters \
  --db-parameter-group-name ledger-db-custom \
  --query "Parameters[?ParameterName=='max_connections']"

# Se ApplyType=static → reboot obrigatório (janela de ~2-5 min de indisponibilidade do RDS)
aws rds reboot-db-instance --db-instance-identifier ledger-db
aws rds wait db-instance-available --db-instance-identifier ledger-db
```

#### Passo B2 — Aumentar pool de conexões por pod (15–20 min)
```bash
# Editar variável de ambiente (ajustar conforme o nome real da var)
# Novo valor: 40 por pod → 12×40=480, dentro do novo limite de 500
kubectl -n chronos set env deployment/chronos-api \
  LEDGER_POOL_MAX_CONNECTIONS=40 \
  LEDGER_QUERY_TIMEOUT_MS=5000

# Aguardar rolling update
kubectl -n chronos rollout status deployment/chronos-api --timeout=5m
```

#### Passo B3 — Reverter timeout para 5s (incluso no B2 acima)
> O timeout de 2s **deve** ser revertido para 5s mesmo no cenário de scaling.
> Sem isso, o scaling apenas posterga o colapso.

#### Passo B4 — Monitorar e validar (10 min)
> Mesmos critérios de aceitação da Opção A (Passo 6).

#### Riscos adicionais do Scaling Emergencial:
- Reboot do RDS causa spike de reconexão de todos os clientes simultaneamente
- Reactor com 50k mensagens vai explodir em conexões ao ser drenado após reboot
- psycopg 3.2.0 + nova biblioteca de pool permanecem sem validação adequada
- Novo endpoint `/batch` continua em produção sem análise de carga

---

## Causa Raiz

### Causa Imediata
Esgotamento do pool de conexões ao Ledger (`max=20/pod`) com 12 pods no limite do HPA, resultando em 240/250 conexões ao RDS e timeout agressivo de 2s causando cascata de falhas.

### Causa Raiz Técnica
Três mudanças simultâneas no deploy v2.48.0, sem testes de carga adequados, alteraram o comportamento do sistema sob tráfego elevado:

1. **Timeout reduzido (5s→2s)** sem validação do percentil de latência atual das queries do Ledger. O p99 estava em 420ms às 13:30, mas queries do endpoint `/batch` claramente ultrapassam 2s.
2. **Refatoração do pool de conexões** para nova biblioteca interna sem validação da semântica de pool (compartilhamento entre coroutines/threads, comportamento de `max`, `min_idle`, etc.).
3. **Endpoint `/batch`** em produção sem análise de impacto no pool (N operações de banco por chamada HTTP).

### Causa Raiz de Processo
- Ausência de testes de carga/soak no pipeline de CI/CD antes de deploy em produção
- Múltiplas mudanças de infraestrutura (pool, timeout, psycopg) agrupadas em um único deploy
- Sem análise de capacidade (capacity planning) para o novo endpoint antes do go-live

---

## Ações Corretivas

| # | Ação | Responsável sugerido | Prazo |
|---|---|---|---|
| AC-1 | **Executar rollback imediato** para v2.47.0 via ArgoCD | SRE on-call | **Agora — 15 min** |
| AC-2 | Desabilitar auto-sync do ArgoCD para `chronos-api` até conclusão da investigação | SRE on-call | **Agora** |
| AC-3 | Monitorar drenagem do Reactor (fila `chronos-transactions`) e garantir que consumer lag retorne a < 2 min | SRE on-call | **Hoje — 2h pós-rollback** |
| AC-4 | Validar o comportamento da nova biblioteca de pool de conexões com testes de carga (k6/locust) em staging com tráfego equivalente ao pico de produção (2.650 req/s) | Tech Lead chronos-api | **Antes do próximo deploy de v2.48.0** |
| AC-5 | Instrumentar métricas do pool de conexões: `pool_size`, `pool_checked_out`, `pool_waiting` — expor via `/metrics` (Prometheus) | Dev + SRE | **Sprint atual** |
| AC-6 | Definir e documentar o timeout adequado para o Ledger com base em dados de p99/p999 das últimas 4 semanas | Tech Lead + DBA | **48h** |
| AC-7 | Validar upgrade psycopg 3.1.18→3.2.0 isoladamente em staging com testes de integração do pool | Dev | **Antes do próximo deploy** |
| AC-8 | Criar alerta no Beacon/Datadog para `ledger_pool_waiting > 10` por mais de 60 segundos | SRE | **Esta semana** |
| AC-9 | Criar alerta para `rds_connections_active / rds_connections_max > 0.80` | SRE + DBA | **Esta semana** |
| AC-10 | Analisar e configurar `connection_pool_recycle`, `pool_pre_ping` e backoff no novo cliente do Ledger antes de reintroduzir em produção | Dev + Tech Lead | **Antes do próximo deploy** |

---

## Ações Preventivas

| # | Ação | Responsável sugerido | Prazo |
|---|---|---|---|
| AP-1 | **Obrigatório: testes de carga em staging** antes de qualquer deploy que altere pool de conexões, timeouts ou introduza novos endpoints com acesso ao banco | Engenharia + SRE | **Definir policy — 1 semana** |
| AP-2 | **Proibir deploys com múltiplas mudanças de infraestrutura simultâneas** (pool + timeout + upgrade de driver + novo endpoint = 4 mudanças num deploy). Separar em PRs/deploys independentes | Tech Lead + EM | **Definir policy — 1 semana** |
| AP-3 | Implementar **canary deploy** para `chronos-api`: 5% do tráfego por 30 min antes de rollout completo. Integrar com ArgoCD Rollouts ou Flagger | SRE + Platform | **1 mês** |
| AP-4 | Adicionar **capacity planning automatizado**: alertar quando `req_rate × connections_per_req > 0.70 × max_connections` | SRE | **2 semanas** |
| AP-5 | Adicionar ao runbook de deploy de `chronos-api` o checklist de validação pós-deploy com critérios de rollback automático | SRE | **Esta semana** |
| AP-6 | Implementar **circuit breaker com retry budget** no lado do Reactor para evitar que falhas da API propaguem acúmulo ilimitado na fila | Dev | **Sprint seguinte** |
| AP-7 | Revisar o limite de `max_connections` do RDS e calcular headroom adequado para o HPA máximo de todos os serviços que acessam o Ledger | DBA + SRE | **2 semanas** |
| AP-8 | Criar **runbook de degradação de pool de conexões** com steps de diagnóstico e remediação (evitar ter que criar este post-mortem sob pressão na próxima vez) | SRE | **Esta semana** |

---

## Lições Aprendidas

1. **Timeout é uma arma de dois gumes**: Reduzir timeout melhora latência percebida mas, sob carga, aumenta a taxa de falhas e a pressão de retentativas — criando um loop positivo de degradação. Mudanças de timeout devem ser validadas contra o percentil p99/p999 atual da dependência.

2. **Pool de conexões é infraestrutura crítica**: Mudar a biblioteca de pool é equivalente a mudar o driver de banco. Requer validação de carga completa e instrumentação antes de produção.

3. **A matemática do HPA máximo deve ser conhecida**: `max_pods × connections_per_pod` deve ser monitorado e nunca deve ultrapassar 80% do `max_connections` do RDS.

4. **Agregar múltiplas mudanças de risco num deploy aumenta o blast radius**: Quanto mais difícil identificar a causa raiz, mais tempo de incidente.

5. **O Reactor precisa de backpressure**: Uma fila sem limite de acúmulo em incidentes de upstream transforma um problema de 20 minutos em um problema de 2 horas de drenagem.

---

*Documento gerado em: 2026-04-24 — SRE on-call*
*Status: Rascunho para revisão do CTO antes de execução da ação AC-1*
