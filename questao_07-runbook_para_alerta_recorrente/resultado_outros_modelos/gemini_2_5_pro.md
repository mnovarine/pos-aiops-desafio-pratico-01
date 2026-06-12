# Runbook: Alerta Crítico de Alto Uso de Memória na API Chronos

**ALERTA:** `[CRITICAL] High memory usage on Chronos API pods (>85% for 10min)`

Este runbook detalha os passos para diagnosticar e mitigar o alerta de alto uso de memória nos pods da aplicação Chronos API.

**Tempo Estimado para Resolução:** 15 minutos.

---

### Passo 1: Verificação Inicial e Coleta de Métricas (Tempo: 2 minutos)

O objetivo é confirmar o estado atual dos pods e obter uma visão rápida do consumo de memória.

**Ação:** Execute os seguintes comandos para listar os pods, verificar seus status e ver o consumo de recursos em tempo real.

```bash
# 1. Listar todos os pods da Chronos API no namespace 'production'
kubectl -n production get pods -l app=chronos-api

# 2. Verificar o consumo de CPU e memória dos pods em tempo real
kubectl -n production top pods -l app=chronos-api
```

**Verificação Esperada:**
- Todos os pods devem estar no estado `Running`.
- O comando `top pods` deve mostrar um ou mais pods com uso de memória (`MEMORY(bytes)`) próximo ou acima do limite que disparou o alerta (85% do `request/limit`). Anote os nomes dos pods com maior consumo.

---

### Passo 2: Análise de Métricas no Prometheus/Grafana (Tempo: 5 minutos)

Investigar o histórico de consumo de memória para identificar padrões e correlações.

**Ação:** Utilize as queries PromQL abaixo no Grafana ou diretamente no Prometheus para analisar o comportamento da memória.

**Query 1: Consumo médio de memória (última 1 hora)**
```promql
// Consumo médio de memória (working set bytes) dos pods da Chronos API
avg(container_memory_working_set_bytes{namespace="production", pod=~"chronos-api-.*", container="chronos-api"}) by (pod)
```

**Query 2: Correlação com Deploys (via Argo CD)**
Verifique no canal do Argo CD ou na UI se houve algum deploy recente que coincida com o início do aumento de memória.

**Verificação Esperada:**
- O gráfico de memória deve mostrar uma tendência de crescimento:
    - **Crescimento Súbito:** Um salto abrupto no uso de memória pode indicar um deploy com nova funcionalidade ou uma alteração que impactou o consumo.
    - **Crescimento Lento e Contínuo (dente de serra):** É um forte indicativo de *memory leak*. O consumo sobe gradualmente até o pod ser reiniciado pelo OOMKiller ou por um novo deploy.

---

### Passo 3: Análise de Métricas de Utilização da API (Tempo: 3 minutos)

Verificar se o alto consumo de memória é uma resposta a um aumento legítimo no tráfego ou carga da aplicação.

**Ação:** Analise os dashboards da Chronos API no Grafana, focando nas seguintes métricas:
- **Request Rate (RPS):** Volume de requisições por segundo.
- **Request Latency:** Latência das requisições.
- **SQS Queue Size (Reactor):** Tamanho da fila de entrada do Reactor.

**Verificação Esperada:**
- **Cenário 1 (Pico de Tráfego):** Os gráficos mostram um pico de requisições ou um aumento no tamanho da fila SQS que coincide com o aumento do consumo de memória.
- **Cenário 2 (Sem Pico de Tráfego):** O tráfego da API permanece estável, sem correlação com o aumento da memória.

---

### Passo 4: Árvore de Decisão - Memory Leak vs. Subdimensionamento (Tempo: 1 minuto)

Com base nas informações coletadas, decida a causa provável.

- **É Memory Leak se:**
    - O consumo de memória cresce de forma lenta e contínua, mesmo com tráfego estável (Passo 2 e 3).
    - O padrão de "dente de serra" é visível no gráfico de memória ao longo de horas ou dias.

- **É Subdimensionamento se:**
    - O consumo de memória aumenta drasticamente em resposta a picos de tráfego (Passo 3).
    - A memória se estabiliza ou diminui quando o pico de tráfego passa.
    - O problema ocorre consistentemente nos mesmos horários (ex: horários de pico de uso do sistema).

---

### Passo 5: Ação de Mitigação Imediata (Tempo: 2 minutos)

Aplique a mitigação correspondente à causa identificada.

**Opção A: Se for Memory Leak**
A ação imediata é reiniciar os pods mais afetados para liberar a memória e ganhar tempo para uma correção definitiva.

```bash
# Reinicie os pods com maior consumo de memória (substitua <pod-name>)
kubectl -n production delete pod <pod-name-1> <pod-name-2>
```
**Atenção:** O Argo CD irá recriar os pods automaticamente. Reinicie os pods de forma faseada para não impactar a disponibilidade do serviço.

**Opção B: Se for Subdimensionamento**
Aumente temporariamente o número máximo de réplicas no HPA para absorver a carga.

```bash
# Aumenta o número máximo de réplicas para 16 (valor sugerido, ajuste se necessário)
kubectl -n production patch hpa chronos-api --patch '{"spec":{"maxReplicas": 16}}'
```

**Verificação Esperada:**
- **Opção A:** Os novos pods devem iniciar com baixo consumo de memória. O alerta deve ser resolvido em poucos minutos.
- **Opção B:** O HPA deve escalar horizontalmente, criando novas réplicas. O consumo médio de memória por pod deve diminuir e se estabilizar abaixo do limiar de alerta.

---

### Passo 6: Critérios de Escalação

**Quando escalar para o time `@chronos-core`:**
- **IMEDIATAMENTE se:** A mitigação aplicada no Passo 5 não resolver o alerta em 5 minutos.
- **IMEDIATAMENTE se:** O incidente estiver causando impacto visível ao cliente (erros 5xx, alta latência) que não foi resolvido com a mitigação.
- **APÓS MITIGAÇÃO (via Slack/Jira) se:** Foi identificado um **memory leak**. Crie um ticket de alta prioridade com as evidências coletadas (gráficos, logs, correlações) e notifique o time no canal `#oncall-chronos`.

**Template de Comunicação para Escalação:**
> **INCIDENTE:** Alto uso de memória na Chronos API.
> **Status:** Mitigado com [reinício de pods | aumento do HPA].
> **Diagnóstico Preliminar:** Suspeita de [Memory Leak | Subdimensionamento devido a pico de tráfego].
> **Evidências:** [Link para o dashboard do Grafana com o período do incidente].
> **Ação:** Peço ao time de desenvolvimento para investigar a causa raiz.

---

### Passo 7: Proposta de Ajustes Definitivos e Encerramento

**Critérios para Encerrar o Incidente:**
- O alerta `[CRITICAL] High memory usage` foi resolvido e o sistema está estável.
- A comunicação de escalação (se necessária) foi enviada ao time de desenvolvimento.
- O incidente foi documentado internamente (postmortem, se a cultura exigir).

**Propostas de Ajustes Definitivos (a serem discutidas com `@chronos-core`):**

- **Se for Memory Leak:**
    - **Ação:** O time de desenvolvimento deve realizar uma análise de perfil de memória (memory profiling) no ambiente de staging para identificar e corrigir o vazamento no código.
    - **Validação Pós-Fix:** Após o deploy da correção, monitorar o gráfico de consumo de memória por 48 horas. O padrão de crescimento contínuo ("dente de serra") não deve mais ocorrer.

- **Se for Subdimensionamento:**
    - **Ação:** Realizar um estudo de capacity planning. Avaliar o aumento permanente dos `requests/limits` de memória no `deployment.yaml` e/ou ajustar os `minReplicas` do HPA para melhor absorver a carga recorrente.
    - **Validação Pós-Fix:** Após o ajuste, monitorar a aplicação durante os horários de pico por uma semana. O HPA deve escalar suavemente e o uso de memória por pod deve permanecer dentro de uma faixa saudável (<80%), sem disparar alertas.
