## Prompt

```markdown
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