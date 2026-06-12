# Modelo

Fiz um teste com o modelo Gemini 2.5 Pro que está localizado no path [resultado_outros_modelos/gemini_2_5_pro.sql](resultado_outros_modelos/gemini_2_5_pro.sql).
O resultado das duas queries foram bem parecidos.

# Justificativa

## Como os componentes aparecem no prompt

**Task**

No prompt: Você é o Product Manager e precisa apresentar para a CEO as informações sobre crescimento de transações.

Isso estabelece a persona (Product Manager) e o cenário de negócio (apresentar dados de crescimento para a CEO).

**Action**

No prompt: Listar as informações por categorias em produção hoje: subscription, one_time, refund e credit_adjustment. Somente quem tem status = 'completed'. O campo amount_cents está em centavos de real e precisa aparecer na saída em reais com 2 casas decimais. O recorte é dos últimos 6 meses corridos a partir de hoje (2026-04-24), agrupado por mês (no formato YYYY-MM) e por categoria, trazendo duas métricas por linha: quantidade de transações e volume total em reais. Ordenação final: mês crescente, depois categoria crescente.

Aqui estão todas as regras: filtros (status = 'completed', categorias específicas, período de 6 meses), formatação (amount_cents para reais, formato da data), agrupamento (mês e categoria) e ordenação.

**Goal**

No prompt: Criar uma query SQL que liste os números consolidados nos últimos 6 meses por categoria.

Este é o objetivo concreto e final: gerar um código SQL que atenda a todos os requisitos da Ação.