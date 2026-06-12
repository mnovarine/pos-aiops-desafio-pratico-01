# Modelo

Fiz um teste com o modelo Gemini 2.5 Pro que está localizado no path [resultado_outros_modelos/gemini_2_5_pro.sh](resultado_outros_modelos/gemini_2_5_pro.sh).
O modelo Claude Sonnet 4.6 gerou um script mais estruturado e organizado, separado por funções.

# Justificativa

## Como os componentes aparecem no prompt

**Role**

No prompt: Você é um SRE sênior responsável por automatizar rotinas operacionais.

Isso instrui a IA a agir com a experiência e o ponto de vista de um Engenheiro de Confiabilidade de Sites (SRE) experiente, focando em automação, boas práticas e robustez.

**Task**

No prompt: Crie um script Bash de backup automático diário para um banco PostgreSQL... seguido por todos os detalhes técnicos como host, banco, usuário, método de autenticação, bucket S3, política de rotação, logging e agendamento.

Esta é a parte mais densa, detalhando "o que" fazer (backup de um banco PostgreSQL) e "como" fazer (usando pg_dump, gzip, aws s3 cp, etc.), além de todas as informações do ambiente (ledger-db.internal.hvt.io, us-east-1, etc.).

**Format**   

No prompt: Script Bash comentado, com cabeçalho explicando uso e variáveis configuráveis no topo do arquivo.

Define a aparência do resultado final, garantindo que o script seja legível, bem documentado e fácil de manter, que são características valorizadas por um SRE sênior.