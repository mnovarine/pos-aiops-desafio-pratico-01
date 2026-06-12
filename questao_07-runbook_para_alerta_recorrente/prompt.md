## Prompt

```markdown
# Role
Você é um SRE responsável pelo plantão e por criar runbooks e procedimentos documentados.

# Input
- Ambiente: API Chronos roda no EKS, namespace production, 6 réplicas com HPA configurado (min 4, max 12, CPU target 70%).
- Deploy: via Argo CD a partir do repositório hvt/chronos-api.
- Dependências diretas: Ledger (PostgreSQL) e Reactor (filas SQS).
- Observabilidade: métricas expostas em /metrics, logs centralizados no Beacon, dashboards em Grafana.
- Ferramentas disponíveis para o plantão: kubectl, aws cli, argocd cli.
- Canal de plantão: #oncall-chronos no Slack.
- Time sênior de escalação: @chronos-core (SLA de resposta: 15 minutos em horário comercial, 30 fora).
- Sintoma: Em média 4 vezes por semana, recebimento de alerta "[CRITICAL] High memory usage on Chronos API pods (>85% for 10min)"

# Steps
1. Confirmar o estado atual dos pods e coletar métricas de utilização de memória
2. Analisar métricas de memória no Prometheus (últimas 1 hora, correlacionar com o deploy)
3. Verificar métricas de utilização da api chronos, se há picos, horários de maior acesso e volumetria
4. Avaliar se é memory leak ou se o sizing está subdimensionado
5. Definir ação imediata de mitigação (ajuste de limits, rollback ou scale horizontal)
6. Documentar critérios de escalação (quando envolver o time de desenvolvimento)
7. Propor ajustes definitivos e critério de validação pós-fix

# Expectation
Espero um runbook operacional completo com verificação esperada ao final de cada passo:
- Comandos kubectl prontos para copiar e colar em cada etapa
- Queries PromQL para investigação de memória
- Árvore de decisão: leak vs subdimensionamento → ação correspondente
- Tempo máximo por etapa (total não deve passar de 15 minutos)
- Critérios claros de quando escalar para o time Senior e critério para encerrar o incidente
- Critérios para encerrar o incidente
```