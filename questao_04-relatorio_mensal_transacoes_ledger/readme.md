---
nome: Relatório Mensal de Transações por Categoria
descricao: Gera query SQL consolidando transações dos últimos 6 meses por categoria e mês para apresentação gerencial.
versao: 1.0.0
tags: [sql, postgresql, transações, relatório, product-management]
modelo: Claude Sonnet 4.6
inputs:
  - nome: data_referencia
    descricao: Data de referência para calcular a janela dos últimos 6 meses corridos (formato YYYY-MM-DD).
---

# Relatório Mensal de Transações por Categoria

## Objetivo

Criar uma query SQL PostgreSQL que consolide as transações com status `completed` dos últimos 6 meses corridos, agrupadas por mês (formato `YYYY-MM`) e categoria (`subscription`, `one_time`, `refund`, `credit_adjustment`). Cada linha traz a quantidade de transações e o volume total em reais (convertido de centavos), com ordenação por mês e categoria crescentes — destinado à apresentação de crescimento de transações para a CEO.

## Quando usar

- Necessário apresentar métricas de crescimento de transações para liderança executiva.
- Geração de relatório mensal de performance financeira segmentado por categoria de transação.
- Análise de tendências em volume e quantidade de transações ao longo dos últimos 6 meses.
- Quando o campo monetário está armazenado em centavos e precisa ser convertido para reais na saída.

## Exemplo de uso

**Query gerada:**

```sql
SELECT
    TO_CHAR(created_at, 'YYYY-MM')        AS mes,
    category                               AS categoria,
    COUNT(*)                               AS qtd_transacoes,
    ROUND(SUM(amount_cents) / 100.0, 2)   AS volume_total_brl
FROM transactions
WHERE status = 'completed'
  AND category IN ('subscription', 'one_time', 'refund', 'credit_adjustment')
  AND created_at >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '5 months'
  AND created_at <  DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month'
GROUP BY 1, 2
ORDER BY 1, 2;
```

## Limitações conhecidas

- A janela temporal é baseada em `created_at`, não em `completed_at`; transações criadas fora da janela mas concluídas dentro dela não serão incluídas.
- A ordenação de categoria é alfabética — não reflete prioridade de negócio ou volume.
- O mês vigente pode estar incompleto se a query for executada antes do encerramento do mês.
