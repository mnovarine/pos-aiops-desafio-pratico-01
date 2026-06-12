---
nome: Plano de Redução de Custos Cloud
descricao: Gera um plano priorizado de oportunidades de redução de custos em cloud sem degradar o SLA, com estimativas de economia, esforço e riscos.
versao: 1.0.0
tags: [cloud, custos, AWS, otimização, FinOps]
modelo: Claude Sonnet 4.6
inputs:
  - nome: relatorio_de_custos
    descricao: Relatório atual de custos em formato CSV com os campos servico, categoria, custo_mensal_usd, uso_medio_pct e observacao.
  - nome: meta_reducao_pct
    descricao: Percentual máximo de redução de custo a ser atingido no horizonte definido (ex.: 15% no próximo trimestre).
---

# Plano de Redução de Custos Cloud

## Objetivo

Criar um plano estruturado com as oportunidades de redução de custos em cloud, sem degradação de SLA. O relatório apresenta as oportunidades priorizadas por impacto financeiro, indicando quanto cada uma representa sobre a conta total, o esforço de implementação (baixo, médio, alto) e os riscos ou pré-requisitos envolvidos em cada ação.

## Quando usar

- Quando há necessidade de reduzir custos de cloud em um horizonte de tempo definido (ex.: próximo trimestre).
- Quando se dispõe de um relatório de custos por serviço e se deseja priorizar ações de otimização com base em impacto e risco.
- Quando é necessário comunicar oportunidades de economia de forma estruturada para times técnicos e stakeholders.
- Quando se quer balancear economia financeira com risco operacional e esforço de implementação.

## Exemplo de uso

**Input — `relatorio_de_custos` (CSV):**

```csv
servico,categoria,custo_mensal_usd,uso_medio_pct,observacao
EC2 reservada,compute,4200,72,contrato de 1 ano
EC2 on-demand,compute,8200,45,workloads variaveis
EKS,compute,6700,58,3 clusters
RDS PostgreSQL,databases,8200,62,multi-AZ
ElastiCache Redis,databases,2100,40,cluster de producao
S3 Standard,storage,3100,,5 buckets principais
EBS gp3,storage,1600,68,volumes de producao
CloudWatch Logs,observability,2800,,retencao de 90 dias
CloudWatch Metrics,observability,900,,
Data Transfer Out,network,1900,,trafego entre regioes
NAT Gateway,network,1200,,3 gateways ativos
Lambda,compute,900,30,~12M invocacoes/mes
```

**Input — `meta_reducao_pct`:** `15%` no próximo trimestre.

**Output esperado:** Plano com oportunidades priorizadas por impacto, totalizando a meta definida, com roadmap de implementação trimestral.

## Limitações conhecidas

- A análise depende da qualidade e completude dos dados fornecidos no CSV; campos vazios (como `uso_medio_pct`) limitam a precisão das estimativas de economia.
- As estimativas são baseadas em benchmarks típicos de mercado (ex.: descontos de Reserved Instances e Savings Plans na AWS) e podem variar conforme o ambiente real.
- Não considera comprometimentos contratuais já existentes além dos explicitamente informados no CSV (ex.: contratos de suporte, acordos de parceiro).
- A meta percentual influencia a seleção das oportunidades incluídas no plano — ações de maior esforço ou risco podem ficar no backlog mesmo que representem economia adicional.