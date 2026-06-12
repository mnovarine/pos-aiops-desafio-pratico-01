# Post-mortem Técnico: Degradação da API Chronos e Acúmulo na Fila de Transações

## 1. Análise Estruturada de Causas Prováveis

A análise dos dados aponta para um esgotamento de recursos no banco de dados `Ledger` (RDS), exacerbado por mudanças no deploy da `v2.48.0`. A seguir, as 5 causas mais prováveis, em ordem de probabilidade.

| Probabilidade | Causa Provável | Como Validar (Métrica/Comando AWS) | Ação Corretiva Imediata (Menor Risco Primeiro) |
| :--- | :--- | :--- | :--- |
| **1 (Altíssima)** | **Timeout Reduzido (2s) Inadequado para Carga Atual:** A redução do timeout de 5s para 2s no cliente do Ledger é a causa mais provável. Com o aumento da carga (`req_rate_s`), as queries que antes passavam, agora falham com timeout, mantendo conexões abertas desnecessariamente e levando ao esgotamento do pool. | **1. CloudWatch Metrics (RDS):** Analisar a métrica `DatabaseConnections` no RDS do Ledger. Um aumento abrupto para o limite de 250 confirma a saturação.<br>**2. CloudWatch Logs Insights:** `filter @message like /timeout/` nos logs da `chronos-api` para quantificar a frequência dos timeouts. | **Rollback do Deploy:** Reverter a `chronos-api` para a versão `v2.47.0`. Esta é a ação mais segura e rápida, pois desfaz todas as mudanças recentes, incluindo a redução do timeout, que é o gatilho mais provável. |
| **2 (Alta)** | **Esgotamento do Pool de Conexões (Aplicação):** A nova biblioteca interna de pool de conexões ou sua configuração pode ser menos eficiente que a anterior, esgotando o pool de 20 conexões por pod rapidamente sob carga, o que é evidenciado pelo log `connection pool exhausted`. | **1. Logs da Aplicação:** A mensagem `[ledger-client] connection pool exhausted` já valida esta hipótese.<br>**2. CloudWatch Metrics (ECS/EKS):** Verificar `CPUUtilization` e `MemoryUtilization` dos pods `chronos-api`. Embora não diretamente, o stress pode indicar contenção de recursos na aplicação. | **Rollback do Deploy:** A mudança na biblioteca do pool de conexões faz parte da `v2.48.0`. O rollback para a `v2.47.0` reverteria essa mudança, eliminando a variável. |
| **3 (Média)** | **Sobrecarga do RDS por Queries Ineficientes:** O novo endpoint `POST /v2/transactions/batch` ou a refatoração do cliente do Ledger podem ter introduzido queries mais lentas ou em maior volume, sobrecarregando o RDS e causando lentidão generalizada. | **1. RDS Performance Insights:** Ativar e analisar o Performance Insights no RDS do Ledger para identificar as queries com maior `DB Load` e `Wait Events` (ex: `CPU`, `IO:XactSync`).<br>**2. `EXPLAIN ANALYZE`:** Executar um `EXPLAIN ANALYZE` nas novas queries suspeitas diretamente no banco de dados para avaliar seu plano de execução. | **Scaling Emergencial (Vertical):** Aumentar a instância do RDS para uma classe com mais CPU/RAM (ex: de `db.t3.medium` para `db.t3.large`). Esta é uma ação de risco moderado que pode aliviar a pressão no banco enquanto a causa raiz é investigada. |
| **4 (Baixa)** | **Bug na Nova Versão do `psycopg` (3.2.0):** A atualização da biblioteca `psycopg` de `3.1.18` para `3.2.0` pode ter introduzido um bug sutil de gerenciamento de conexão ou um vazamento de recursos que se manifesta sob alta carga. | **1. GitHub Issues:** Pesquisar no repositório do `psycopg` por issues abertas relacionadas a `connection leak`, `timeout` ou `pool` na versão `3.2.0`.<br>**2. Teste em Staging:** Isolar a mudança do `psycopg` em um ambiente de staging com um teste de carga para tentar reproduzir o problema. | **Rollback do Deploy:** A atualização do `psycopg` é parte do deploy. O rollback para a `v2.47.0` mitigaria o problema imediatamente. |
| **5 (Muito Baixa)** | **Limite de Conexões do RDS Insuficiente para a Carga:** O limite máximo de 250 conexões no RDS pode ser inerentemente baixo para o volume de tráfego atual, mesmo com uma aplicação saudável. O crescimento do negócio pode ter tornado a configuração antiga obsoleta. | **1. CloudWatch Metrics (RDS):** Analisar a tendência histórica da métrica `DatabaseConnections` em um período mais longo (ex: 3 meses) para observar se o uso médio tem se aproximado do limite.<br>**2. Análise de Carga:** Comparar o `req_rate_s` atual com o de semanas anteriores para quantificar o crescimento da carga. | **Scaling Emergencial (Configuração):** Aumentar o parâmetro `max_connections` no Parameter Group do RDS e, em seguida, aumentar o pool de conexões na aplicação. Esta é uma ação de alto risco, pois pode levar a contenção de CPU/memória no RDS se a instância não for dimensionada adequadamente. |

---

## 2. Documento de Post-mortem do Incidente

### **Título do Incidente:** Degradação Crítica da `chronos-api` e Acúmulo na Fila de Transações

- **Data e Hora:** 2026-04-24, a partir das 14:10 UTC
- **Duração:** Em andamento (Iniciado há ~20 minutos no momento da análise)
- **Severidade:** SEV-1 (Crítico - Impacto direto em transações de produção e clientes)
- **Serviços Afetados:** `chronos-api`, `Reactor` (fila `chronos-transactions`), `Ledger` (RDS)

### **Resumo Executivo**

Às 14:10 UTC de 2026-04-24, a API `chronos-api` começou a apresentar um aumento drástico na latência (de ~500ms para >8000ms) e na taxa de erros (>11%). A causa raiz imediata foi o esgotamento de conexões com o banco de dados Ledger (RDS), que atingiu seu limite de 250 conexões. Este esgotamento foi desencadeado por uma combinação de aumento de carga e, principalmente, pela redução do timeout de conexão de 5s para 2s no deploy da `v2.48.0`, realizado no dia anterior. A ação de contenção imediata recomendada é o **rollback para a versão `v2.47.0`**, por ser a solução de menor risco e com maior probabilidade de restaurar a estabilidade do serviço.

### **Timeline do Incidente (UTC)**

- **2026-04-23 18:42:** Deploy da `chronos-api v2.48.0` é concluído com sucesso.
- **2026-04-24 13:30 - 14:00:** Métricas de latência e erro começam a se degradar lentamente, mas ainda dentro de limites operacionais.
- **2026-04-24 14:10:** Alerta de latência (p99 > 2s) é disparado. Latência atinge 2400ms e taxa de erro sobe para 4.5%.
- **2026-04-24 14:15:** Incidente é declarado (SEV-1). Latência sobe para 5200ms, erros para 8.2%. A fila do Reactor começa a acumular mensagens rapidamente.
- **2026-04-24 14:19:** Logs da `chronos-api` mostram `connection pool exhausted`, `query timeout` e o circuit breaker para o `ledger-client` é aberto.
- **2026-04-24 14:20:** Latência atinge 8100ms, erros chegam a 11.7%. Conexões no RDS chegam a 240/250.
- **2026-04-24 14:25:** Início da análise de causa raiz e elaboração deste post-mortem.

### **Análise de Causa Raiz Detalhada**

A causa raiz do incidente é uma falha em cascata iniciada pela **redução do timeout do cliente do Ledger de 5s para 2s** na versão `v2.48.0`.

1.  **Gatilho:** O aumento natural da carga de requisições (`req_rate_s` subindo de 1200 para 2650) fez com que algumas queries ao banco de dados Ledger, que antes eram concluídas em ~3-4s, começassem a falhar devido ao novo timeout de 2s.
2.  **Saturação do Pool:** As falhas de timeout não liberavam as conexões do pool da aplicação (`max=20` por pod) de forma eficiente. Com o aumento das requisições em espera (`waiting=147`), o pool de cada um dos 12 pods se esgotou.
3.  **Esgotamento de Conexões no RDS:** Com 12 pods, cada um tentando manter seu pool de 20 conexões, a demanda total teórica (240 conexões) saturou o limite de 250 conexões do RDS.
4.  **Falha em Cascata:** Com o RDS e os pools de conexão da aplicação saturados, novas requisições falhavam imediatamente (`context deadline exceeded`), o circuit breaker abriu, e a `chronos-api` parou de processar transações, causando o acúmulo massivo de mensagens na fila do Reactor.

As outras mudanças no deploy (novo endpoint, `psycopg 3.2.0`) são fatores de risco, mas a correlação direta entre o log de `query timeout after 2000ms` e a degradação torna a redução do timeout o principal culpado.

### **Árvore de Decisão: Rollback vs. Scaling Emergencial**

-   **Opção 1: Rollback para `v2.47.0` (Ação Recomendada)**
    -   **Descrição:** Reverter o deploy da `chronos-api` para a versão estável anterior.
    -   **Tempo Estimado:** **~15-20 minutos** (tempo de pipeline do Argo CD/CI/CD para reverter e estabilizar).
    -   **Prós:**
        -   Ação de menor risco.
        -   Resolve a causa raiz mais provável (timeout) e outros possíveis fatores da `v2.48.0`.
        -   Restaura o sistema a um estado conhecido e estável.
    -   **Contras:**
        -   Perde-se as novas funcionalidades da `v2.48.0` temporariamente.
    -   **Roteiro de Execução:**
        1.  **Comunicação:** Notificar no canal de incidentes que o rollback será iniciado. `(Responsável: Plantonista)`
        2.  **Argo CD:** Acessar a UI do Argo CD, encontrar a aplicação `chronos-api` e clicar em `History and Rollback`. Selecionar a penúltima sincronização bem-sucedida (com a `v2.47.0`) e iniciar o rollback.
        3.  **Monitoramento:** Acompanhar os pods sendo substituídos (`kubectl get pods -n chronos -w`).
        4.  **Validação:** Observar as métricas no Beacon: `p99_latency_ms` e `err_rate_pct` devem começar a cair drasticamente em 5-10 minutos. Acompanhar a métrica `DatabaseConnections` no CloudWatch do RDS, que deve cair para níveis normais.
        5.  **Fila do Reactor:** Monitorar o `consumer lag` da fila `chronos-transactions`, que deve começar a diminuir à medida que a API se estabiliza.

-   **Opção 2: Scaling Emergencial (Ação Não Recomendada como primeira escolha)**
    -   **Descrição:** Aumentar verticalmente a instância do RDS e aumentar o limite de `max_connections`.
    -   **Tempo Estimado:** **~30-45 minutos** (tempo de modificação da instância RDS + reinicialização + ajustes na aplicação).
    -   **Prós:**
        -   Pode resolver o problema se a causa for puramente sobrecarga.
        -   Mantém as novas funcionalidades no ar.
    -   **Contras:**
        -   Ação de alto risco; não trata a causa raiz (timeouts) e pode apenas "empurrar" o gargalo para outro lugar.
        -   Modificar uma instância RDS em produção é uma operação arriscada e pode causar uma indisponibilidade ainda maior se algo der errado.
        -   Não há garantia de que resolverá o problema.
    -   **Roteiro de Execução (se o rollback falhar):**
        1.  **Snapshot do RDS:** (Opcional, mas recomendado) Tirar um snapshot manual do RDS como backup.
        2.  **Modificar Instância:** Na AWS Console, ir para o RDS, selecionar a instância do Ledger, clicar em `Modify`. Alterar a `DB instance class` para uma maior (ex: `db.t3.large`). Aplicar imediatamente (pode haver downtime).
        3.  **Aumentar `max_connections`:** Modificar o Parameter Group associado, alterar `max_connections` para um valor maior (ex: 500) e aplicar.
        4.  **Atualizar Pool da Aplicação:** Fazer um deploy de uma nova versão da `chronos-api` (`v2.48.1`) com o tamanho do pool de conexões aumentado na configuração da aplicação.
        5.  **Monitoramento e Validação:** Seguir os mesmos passos de validação do rollback.

### **Ações Corretivas (Pós-Incidente)**

| Ação | Responsável Sugerido | Prazo |
| :--- | :--- | :--- |
| Investigar a causa do aumento da latência das queries no Ledger com a carga atual. | Time de Dados/DBA | 3 dias úteis |
| Realizar teste de carga em staging para a `v2.48.0`, focando em simular a carga de produção e validar o comportamento do novo timeout e da biblioteca de conexão. | Time de SRE/QA | 5 dias úteis |
| Revisar a política de configuração de timeouts, garantindo que sejam baseados em dados de performance (ex: p99 da latência da query) e não em valores arbitrários. | Time de Arquitetura/Chronos | 1 semana |

### **Ações Preventivas**

| Ação | Responsável Sugerido | Prazo |
| :--- | :--- | :--- |
| Implementar alertas automáticos para a taxa de crescimento do `consumer lag` em filas críticas. | Time de SRE/Observability | 2 semanas |
| Adicionar a métrica de conexões ativas do pool da aplicação ao dashboard principal do Beacon para `chronos-api`. | Time de Chronos | 2 semanas |
| Criar um runbook automatizado ou semi-automatizado para executar o rollback de aplicações críticas com um único comando/bot. | Time de SRE/Platform | 1 mês |
| Avaliar o uso de um proxy de banco de dados como o RDS Proxy para gerenciar pools de conexão de forma mais eficiente e centralizada. | Time de Arquitetura/DBA | 1 mês |
