WITH transacoes_ultimos_6_meses AS (
    SELECT
        TO_CHAR(created_at, 'YYYY-MM') AS mes,
        category,
        amount_cents
    FROM
        transactions
    WHERE
        status = 'completed'
        AND category IN ('subscription', 'one_time', 'refund', 'credit_adjustment')
        AND created_at >= date_trunc('month', CAST('2026-04-24' AS DATE) - INTERVAL '5 months')
        AND created_at < date_trunc('month', CAST('2026-04-24' AS DATE) + INTERVAL '1 month')
)
SELECT
    mes,
    category,
    COUNT(*) AS quantidade_de_transacoes,
    TO_CHAR(SUM(amount_cents) / 100.0, 'FM999G999G999D00') AS volume_total_em_reais
FROM
    transacoes_ultimos_6_meses
GROUP BY
    mes,
    category
ORDER BY
    mes ASC,
    category ASC;
