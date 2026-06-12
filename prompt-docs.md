Ler o prompt no arquivo prommt.md e criar a documentação de acordo com os padrões abaixo.

- Inferir metadados

A partir do texto do prompt, inferir:

nome: título humano curto em pt-BR, capitalizado (ex.: "Revisar Pull Request"). Deriva do objetivo central do prompt, não da técnica usada.
descricao: uma única linha descrevendo o objetivo — é o que aparecerá nos índices.
tags: 2 a 5 termos livres em pt-BR que descrevem o domínio e a ação do prompt.
descricao de cada input: o que a variável representa, inferido pelo contexto em que aparece no prompt.
Conteúdo das seções do README:
Objetivo (parágrafo curto baseado no texto do prompt).
Quando usar (2 a 4 bullets inferidos do contexto).
Exemplo de uso — tentar inferir a partir do texto; se não houver base concreta, gravar _A preencher_.
Limitações conhecidas — idem; se não houver base concreta, _A preencher_.

Regra de honestidade: nunca inventar informação que não esteja no próprio texto do prompt. Na dúvida, _A preencher_.

- Frontmatter inferido (YAML pronto, idêntico para os dois arquivos):

```yaml
nome: ...
descricao: ...
versao: 1.0.0
tags: [...]
modelo: ...
inputs:
  - nome: ...
    descricao: ...
```

A documentação deverá ficar no arquivo readme.md