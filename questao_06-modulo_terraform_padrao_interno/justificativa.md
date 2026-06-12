# Modelo

Fiz um teste com o modelo Gemini 2.5 Pro que está localizado no path [output_gemini_25_pro](output_gemini_25_pro).
O resultado foi bem parecido, mas o do Claude Sonnet 4.6 ficou melhor documentado, inclusive os exemplos.

# Justificativa

## Como os componentes aparecem no prompt

**Context**

Esta seção define o cenário e as regras que a IA deve seguir.

- No enunciado: A descrição do padrão interno de IaC definido por Strickland e as convenções da empresa.
```
"Trabalhamos com Terraform na AWS. Seguimos o padrão de módulos do terraform-aws-modules como referência de estrutura. Usamos workspaces para separar ambientes (dev, staging, production). Convenção de naming: kebab-case para recursos, snake_case para variáveis, prefixo hvt- nos nomes de recursos e tags obrigatórias em todo recurso: Owner, CostCenter, Environment."
```

- No `prompt.md`: A seção `# Context` reflete exatamente essas informações.

**Action**

Esta é a tarefa principal que a IA deve executar.

- No enunciado: O pedido de Doc Brown para a criação do módulo.
```
"Doc Brown pediu um módulo Terraform reutilizável pra criar buckets S3 aderentes a esse padrão."
```

- No `prompt.md`: A seção `# Action` descreve a tarefa de forma direta, detalhando os requisitos técnicos do bucket S3.
```
"Crie um Terraform module para provisionar um bucket S3 com versionamento, encryption com KMS (SSE-S3 mínimo), block public access total e logging configurado."
```

**Result**

Aqui se especifica o que se espera como entrega final, definindo o formato e a estrutura da saída.

- No enunciado: A menção de que o módulo precisa ser consumível e vir com exemplo de uso.
```
"O módulo vai ser consumido por todos os times da empresa, então precisa vir com exemplo de uso."
```

- No `prompt.md`: A seção `# Result` detalha os artefatos esperados.
```
"O module deve conter: main.tf, variables.tf com descrições e validações, outputs.tf com ARN e nome do bucket s3, e um README.md com exemplo de uso. Seguir as convenções de naming definidas no contexto."
```

**Example**

Fornece um modelo concreto para guiar a IA sobre o estilo e a estrutura desejados.

- No enunciado: A referência ao módulo de VPC existente.
```
"Como referência de estilo, o módulo de VPC que já existe na empresa..."
```

- No `prompt.md`: A seção `# Example` apresenta o trecho de código do módulo de VPC.
```
"Aqui está a estrutura do nosso modulo de VPC que é a referência que utilizamos..."
```