---
nome: Modernizar Deployment Kubernetes Legado
descricao: Moderniza um manifesto de Deployment Kubernetes legado aplicando práticas de produção e gera um plano de migração em fases com rollback.
versao: 1.0.0
tags: [kubernetes, deployment, modernização, produção, migração]
modelo: Claude Sonnet 4.6
inputs:
  - nome: deployment_original
    descricao: Manifesto YAML do Deployment Kubernetes legado a ser modernizado
  - nome: requisitos_producao
    descricao: Lista de práticas de produção desejadas na versão modernizada (alta disponibilidade, secrets externalizados, probes, securityContext não-root etc.)
---

# Modernizar Deployment Kubernetes Legado

## Objetivo

Receber um manifesto de Deployment Kubernetes legado com falhas críticas de segurança e disponibilidade — como credenciais hardcoded, réplica única e ausência de probes — e gerar tanto a versão modernizada dos manifestos quanto um plano de migração em fases executável sem downtime, incluindo procedimento de rollback para cada etapa.

## Quando usar

- Quando um Deployment em produção possui credenciais hardcoded diretamente no manifesto YAML
- Quando a aplicação opera com réplica única e está sujeita a SPOF (single point of failure)
- Quando o manifesto referencia imagem com tag `:latest`, tornando deploys imprevisíveis
- Quando é necessário evoluir a configuração de forma incremental sem interromper o serviço em produção

## Exemplo de uso

**Input (`deployment_original`)**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: chronos-api
  namespace: production
spec:
  replicas: 1
  ...
  containers:
  - name: api
    image: chronos-api:latest
    env:
    - name: DB_PASSWORD
      value: "P@ssw0rd2023!"
```

**Output gerado**: plano de migração em 7 fases (externalização de secrets, alta disponibilidade, resource limits, securityContext, probes, HPA e aplicação final), manifestos prontos (`deployment.yaml`, `secret.yaml`, `pdb.yaml`, `hpa.yaml`) e comandos de rollback por fase.

## Limitações conhecidas

- Os valores de `resources.requests` e `resources.limits` são ilustrativos; devem ser calibrados com base no consumo real medido via `kubectl top pods`
- Os endpoints de health (`/healthz`, `/ready`) são supostos; devem ser validados conforme os endpoints reais da aplicação antes de ativar as probes em produção
- A tag de imagem `1.0.0` usada no output é um placeholder; deve ser substituída pela tag real da versão em produção

---
