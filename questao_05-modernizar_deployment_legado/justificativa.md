# Modelo

Fiz um teste com o modelo Gemini 2.5 Pro que está localizado no path [output_gemini_25_pro](output_gemini_25_pro).
O resultado das duas queries foram bem parecidos, mas o do Claude Sonnet 4.6 achei mais completo. Algumas diferenças encontradas que ficaram faltando na versão gerada pelo Gemini 2.5 Pro:

Arquivo `deployment.yaml`

- Inclusão da label de versão `version: "1.0.0"`

Arquivo `hpa.yaml`

- Inclusão do trecho `behavior` para scaling up e down

Arquivo `secret.yaml`

- Gemini incluiu valores fictícios. Claude Sonnet reforçou a importância de alterar os valores antes de aplicar o arquivo.

# Justificativa

**Before**

Esta seção descreve o estado inicial e problemático do Deployment da chronos-api. É o ponto de partida.

```
# Before
Temos uma API responsável por todo o tráfego da empresa com a seguinte configuração abaixo de deployment para kubernetes:

apiVersion: apps/v1
kind: Deployment
metadata:
  name: chronos-api
# ... (restante do YAML)
```

**After**

Aqui é descrito o resultado esperado, ou seja, o estado final e moderno que o Deployment deve atingir, listando todos os requisitos e boas práticas a serem aplicados.

```
# After
Queremos uma versão moderna que precisa ter alta disponibilidade, imagem versionada (não utilizar latest), secrets fora do manifesto, resource requests e limits, liveness e readiness probes, securityContext não-root e as demais práticas de produção que hoje são padrão na empresa.
```

**Bridge**

A "ponte" é a solicitação do plano de ação para ir do estado "Before" para o "After" de forma segura e gradual, sem causar indisponibilidade no serviço.

```
# Bridge
Criar um plano de migração em fases para aplicação das novas configurações, onde cada fase possa ser executada sem derrubar a aplicação em produção e plano de rollback.
```