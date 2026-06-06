## Prompt

```
# Task
Você é o Product Manager e precisa apresentar para a CEO as informações sobre crescimento de transações.

# Action
Listar as informações por categorias em produção hoje: subscription, one_time, refund e credit_adjustment. Somente quem tem status = 'completed'. O campo amount_cents está em centavos de real e precisa aparecer na saída em reais com 2 casas decimais. O recorte é dos últimos 6 meses corridos a partir de hoje (2026-04-24), agrupado por mês (no formato YYYY-MM) e por categoria, trazendo duas métricas por linha: quantidade de transações e volume total em reais. Ordenação final: mês crescente, depois categoria crescente.

As informações do histórico completo estão armazenadas no PostgreSQL no formato abaixo:

CREATE TABLE transactions (
  id              BIGSERIAL PRIMARY KEY,
  customer_id     BIGINT NOT NULL REFERENCES customers(id),
  category        VARCHAR(32) NOT NULL,
  amount_cents    BIGINT NOT NULL,
  status          VARCHAR(16) NOT NULL,
  payment_method  VARCHAR(16),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at    TIMESTAMPTZ
);

CREATE INDEX idx_transactions_created_at ON transactions(created_at);
CREATE INDEX idx_transactions_status ON transactions(status);
CREATE INDEX idx_transactions_category ON transactions(category);
CREATE TABLE customers (
  id          BIGSERIAL PRIMARY KEY,
  segment     VARCHAR(16) NOT NULL,
  country     CHAR(2) NOT NULL,
  signup_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

# Goal
Objetivo: Criar uma query SQL que liste os números consolidados nos últimos 6 meses por categoria.
```

## Modelo

Claude Sonnet 4.6

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
