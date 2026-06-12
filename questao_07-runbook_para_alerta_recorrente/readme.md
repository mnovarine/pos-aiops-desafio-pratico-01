---
nome: Criar Runbook para Alerta de Alto Uso de Memória
descricao: Gera runbook operacional completo para diagnóstico e mitigação de alerta crítico de alto uso de memória em pods Kubernetes.
versao: 1.0.0
tags: [runbook, SRE, kubernetes, memória, on-call]
modelo: Claude Sonnet 4.6
inputs:
  - nome: ambiente
    descricao: Detalhes do ambiente de execução da API (plataforma, namespace, número de réplicas e configuração do HPA).
  - nome: deploy
    descricao: Ferramenta e repositório utilizados para deploys da aplicação.
  - nome: dependencias
    descricao: Serviços externos dos quais a API depende diretamente (banco de dados, filas, etc.).
  - nome: observabilidade
    descricao: Stack de observabilidade disponível (endpoint de métricas, sistema de logs, dashboards).
  - nome: ferramentas
    descricao: Ferramentas de linha de comando disponíveis durante o plantão.
  - nome: canal_plantao
    descricao: Canal de comunicação utilizado durante incidentes.
  - nome: escalacao
    descricao: Identificação do time sênior de escalação e seus SLAs de resposta.
  - nome: sintoma
    descricao: Descrição do alerta recorrente que motivou a criação do runbook.
---

## Objetivo

Gerar um runbook operacional completo para que o engenheiro de plantão consiga diagnosticar e mitigar o alerta `[CRITICAL] High memory usage on Chronos API pods (>85% for 10min)` em até 15 minutos, com comandos prontos para uso, queries PromQL para análise, árvore de decisão entre memory leak e subdimensionamento, critérios de escalação para o time sênior e critérios de encerramento do incidente.

## Quando usar

- Ao receber o alerta crítico de alto uso de memória nos pods da API Chronos no EKS.
- Ao precisar diagnosticar rapidamente se a causa é memory leak ou subdimensionamento de recursos.
- Ao precisar definir e executar a ação de mitigação imediata durante o plantão.
- Ao preparar documentação prévia para incidentes recorrentes de memória em APIs Kubernetes.

## Limitações conhecidas

- O runbook assume que as ferramentas `kubectl`, `aws cli` e `argocd cli` estão configuradas e autenticadas no ambiente do plantão.
- As queries PromQL e os nomes de métricas (`container_memory_working_set_bytes`, `http_requests_total`, etc.) assumem instrumentação padrão; podem precisar de ajuste caso a API utilize bibliotecas de métricas com nomenclatura diferente.
- O comando de coleta de heap dump varia conforme o runtime da aplicação (Java, Node.js, Go) e deverá ser adaptado conforme a stack real do Chronos.

---
