### Plano de Otimização de Custos Cloud

**Custo Mensal Total Atual:** $39,800 USD

---

### 1. Otimização de Instâncias EC2 On-Demand
- **Descrição:** Atualmente, uma parte significativa dos custos de computação vem de instâncias EC2 On-Demand com uma utilização média de 45%. Isso indica que há uma oportunidade para otimizar esses custos.
- **Ação Recomendada:** Migrar uma porção das cargas de trabalho de instâncias On-Demand para um AWS Savings Plan de 1 ano. Isso oferece um desconto significativo em troca de um compromisso de uso.
- **Impacto Financeiro:**
    - **Economia Estimada:** $2,460 USD/mês
    - **Percentual do Total:** 6.18%
- **Esforço de Implementação:** Baixo
- **Riscos e Pré-requisitos:**
    - **Pré-requisito:** Análise detalhada do perfil de uso das instâncias para definir o compromisso ideal do Savings Plan.
    - **Risco:** O compromisso do Savings Plan é de 1 ano. Uma redução drástica e inesperada no uso pode diminuir a eficácia do desconto.

---

### 2. Otimização do Armazenamento em S3
- **Descrição:** O custo com S3 Standard é representativo. Para dados que não precisam de acesso imediato, é possível reduzir custos movendo-os para classes de armazenamento mais baratas.
- **Ação Recomendada:** Implementar políticas de ciclo de vida (Lifecycle Policies) nos buckets S3 para mover objetos com mais de 30 dias e menos de 90 dias para a classe S3 Intelligent-Tiering.
- **Impacto Financeiro:**
    - **Economia Estimada:** $930 USD/mês
    - **Percentual do Total:** 2.34%
- **Esforço de Implementação:** Baixo
- **Riscos e Pré-requisitos:**
    - **Pré-requisito:** Validar que os dados a serem movidos não possuem requisitos de acesso de alta frequência.
    - **Risco:** Mínimo. O S3 Intelligent-Tiering move os dados automaticamente entre camadas de acesso, otimizando os custos sem impacto na performance.

---

### 3. Otimização de Custos do CloudWatch
- **Descrição:** Os custos com CloudWatch Logs, especialmente com a retenção de 90 dias, podem ser otimizados.
- **Ação Recomendada:** Reduzir o período de retenção dos logs no CloudWatch de 90 para 30 dias. Para logs que precisam ser mantidos por mais tempo por questões de conformidade, configure a exportação automática para o S3 Glacier Deep Archive.
- **Impacto Financeiro:**
    - **Economia Estimada:** $1,867 USD/mês
    - **Percentual do Total:** 4.69%
- **Esforço de Implementação:** Médio
- **Riscos e Pré-requisitos:**
    - **Pré-requisito:** Revisar as políticas de conformidade e auditoria para garantir que a retenção de 30 dias é suficiente para a maioria dos logs.
    - **Risco:** Acesso a logs com mais de 30 dias se tornará mais lento e complexo, pois exigirá a restauração a partir do S3 Glacier.

---

### 4. Otimização de Custos de Rede com NAT Gateway
- **Descrição:** O custo com NAT Gateways pode ser reduzido se o tráfego de saída para serviços AWS puder ser roteado de forma mais eficiente.
- **Ação Recomendada:** Configurar VPC Gateway Endpoints para serviços AWS como o S3. Isso permite que o tráfego entre suas instâncias EC2 e esses serviços ocorra dentro da rede da AWS, sem passar pelo NAT Gateway e incorrer em custos de transferência de dados.
- **Impacto Financeiro:**
    - **Economia Estimada:** $360 USD/mês
    - **Percentual do Total:** 0.91%
- **Esforço de Implementação:** Médio
- **Riscos e Pré-requisitos:**
    - **Pré-requisito:** Mapear os serviços AWS acessados pelas instâncias na VPC para identificar quais suportam Gateway Endpoints.
    - **Risco:** Requer alterações na configuração de rede (tabelas de rotas da VPC), o que deve ser feito com cuidado para evitar interrupções no serviço.

---

### Resumo das Oportunidades

| Oportunidade | Economia Mensal (USD) | % do Total da Conta | Esforço |
| :--- | :--- | :--- | :--- |
| **EC2 Savings Plan** | $2,460 | 6.18% | Baixo |
| **Otimização do CloudWatch** | $1,867 | 4.69% | Médio |
| **S3 Lifecycle Policies** | $930 | 2.34% | Baixo |
| **VPC Gateway Endpoints** | $360 | 0.91% | Médio |
| **Total** | **$5,617** | **14.12%** | |
