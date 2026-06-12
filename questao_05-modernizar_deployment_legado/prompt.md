## Prompt

```markdown
# Before
Temos uma API responsável por todo o tráfego da empresa com a seguinte configuração abaixo de deployment para kubernetes:

apiVersion: apps/v1
kind: Deployment
metadata:
  name: chronos-api
  namespace: production
spec:
  replicas: 1
  selector:
    matchLabels:
      app: chronos-api
  template:
    metadata:
      labels:
        app: chronos-api
    spec:
      containers:
      - name: api
        image: chronos-api:latest
        ports:
        - containerPort: 8080
        env:
        - name: DB_PASSWORD
          value: "P@ssw0rd2023!"
        - name: JWT_SECRET
          value: "hvt-jwt-prod-secret"

# After
Queremos uma versão moderna que precisa ter alta disponibilidade, imagem versionada (não utilizar latest), secrets fora do manifesto, resource requests e limits, liveness e readiness probes, securityContext não-root e as demais práticas de produção que hoje são padrão na empresa.

# Bridge
Criar um plano de migração em fases para aplicação das novas configurações, onde cada fase possa ser executada sem derrubar a aplicação em produção e plano de rollback.
```