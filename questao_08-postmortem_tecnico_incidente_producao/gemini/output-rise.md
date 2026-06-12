### **Post-mortem: Degradação Crítica de Performance na `chronos-api`**

*   **Data do Incidente:** 2026-04-24
*   **Duração:** ~45 minutos (de 14:10 UTC até o momento) e em andamento.
*   **Severidade:** 1 (Crítico) - Impacto direto em transações de produção, com perda de funcionalidade e crescente instabilidade.

### **Resumo Executivo**

Desde aproximadamente 14:10 UTC de hoje, a `chronos-api` está em estado de degradação severa, com latência p99 aumentando em mais de 1900% (de 420ms para 8100ms) e a taxa de erros subindo para 11.7%. Logs indicam esgotamento do pool de conexões com o banco de dados (Ledger), timeouts de queries e falhas em cascata, incluindo o novo endpoint `POST /v2/transactions/batch`. O cluster está no limite de conexões do RDS (240/250) e a fila de processamento assíncrono (Reactor) acumula mensagens rapidamente, com um atraso de mais de 18 minutos.

A causa raiz está diretamente ligada ao deploy da versão `v2.48.0`, que introduziu uma refatoração no cliente do Ledger e reduziu o timeout de queries para 2 segundos. Essa mudança, combinada com o aumento da carga, criou um gargalo no acesso ao banco de dados.

A decisão imediata é entre um **rollback** para a v2.47.0, que restauraria a estabilidade em ~15 minutos, ou um **scaling emergencial** do RDS e da aplicação, uma ação mais arriscada e demorada (~45-60 minutos) que pode não resolver o problema fundamental de contenção de conexões. **A recomendação é pelo rollback imediato.**

### **Timeline dos Eventos Críticos**

*   **2026-04-23 18:42 UTC:** Deploy da `chronos-api` v2.48.0 é concluído.
*   **2026-04-24 14:00 UTC:** Métricas começam a mostrar sinais de degradação (latência p99 em 780ms, erros em 0.8%).
*   **2026-04-24 14:10 UTC:** O sistema entra em estado crítico. A latência p99 salta para 2400ms e a taxa de erros para 4.5%.
*   **2026-04-24 14:19 UTC:** Logs confirmam o esgotamento do pool de conexões da aplicação, timeouts de query e a abertura do circuit breaker para o Ledger.
*   **2026-04-24 14:20 UTC:** Latência p99 atinge 8100ms, erros chegam a 11.7%. O HPA da `chronos-api` atinge o máximo de pods (12/12).
*   **2026-04-24 14:25 UTC (agora):** O número de conexões ativas no RDS está em 240/250. A fila do Reactor acumula mais de 50.000 mensagens.

### **Análise da Causa Raiz**

A causa raiz é uma combinação de fatores introduzidos na versão `v2.48.0`:

1.  **Redução do Timeout do Ledger (5s para 2s):** Queries que antes poderiam ser mais lentas sob carga agora falham rapidamente, aumentando a pressão sobre o pool de conexões com novas tentativas e transações presas.
2.  **Refatoração do Cliente do Ledger:** A nova biblioteca de pool de conexões interna parece ser menos eficiente ou estar mal configurada para o padrão de carga atual. O log `connection pool exhausted (max=20, active=20, waiting=147)` mostra que cada pod está tentando usar mais conexões do que as 20 disponíveis, com 147 requisições em espera.
3.  **Novo Endpoint de Batch:** O endpoint `POST /v2/transactions/batch` provavelmente executa múltiplas operações no banco de dados, intensificando a contenção por conexões e exacerbando o problema.

Esses fatores criaram um ciclo vicioso: o aumento da carga leva a queries mais lentas, que atingem o novo timeout de 2s. As falhas e retentativas esgotam o pool de conexões de cada pod, que por sua vez esgota o limite de conexões do RDS, causando uma falha sistêmica.

### **Árvore de Decisão: Rollback vs. Scaling Emergencial**

```mermaid
graph TD
    A[Incidente: Degradação da chronos-api] --> B{Qual a prioridade?};
    B --> C[Restaurar serviço o mais rápido possível];
    B --> D[Tentar manter a nova versão no ar];

    C --> E[**Opção 1: Rollback para v2.47.0**];
    E --> F[Prós: Rápido (~15 min), seguro, causa raiz conhecida e contida];
    E --> G[Contras: Perda temporária das novas features da v2.48.0];
    E --> H[**Roteiro: Rollback**];
    H --> H1[1. Pausar o sync do Argo CD para a app 'chronos-api'];
    H1 --> H2[2. Executar o comando de rollback do Argo CD para a versão estável anterior (v2.47.0)];
    H2 --> H3[3. Monitorar o deploy, a latência, a taxa de erros e o consumo da fila do Reactor];
    H3 --> H4[4. Após estabilização, reativar o sync do Argo CD];

    D --> I[**Opção 2: Scaling Emergencial**];
    I --> J[Prós: Mantém as novas features se funcionar];
    I --> K[Contras: Lento (~45-60 min), arriscado, pode não resolver o problema de contenção na aplicação];
    I --> L[**Roteiro: Scaling**];
    L --> L1[1. Aumentar o `max_connections` no RDS (ex: de 250 para 500). **Requer downtime do DB**];
    L1 --> L2[2. Aplicar um novo `ConfigMap` para a `chronos-api` aumentando o pool por pod (ex: de 20 para 40)];
    L2 --> L3[3. Aumentar o `maxReplicas` no HPA da `chronos-api` (ex: de 12 para 24)];
    L3 --> L4[4. Monitorar se a latência e os erros diminuem. **Alto risco de falha**];

    subgraph Recomendação
        E
    end
```

### **Ações Corretivas (Imediatas)**

| Ação | Responsável Sugerido | Prazo |
| :--- | :--- | :--- |
| **Executar o rollback da `chronos-api` para a v2.47.0** | Plantonista SRE | Imediato |
| Comunicar as áreas de negócio sobre a instabilidade e o rollback | Tech Lead / Product Manager | Imediato |

### **Ações Preventivas (Pós-Incidente)**

| Ação | Responsável Sugerido | Prazo |
| :--- | :--- | :--- |
| Investigar a fundo a ineficiência do novo cliente do Ledger | Time de Desenvolvimento (Chronos) | 3 dias |
| Realizar testes de carga e stress no ambiente de staging com a v2.48.0, focando no pool de conexões | Time de QA / SRE | 5 dias |
| Revisar a política de alteração de timeouts e adicionar métricas de saturação do pool de conexões aos dashboards | Time de SRE | 7 dias |
| Criar um runbook automatizado para rollback de aplicações críticas | Time de SRE | 15 dias |
