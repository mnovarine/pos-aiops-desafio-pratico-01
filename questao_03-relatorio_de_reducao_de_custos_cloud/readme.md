## Prompt

```
# Task
Crie um plano com as oportunidades de redução de custo de cloud sem degradar o SLA.

# Action
O relatório precisa trazer as oportunidades de economia priorizadas por impacto, quanto cada uma representa em percentual da conta total, o esforço de implementação (baixo, médio, alto) e os riscos ou pré-requisitos envolvidos em cada uma.

Abaixo o relatório atual de custos, em formato CSV:

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

# Goal
Objetivo: listar as oportunidades de redução de custo em até 15% para o próximo trimestre.
```

## Modelo

Claude Sonnet 4.6

## Output

Relatório gerado com base nos dados de custo fornecidos. A análise cobre todos os 12 serviços listados, totaliza a conta mensal, calcula o percentual de representatividade de cada oportunidade sobre o total e estima economias conservadoras sem alteração de SLA.

---

# Plano de Redução de Custos Cloud — Próximo Trimestre

## Resumo Executivo

| Item | Valor |
|---|---|
| **Conta total mensal** | $41.800 |
| **Meta de redução (15%)** | $6.270/mês |
| **Economia total identificada** | $8.370/mês (~20%) |
| **Economia do plano recomendado** | $6.290/mês (~15,1%) |

> As oportunidades abaixo foram selecionadas para atingir a meta de 15% no trimestre sem degradação de SLA, priorizando esforço baixo e risco controlado.

---

## Composição Atual da Conta

| Serviço | Categoria | Custo Mensal | % da Conta | Uso Médio |
|---|---|---|---|---|
| EC2 on-demand | compute | $8.200 | 19,6% | 45% |
| RDS PostgreSQL | databases | $8.200 | 19,6% | 62% |
| EKS | compute | $6.700 | 16,0% | 58% |
| EC2 reservada | compute | $4.200 | 10,0% | 72% |
| S3 Standard | storage | $3.100 | 7,4% | — |
| CloudWatch Logs | observability | $2.800 | 6,7% | — |
| ElastiCache Redis | databases | $2.100 | 5,0% | 40% |
| Data Transfer Out | network | $1.900 | 4,5% | — |
| EBS gp3 | storage | $1.600 | 3,8% | 68% |
| NAT Gateway | network | $1.200 | 2,9% | — |
| CloudWatch Metrics | observability | $900 | 2,2% | — |
| Lambda | compute | $900 | 2,2% | 30% |
| **Total** | | **$41.800** | **100%** | |

---

## Oportunidades de Redução — Priorizadas por Impacto

### 1. EC2 on-demand → Compute Savings Plans

| Atributo | Detalhe |
|---|---|
| **Serviço** | EC2 on-demand |
| **Custo atual** | $8.200/mês |
| **% da conta** | 19,6% |
| **Economia estimada** | $2.460/mês (30%) |
| **% de economia sobre conta total** | 5,9% |
| **Esforço** | Baixo |
| **Risco** | Baixo |

**Ação:** Contratar Compute Savings Plans de 1 ano (no-upfront) cobrindo ~60% do baseline de consumo. O modelo Compute Savings Plan é flexível entre famílias de instâncias, regiões e até Fargate/Lambda — sem lock-in de instância específica.

**Pré-requisitos:**
- Analisar pelo menos 30 dias de histórico de uso via AWS Cost Explorer.
- Confirmar que workloads variáveis possuem um baseline previsível (mesmo que 45% médio, há um piso constante elegível para cobertura).

**Riscos:** Mínimo. Savings Plans não forçam uso — qualquer consumo abaixo do comprometido simplesmente é cobrado à tarifa comprometida. Não há impacto em SLA.

---

### 2. RDS PostgreSQL → Reserved Instances (1 ano)

| Atributo | Detalhe |
|---|---|
| **Serviço** | RDS PostgreSQL |
| **Custo atual** | $8.200/mês |
| **% da conta** | 19,6% |
| **Economia estimada** | $1.230/mês (15%) |
| **% de economia sobre conta total** | 2,9% |
| **Esforço** | Baixo |
| **Risco** | Baixo |

**Ação:** Converter instâncias RDS para Reserved Instances de 1 ano (no-upfront ou partial-upfront). Para instâncias multi-AZ estáveis, o desconto conservador é de 15–30%.

**Pré-requisitos:**
- Confirmar que as instâncias atuais (tipo e tamanho) permanecerão estáveis por pelo menos 12 meses.
- Validar com o time de banco de dados se há plano de upgrade de instância no horizonte — Reserved Instance não é transferível entre tipos.

**Riscos:** Baixo. A infra multi-AZ permanece idêntica; apenas o modelo de cobrança muda. Se houver upgrade de instância antes do vencimento, o RI pode ser vendido no AWS Marketplace.

---

### 3. CloudWatch Logs → Redução de retenção + exportação para S3

| Atributo | Detalhe |
|---|---|
| **Serviço** | CloudWatch Logs |
| **Custo atual** | $2.800/mês |
| **% da conta** | 6,7% |
| **Economia estimada** | $1.120/mês (40%) |
| **% de economia sobre conta total** | 2,7% |
| **Esforço** | Baixo |
| **Risco** | Baixo |

**Ação:**
1. Reduzir a retenção padrão de 90 para 30 dias nos Log Groups de aplicação.
2. Criar um job de exportação automática (Lambda + EventBridge) para mover logs com mais de 30 dias para S3 Standard-IA ou S3 Glacier Instant Retrieval.
3. Armazenamento CloudWatch: ~$0,03/GB/mês → S3 Glacier: ~$0,004/GB/mês (redução de ~87% no custo de retenção de logs antigos).

**Pré-requisitos:**
- Mapear quais Log Groups possuem requisitos de compliance ou auditoria que exijam retenção maior (ex.: logs de acesso podem ter exigência regulatória de 1 ano).
- Validar se há queries recorrentes sobre logs com mais de 30 dias via CloudWatch Insights — se sim, manter no CW ou usar Athena sobre S3.

**Riscos:** Baixo. Logs permanecem acessíveis no S3; apenas o canal de consulta muda de CloudWatch Insights para Athena/S3 Select para dados históricos.

---

### 4. S3 Standard → Intelligent-Tiering + Lifecycle Policies

| Atributo | Detalhe |
|---|---|
| **Serviço** | S3 Standard |
| **Custo atual** | $3.100/mês |
| **% da conta** | 7,4% |
| **Economia estimada** | $775/mês (25%) |
| **% de economia sobre conta total** | 1,9% |
| **Esforço** | Médio |
| **Risco** | Baixo |

**Ação:**
1. Habilitar S3 Intelligent-Tiering para buckets com padrão de acesso variável (move automaticamente objetos entre Frequent/Infrequent/Archive Access — sem taxa de recuperação para as duas primeiras camadas).
2. Criar Lifecycle Policies para objetos com padrão previsível: mover para S3-IA após 30 dias e Glacier Instant Retrieval após 90 dias.
3. Ativar S3 Storage Lens para identificar objetos não acessados nos últimos 90 dias em cada bucket.

**Pré-requisitos:**
- Inventariar os 5 buckets: tipo de dado, frequência de acesso, requisitos de latência de recuperação.
- Intelligent-Tiering tem custo de monitoramento por objeto (~$0,0025/1.000 objetos) — não recomendado para objetos muito pequenos (< 128 KB).

**Riscos:** Baixo. Objetos em S3-IA têm latência idêntica ao Standard; Glacier Instant tem latência de milissegundos. Sem impacto em disponibilidade.

---

### 5. ElastiCache Redis → Right-sizing + Reserved Nodes

| Atributo | Detalhe |
|---|---|
| **Serviço** | ElastiCache Redis |
| **Custo atual** | $2.100/mês |
| **% da conta** | 5,0% |
| **Economia estimada** | $525/mês (25%) |
| **% de economia sobre conta total** | 1,3% |
| **Esforço** | Médio |
| **Risco** | Médio |

**Ação:**
1. Analisar métricas de `CurrConnections`, `DatabaseMemoryUsagePercentage` e `EngineCPUUtilization` dos últimos 30 dias.
2. Com 40% de uso médio, avaliar redução do tipo de instância (ex.: de `r6g.xlarge` para `r6g.large`) ou redução do número de réplicas de leitura.
3. Após right-sizing, contratar Reserved Nodes de 1 ano para as instâncias estabilizadas.

**Pré-requisitos:**
- Identificar picos de uso (Black Friday, batch jobs) — o right-sizing deve considerar o P95, não apenas a média.
- Validar se a aplicação usa todas as réplicas de leitura ativas ou se alguma está ociosa.
- Testar em ambiente de staging antes de aplicar em produção.

**Riscos:** Médio. Redução de instância pode impactar latência em picos se o dimensionamento for agressivo. Mitigação: aplicar redução incremental (um step de instância por vez) com janela de manutenção monitorada.

---

### 6. Lambda → Otimização de memória e duração

| Atributo | Detalhe |
|---|---|
| **Serviço** | Lambda |
| **Custo atual** | $900/mês |
| **% da conta** | 2,2% |
| **Economia estimada** | $180/mês (20%) |
| **% de economia sobre conta total** | 0,4% |
| **Esforço** | Baixo |
| **Risco** | Baixo |

**Ação:**
1. Usar AWS Lambda Power Tuning (open-source) para encontrar a configuração ótima de memória por função — menor custo nem sempre é a menor memória, pois mais memória = mais CPU = execução mais rápida.
2. Revisar funções com 30% de uso de CPU: provavelmente estão superdimensionadas.
3. Avaliar uso de Graviton2 (arm64) — desconto de ~20% sobre x86 para mesma alocação de memória.

**Pré-requisitos:**
- Mapear as funções de maior custo (top 20% que representam ~80% do gasto em Lambda).
- Validar compatibilidade com arm64 antes de migrar para Graviton.

**Riscos:** Baixo. Alteração de memória/arquitetura é reversível instantaneamente. Sem impacto em SLA se testado antes.

---

## Roadmap do Trimestre

```
Semana 1-2   │ #1 Compute Savings Plans (análise de histórico + contratação)
             │ #2 RDS Reserved Instances (análise + contratação)
             │
Semana 3-4   │ #3 CloudWatch Logs (ajuste de retenção + job de exportação)
             │ #6 Lambda Power Tuning (análise + ajuste de memória)
             │
Semana 5-8   │ #4 S3 Intelligent-Tiering + Lifecycle Policies (inventário + config)
             │
Semana 7-12  │ #5 ElastiCache right-sizing (análise → staging → produção)
```

---

## Consolidado de Economia

| # | Oportunidade | Serviço | Economia/mês | % da Conta | Esforço | Risco |
|---|---|---|---|---|---|---|
| 1 | Compute Savings Plans | EC2 on-demand | $2.460 | 5,9% | Baixo | Baixo |
| 2 | Reserved Instances RDS | RDS PostgreSQL | $1.230 | 2,9% | Baixo | Baixo |
| 3 | Retenção de logs + S3 export | CloudWatch Logs | $1.120 | 2,7% | Baixo | Baixo |
| 4 | S3 Intelligent-Tiering | S3 Standard | $775 | 1,9% | Médio | Baixo |
| 5 | ElastiCache right-sizing | ElastiCache Redis | $525 | 1,3% | Médio | Médio |
| 6 | Lambda Power Tuning | Lambda | $180 | 0,4% | Baixo | Baixo |
| — | **Total do plano** | | **$6.290** | **15,1%** | | |

> **Oportunidades adicionais identificadas** (além da meta do trimestre, para backlog):
> - EKS: Karpenter + Spot para non-prod → ~$1.340/mês (esforço alto)
> - NAT Gateway: VPC Endpoints para S3/DynamoDB → ~$360/mês (esforço médio)
> - Data Transfer: CloudFront para reduzir egress → ~$380/mês (esforço médio)

---

*Conta de referência: $41.800/mês | Meta: $6.270/mês (15%) | Plano entrega: $6.290/mês (15,1%)*

