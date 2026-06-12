# Post-mortem: Degradação Crítica da API Chronos (v2.48.0)

- **Data:** 2026-04-24
- **Duração:** Em andamento, desde ~14:10 UTC
- **Severidade:** SEV-1 (Crítico - Impacto massivo na funcionalidade principal, perda de transações)

## Resumo Executivo

A partir das 14:10 UTC de 24/04/2026, a `chronos-api` começou a apresentar uma degradação severa, com latência p99 subindo para mais de 8 segundos e a taxa de erros ultrapassando 11%. A causa raiz está diretamente ligada ao deploy da versão `v2.48.0` de ontem (23/04). A combinação de um novo endpoint de batch (`/v2/transactions/batch`), a refatoração do pool de conexões com o banco de dados (Ledger) e a redução do timeout de 5s para 2s resultou no esgotamento total das conexões disponíveis no RDS (240/250) e no pool de conexões da aplicação. Isso gerou um efeito cascata, abrindo o circuit breaker, acumulando mensagens na fila do Reactor e impactando a capacidade de processamento de transações.

A decisão imediata a ser tomada é entre um **rollback** para a versão `v2.47.0` para restaurar a estabilidade ou um **scaling emergencial** do RDS e dos pools de conexão para tentar absorver a nova carga. **A recomendação é o rollback**, por ser a ação mais rápida, segura e com maior probabilidade de sucesso para mitigar o impacto imediatamente.

## Timeline do Incidente (UTC)

- **23/04 18:42:** Deploy da `chronos-api` v2.48.0 é concluído.
- **24/04 13:30 - 14:00:** Métricas de latência e erro começam a se elevar gradualmente, mas ainda dentro de limites operacionais.
- **24/04 14:10:** Aumento abrupto da latência p99 para 2.4s e taxa de erros para 4.5%. O sistema entra em estado de alerta.
- **24/04 14:15:** Latência salta para 5.2s e erros para 8.2%. O HPA da `chronos-api` atinge o máximo de 12 pods.
- **24/04 14:19:** Logs confirmam esgotamento do pool de conexões, timeouts de query e abertura do circuit breaker.
- **24/04 14:20:** Latência atinge 8.1s, taxa de erros chega a 11.7%. Conexões no RDS chegam a 240/250. Fila do Reactor com lag de 18 minutos e crescendo.
- **24/04 14:25:** Início da análise para decisão de mitigação (Rollback vs. Scaling).

## Análise da Causa Raiz

A degradação foi causada por uma "tempestade perfeita" de mudanças introduzidas na versão `v2.48.0`:

1.  **Redução do Timeout (5s -> 2s):** A causa mais provável. Queries que antes passavam (mesmo que lentas) agora falham, mas não antes de reter uma conexão do pool por 2 segundos. Isso aumenta o tempo médio de ocupação de conexão sob carga.
2.  **Novo Endpoint de Batch (`/v2/transactions/batch`):** Este endpoint provavelmente executa múltiplas operações no banco de dados, intensificando o uso de conexões e colocando mais pressão sobre o pool, que já estava fragilizado pela redução do timeout.
3.  **Refatoração do Cliente do Ledger:** A nova biblioteca interna de pool de conexões pode ter um comportamento diferente sob alta carga ou uma configuração padrão inadequada (ex: `max=20` por pod), que se mostrou insuficiente para o novo padrão de uso.
4.  **Bump do `psycopg`:** Menos provável, mas uma nova versão pode ter introduzido regressões ou mudanças de comportamento não previstas na gestão de conexões.

Esses fatores combinados levaram ao esgotamento do pool de conexões em cada pod, e consequentemente, ao esgotamento do limite de conexões do RDS, paralisando a capacidade da API de se comunicar com o banco de dados.

## Árvore de Decisão: Ações Imediatas

### Opção 1: Rollback para v2.47.0 (Recomendado)

- **Descrição:** Reverter o deploy da `chronos-api` para a versão estável anterior (`v2.47.0`) via Argo CD.
- **Tempo Estimado:** **5-10 minutos**.
- **Prós:**
    - **Rápido:** Ação mais veloz para restaurar o serviço.
    - **Seguro:** Retorna o sistema a um estado conhecido e estável.
    - **Eficaz:** Remove todos os vetores de problema introduzidos na v2.48.0 de uma só vez.
- **Contras:**
    - Perda temporária das novas funcionalidades (endpoint de batch).
- **Roteiro de Execução:**
    1.  **Comunicar:** Notificar as equipes no canal de incidentes sobre o início do rollback.
    2.  **Executar Rollback no Argo CD:**
        - Acessar a aplicação `chronos-api` no Argo CD.
        - Clicar em "History and Rollback".
        - Selecionar a versão `v2.47.0` (deploy de 23/04 antes das 18:42 UTC).
        - Iniciar o rollback.
    3.  **Monitorar:** Acompanhar o deploy dos novos pods na versão `v2.47.0`.
    4.  **Validar:** Observar as métricas (latência, erros, conexões RDS, fila do Reactor) para confirmar a normalização do sistema. A expectativa é uma queda drástica em 5 minutos.

### Opção 2: Scaling Emergencial

- **Descrição:** Aumentar os limites de conexão no RDS e o tamanho do pool de conexões na aplicação.
- **Tempo Estimado:** **20-40 minutos** (pode variar dependendo da necessidade de reinicialização do RDS).
- **Prós:**
    - Mantém as novas funcionalidades no ar.
- **Contras:**
    - **Arriscado:** Pode não resolver o problema se a causa for ineficiência de queries ou um bug na nova biblioteca, apenas adiando o colapso.
    - **Lento:** Aumentar limites no RDS pode exigir tempo ou até uma janela de manutenção. Alterar a configuração da aplicação exige um novo deploy.
    - **Custo:** Aumenta os custos de infraestrutura de forma reativa.
- **Roteiro de Execução:**
    1.  **Comunicar:** Notificar as equipes sobre o plano de scaling.
    2.  **Scaling do RDS:**
        - Acessar o console da AWS -> RDS.
        - Modificar a instância do Ledger para um tipo com maior capacidade de conexões (ex: de `db.t3.medium` para `db.t3.large`).
        - **Atenção:** Verificar se a mudança pode ser aplicada imediatamente ou se requer uma janela de manutenção.
    3.  **Aumentar Pool na Aplicação:**
        - Criar um hotfix branch a partir da `v2.48.0`.
        - Alterar a configuração do pool de conexões (ex: `max=50`).
        - Gerar uma nova imagem `v2.48.1`.
    4.  **Deploy:** Fazer o deploy da `v2.48.1` via Argo CD.
    5.  **Monitorar e Validar:** Acompanhar as métricas para ver se o sistema estabiliza com os novos limites.

## Ações Corretivas (Pós-Incidente)

| Ação                                                                                             | Responsável Sugerido | Prazo      |
| ------------------------------------------------------------------------------------------------- | -------------------- | ---------- |
| **1.** Conduzir análise de causa raiz detalhada do código da `v2.48.0` para identificar o bug exato. | Squad Chronos        | 25/04/2026 |
| **2.** Corrigir o bug (seja no pool, na query do batch ou no timeout) e validar em ambiente de staging. | Squad Chronos        | 26/04/2026 |
| **3.** Processar manualmente as mensagens acumuladas na fila `chronos-transactions` após a estabilização. | SRE / Plantonista    | 24/04/2026 |

## Ações Preventivas

| Ação                                                                                                                            | Responsável Sugerido | Prazo      |
| ------------------------------------------------------------------------------------------------------------------------------- | -------------------- | ---------- |
| **1.** Implementar testes de carga em ambiente de staging que simulem o uso dos novos endpoints antes do deploy em produção.      | QA / Squad Chronos   | 01/05/2026 |
| **2.** Criar dashboards específicos para monitorar a saúde do pool de conexões (conexões ativas, em espera, livres) por pod.     | SRE / Observability  | 15/05/2026 |
| **3.** Revisar e padronizar a configuração do pool de conexões para todas as bibliotecas internas, com valores baseados em testes. | SRE / Arquitetura    | 20/05/2026 |
| **4.** Adicionar ao playbook de deploy um passo de "Canary Release" para mudanças sensíveis (como esta), liberando para uma pequena porcentagem de pods antes do rollout completo. | SRE / DevOps         | 01/06/2026 |
