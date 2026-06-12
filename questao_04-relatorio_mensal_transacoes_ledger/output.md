## Output

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

### Explicação das decisões

| Ponto | Decisão |
|---|---|
| Janela temporal | `DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '5 months'` cobre o início do mês atual menos 5 = 6 meses corridos inclusive o mês atual |
| Filtro de data | `< DATE_TRUNC(...) + INTERVAL '1 month'` garante que o mês atual seja incluído por completo sem depender de horário |
| Conversão de centavos | `SUM(amount_cents) / 100.0` usa divisão de ponto flutuante antes do `ROUND(..., 2)` para evitar truncamento inteiro |
| Formato do mês | `TO_CHAR(created_at, 'YYYY-MM')` produz exatamente `YYYY-MM` como pedido |
| Ordenação | `ORDER BY 1, 2` — mês crescente, depois categoria crescente (alfabética) |
