# Modelo

Fiz um teste com o modelo Gemini 2.5 Pro que está localizado no path [resultado_outros_modelos/gemini_2_5_pro.md](resultado_outros_modelos/gemini_2_5_pro.md).
O modelo Claude Sonnet 4.6 gerou um procedimento um pouco mais completo e organizado.

# Justificativa

**Role**

O prompt define claramente a persona que a IA deve assumir. Isso ajuda a IA a entender o tom, o nível de conhecimento técnico e o objetivo da resposta.

- No prompt:
```
# Role
Você é um SRE responsável pelo plantão e por criar runbooks e procedimentos documentados.
```

- Análise: A IA sabe que precisa agir como um Engenheiro de Confiabilidade de Site (SRE), focando em operações, diagnóstico e documentação de procedimentos (runbooks).

**Input**

Esta seção fornece todo o contexto necessário para a IA entender o cenário, as ferramentas disponíveis e o problema a ser resolvido.

- No prompt:
```
# Input
- Ambiente: API Chronos roda no EKS, namespace production, 6 réplicas com HPA configurado (min 4, max 12, CPU target 70%).
- Deploy: via Argo CD a partir do repositório hvt/chronos-api.
- Dependências diretas: Ledger (PostgreSQL) e Reactor (filas SQS).
- Observabilidade: métricas expostas em /metrics, logs centralizados no Beacon, dashboards em Grafana.
- Ferramentas disponíveis para o plantão: kubectl, aws cli, argocd cli.
- Canal de plantão: #oncall-chronos no Slack.
- Time sênior de escalação: @chronos-core (SLA de resposta: 15 minutos em horário comercial, 30 fora).
- Sintoma: Em média 4 vezes por semana, recebimento de alerta "[CRITICAL] High memory usage on Chronos API pods (>85% for 10min)"
```

- Análise: O Input detalha o ambiente técnico (EKS, ArgoCD), as dependências, as ferramentas de observabilidade e o sintoma exato (o alerta de memória). Isso dá à IA todas as "peças do quebra-cabeça" para trabalhar.

**Steps**

Aqui, a tarefa é dividida em uma sequência lógica de ações. Isso guia a IA através do processo de resolução, garantindo que todas as etapas importantes sejam cobertas.

- No prompt:
```
# Steps
1. Confirmar o estado atual dos pods e coletar métricas de utilização de memória
2. Analisar métricas de memória no Prometheus (últimas 1 hora, correlacionar com o deploy)
3. Verificar métricas de utilização da api chronos, se há picos, horários de maior acesso e volumetria
4. Avaliar se é memory leak ou se o sizing está subdimensionado
5. Definir ação imediata de mitigação (ajuste de limits, rollback ou scale horizontal)
6. Documentar critérios de escalação (quando envolver o time de desenvolvimento)
7. Propor ajustes definitivos e critério de validação pós-fix
```

- Análise: Os passos representam um fluxo de trabalho de troubleshooting padrão para um SRE: confirmar, analisar, investigar a causa raiz, mitigar, escalar e propor uma solução definitiva.

**Expectation**

Esta é a parte mais importante para definir a qualidade e o formato da saída. Ela diz à IA como entregar a resposta.

- No prompt:
```
# Expectation
Espero um runbook operacional completo com verificação esperada ao final de cada passo:
- Comandos kubectl prontos para copiar e colar em cada etapa
- Queries PromQL para investigação de memória
- Árvore de decisão: leak vs subdimensionamento → ação correspondente
- Tempo máximo por etapa (total não deve passar de 15 minutos)
- Critérios claros de quando escalar para o time Senior e critério para encerrar o incidente
- Critérios para encerrar o incidente
```

- Análise: A expectativa é muito específica. Ela não pede apenas "um runbook", mas um "runbook operacional completo" com elementos práticos como comandos kubectl prontos, queries PromQL, uma árvore de decisão e critérios claros de escalonamento e encerramento, transformando a resposta em uma ferramenta acionável e não apenas em um texto genérico.