---
nome: Post-mortem Técnico de Incidente de Produção
descricao: Gera um documento de post-mortem técnico a partir de métricas, logs e estado do cluster para subsidiar decisão de rollback ou scaling emergencial.
versao: 1.0.0
tags: [post-mortem, incidente, SRE, rollback, observabilidade]
modelo: Claude Sonnet 4.6
inputs:
  - nome: evento_deploy
    descricao: Dados do deploy anterior, incluindo versão, timestamp de sync do Argo CD e changelog das alterações introduzidas.
  - nome: metricas_beacon
    descricao: Série temporal dos últimos 30 minutos com latência p99 (ms), taxa de requisições por segundo e taxa de erros (%).
  - nome: logs_pod
    descricao: Trecho dos logs do pod afetado contendo erros de esgotamento de connection pool, timeouts de query e estado do circuit breaker.
  - nome: estado_reactor
    descricao: Número de mensagens acumuladas na fila, velocidade de crescimento e consumer lag atual do Reactor.
  - nome: estado_cluster
    descricao: Quantidade de pods em execução, uso médio de CPU e memória, e conexões ativas ao banco de dados (RDS).
---

# Post-mortem Técnico de Incidente de Produção

## Objetivo

Gerar um documento de post-mortem técnico estruturado para auxiliar o CTO na tomada de decisão entre rollback de um deploy recente e scaling emergencial. O prompt instrui a IA a assumir o papel de SRE de plantão, analisar dados de deploy, métricas de latência e erro, logs de pod, estado de fila e estado do cluster, e produzir um relatório com causa raiz, timeline de marcos críticos, árvore de decisão com tempo estimado para cada opção e roteiro detalhado de execução de cada alternativa.

## Quando usar

- Após um incidente de produção com degradação de performance ou aumento de erros causado por um deploy recente.
- Quando é necessário decidir rapidamente, com base em evidências técnicas, entre rollback e mitigação alternativa (scaling, ajuste de configurações).
- Quando o SRE de plantão precisa produzir documentação estruturada para embasar uma decisão executiva em tempo real.
- Para documentar a causa raiz e registrar as ações corretivas e preventivas de um incidente de disponibilidade ou latência.

## Exemplo de uso

Fornecer ao modelo os seguintes dados do incidente:

- **Evento do deploy**: `chronos-api v2.47.0 → v2.48.0`, sincronizado pelo Argo CD em `2026-04-23 18:42:11 UTC`, com changelog incluindo refatoração do cliente do Ledger, bump de psycopg e redução de timeout de 5s para 2s.
- **Métricas do Beacon** (30 min): tabela com timestamps de `13:30` a `14:20 UTC`, mostrando p99 escalando de 420 ms até 8.100 ms e taxa de erros de 0,2% até 11,7%.
- **Logs do pod** `chronos-api-79c4d8b9-xk2jp`: erros de `connection pool exhausted (max=20, waiting=147)`, timeouts de query após 2000 ms e circuit breaker aberto a 87%.
- **Estado do Reactor**: 50.127 mensagens acumuladas, crescendo a ~800/min, consumer lag de 18 minutos.
- **Estado do cluster**: 12/12 pods no HPA máximo, CPU 62%, memória 71%, conexões RDS 240/250.

O modelo produzirá um post-mortem com título, severidade, resumo executivo, timeline, causa raiz, árvore de decisão (rollback vs. scaling emergencial com tempo estimado de cada opção) e roteiro detalhado de execução.

## Limitações conhecidas

- Os dados de entrada são embutidos diretamente no corpo do prompt; não há parametrização via variáveis de template, o que dificulta o reuso direto para outros incidentes sem edição manual.
- A árvore de decisão e os tempos estimados são gerados pela IA e devem ser validados pelo engenheiro de plantão antes da execução.
- O prompt não contempla cenários de incidente sem deploy recente como gatilho (ex.: falha de infraestrutura ou pico orgânico de tráfego).
