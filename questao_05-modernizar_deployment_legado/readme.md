## Prompt

```
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

## Modelo

Claude Sonnet 4.6

## Output

# Plano de Modernização — chronos-api

## Visão Geral dos Arquivos

| Arquivo | Descrição |
|---|---|
| `deployment.yaml` | Deployment modernizado (versão final) |
| `secret.yaml` | Secret com credenciais externalizadas |
| `pdb.yaml` | PodDisruptionBudget — garante mínimo de 2 pods durante manutenção |
| `hpa.yaml` | HorizontalPodAutoscaler — escala automática por CPU/memória |

---

## Problemas Identificados no Manifesto Original

| # | Problema | Risco | Criticidade |
|---|---|---|---|
| 1 | Credenciais hardcoded no manifesto (`DB_PASSWORD`, `JWT_SECRET`) | Exposição de secrets em git, logs e `kubectl get deployment -o yaml` | **CRÍTICO** |
| 2 | `image: chronos-api:latest` | Deploy imprevisível; reimagem silenciosa pode quebrar produção | Alto |
| 3 | `replicas: 1` | SPOF — qualquer restart derruba o serviço | Alto |
| 4 | Ausência de `strategy` rolling update | Restart in-place derruba o pod durante atualização | Alto |
| 5 | Ausência de `resources` (requests/limits) | Container pode consumir todo o nó; OOM Kill sem controle | Médio |
| 6 | Ausência de `livenessProbe` / `readinessProbe` | Kubernetes não detecta travamentos; tráfego é roteado para pods não prontos | Médio |
| 7 | Ausência de `securityContext` | Container roda como root por padrão | Médio |
| 8 | Ausência de PodDisruptionBudget | Drain de nó pode derrubar todos os pods simultaneamente | Médio |

---

## Plano de Migração em Fases

> **Princípio-guia**: cada fase usa `RollingUpdate` com `maxUnavailable: 0`, garantindo que sempre haverá pods saudáveis servindo tráfego. O comando de rollback de qualquer fase é `kubectl rollout undo deployment/chronos-api -n production`.

---

### Fase 1 — Externalização de Secrets ⚠️ URGENTE

**Objetivo**: Remover credenciais hardcoded do manifesto.  
**Risco**: Baixo — é apenas uma mudança de onde o valor é lido; a aplicação recebe o mesmo valor via env var.

#### Passos

**1.1 — Gerar os valores base64 (em ambiente seguro, nunca no CI sem vault):**
```bash
echo -n 'SuaSenhaRealAqui' | base64
echo -n 'SeuJwtSecretReal' | base64
```

**1.2 — Editar `secret.yaml` com os valores gerados e aplicar:**
```bash
# Substitua os placeholders em secret.yaml pelos valores base64 reais
kubectl apply -f secret.yaml
kubectl get secret chronos-api-secrets -n production  # confirma criação
```

**1.3 — Atualizar o Deployment para referenciar o Secret:**
```bash
# Aplicar somente as mudanças de env (sem alterar réplicas ou imagem ainda)
kubectl patch deployment chronos-api -n production --patch '
spec:
  template:
    spec:
      containers:
      - name: api
        env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: chronos-api-secrets
              key: db-password
        - name: JWT_SECRET
          valueFrom:
            secretKeyRef:
              name: chronos-api-secrets
              key: jwt-secret'
```

**1.4 — Verificar:**
```bash
kubectl rollout status deployment/chronos-api -n production
kubectl exec -it deployment/chronos-api -n production -- env | grep -E 'DB_PASSWORD|JWT_SECRET'
```

#### Rollback Fase 1
```bash
kubectl rollout undo deployment/chronos-api -n production
kubectl delete secret chronos-api-secrets -n production
```

---

### Fase 2 — Alta Disponibilidade + Imagem Versionada

**Objetivo**: Eliminar o SPOF (single replica), configurar rolling update correto e fixar a tag da imagem.  
**Risco**: Baixo. O aumento de réplicas é aditivo; a estratégia `maxUnavailable: 0` garante zero downtime.

**Pré-requisito**: confirmar a tag exata da imagem atual em produção:
```bash
kubectl get deployment chronos-api -n production -o jsonpath='{.spec.template.spec.containers[0].image}'
```

#### Passos

**2.1 — Aplicar réplicas, strategy, PDB e tag versionada:**
```bash
kubectl apply -f pdb.yaml

kubectl patch deployment chronos-api -n production --patch '
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    spec:
      containers:
      - name: api
        image: chronos-api:1.0.0'
```

**2.2 — Verificar:**
```bash
kubectl rollout status deployment/chronos-api -n production
kubectl get pods -n production -l app=chronos-api
kubectl get pdb -n production
```

#### Rollback Fase 2
```bash
kubectl rollout undo deployment/chronos-api -n production
kubectl delete pdb chronos-api-pdb -n production
```

---

### Fase 3 — Resource Requests e Limits

**Objetivo**: Proteger o nó de uso excessivo e garantir QoS ao scheduler.  
**Risco**: Médio. Se os limites forem muito baixos, pods podem sofrer OOM Kill ou throttling de CPU.

**Pré-requisito**: medir consumo real com `kubectl top pods -n production` e ajustar os valores abaixo antes de aplicar.

#### Passos

**3.1 — Coletar métricas de baseline (faça durante 30 min de carga normal):**
```bash
kubectl top pods -n production -l app=chronos-api --containers
```

**3.2 — Aplicar resources (ajuste os valores conforme baseline):**
```bash
kubectl patch deployment chronos-api -n production --patch '
spec:
  template:
    spec:
      containers:
      - name: api
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"'
```

**3.3 — Verificar:**
```bash
kubectl rollout status deployment/chronos-api -n production
kubectl describe pods -n production -l app=chronos-api | grep -A6 "Limits:"
# Monitorar por 15 min — verificar se há OOMKilled ou Throttling
kubectl get events -n production --sort-by='.lastTimestamp' | grep -E 'OOM|Kill|Evict'
```

#### Rollback Fase 3
```bash
kubectl rollout undo deployment/chronos-api -n production
```

---

### Fase 4 — SecurityContext Não-Root

**Objetivo**: Eliminar execução como root, remover capabilities desnecessárias, e ativar `readOnlyRootFilesystem`.  
**Risco**: Médio. Se a aplicação escreve em diretórios do sistema de arquivos da raiz (ex: `/tmp`, `/app/logs`), irá falhar. Testar em staging antes.

**Pré-requisito**: validar em staging que a aplicação inicia corretamente com `runAsUser: 1000` e `readOnlyRootFilesystem: true`. Se precisar de escrita em `/tmp`, adicione um `emptyDir` volume (veja comentário no `deployment.yaml`).

#### Passos

**4.1 — Aplicar securityContext:**
```bash
kubectl patch deployment chronos-api -n production --patch '
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: api
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL'
```

**4.2 — Verificar:**
```bash
kubectl rollout status deployment/chronos-api -n production
kubectl exec -it deployment/chronos-api -n production -- id
# Deve retornar: uid=1000 gid=1000
```

#### Rollback Fase 4
```bash
kubectl rollout undo deployment/chronos-api -n production
```

---

### Fase 5 — Liveness e Readiness Probes

**Objetivo**: Permitir que o Kubernetes detecte pods travados (liveness) e pods ainda inicializando (readiness).  
**Risco**: Médio. Probes com `initialDelaySeconds` muito curto ou `path` errado causam restart loops. Validar endpoints antes.

**Pré-requisito**: confirmar os endpoints de health da aplicação:
```bash
# Teste direto no pod antes de configurar as probes
kubectl exec -it deployment/chronos-api -n production -- curl -s http://localhost:8080/healthz
kubectl exec -it deployment/chronos-api -n production -- curl -s http://localhost:8080/ready
```

#### Passos

**5.1 — Aplicar probes (ajuste os paths conforme a aplicação real):**
```bash
kubectl patch deployment chronos-api -n production --patch '
spec:
  template:
    spec:
      containers:
      - name: api
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          failureThreshold: 3
          timeoutSeconds: 5
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
          failureThreshold: 3
          timeoutSeconds: 3'
```

**5.2 — Verificar:**
```bash
kubectl rollout status deployment/chronos-api -n production
kubectl get pods -n production -l app=chronos-api
# Aguardar alguns minutos e checar se há CrashLoopBackOff ou Restarts
kubectl get pods -n production -l app=chronos-api -w
```

#### Rollback Fase 5
```bash
kubectl rollout undo deployment/chronos-api -n production
```

---

### Fase 6 — HPA (Autoscaling Horizontal)

**Objetivo**: Escalar automaticamente conforme carga de CPU/memória, mantendo o mínimo de 3 réplicas.  
**Risco**: Baixo. O HPA apenas aumenta e diminui réplicas dentro dos limites definidos; o PDB garante o mínimo de 2 disponíveis.

**Pré-requisito**: Metrics Server deve estar instalado no cluster:
```bash
kubectl get deployment metrics-server -n kube-system
```

#### Passos

**6.1 — Aplicar HPA:**
```bash
kubectl apply -f hpa.yaml
```

**6.2 — Verificar:**
```bash
kubectl get hpa -n production
kubectl describe hpa chronos-api-hpa -n production
# Monitorar escalonamento sob carga:
kubectl get hpa -n production -w
```

#### Rollback Fase 6
```bash
kubectl delete hpa chronos-api-hpa -n production
# O Deployment permanece inalterado; as réplicas voltam ao valor estático definido no spec.
```

---

### Fase 7 — Aplicar o Manifesto Completo Final

Após todas as fases validadas individualmente, aplicar o `deployment.yaml` final como fonte única da verdade:

```bash
kubectl apply -f secret.yaml
kubectl apply -f deployment.yaml
kubectl apply -f pdb.yaml
kubectl apply -f hpa.yaml
kubectl rollout status deployment/chronos-api -n production
```

---

## Rollback Global de Emergência

Se a aplicação apresentar problemas graves após qualquer fase e o rollback individual não for suficiente:

```bash
# Ver histórico de revisões
kubectl rollout history deployment/chronos-api -n production

# Voltar para uma revisão específica (ex: revisão 1 = estado original)
kubectl rollout undo deployment/chronos-api -n production --to-revision=1

# Acompanhar o rollback
kubectl rollout status deployment/chronos-api -n production

# Remover recursos auxiliares se necessário
kubectl delete hpa chronos-api-hpa -n production
kubectl delete pdb chronos-api-pdb -n production
kubectl delete secret chronos-api-secrets -n production
```

---

## Resumo das Melhorias Aplicadas

| Prática | Antes | Depois |
|---|---|---|
| Secrets | Hardcoded no manifesto | `secretKeyRef` → `chronos-api-secrets` |
| Tag da imagem | `:latest` | `:1.0.0` (versionada) |
| Réplicas | 1 | 3 (mín) / 10 (máx via HPA) |
| Rolling update | Não configurado | `maxSurge: 1`, `maxUnavailable: 0` |
| Distribuição de pods | Sem controle | `topologySpreadConstraints` por nó |
| Resource requests/limits | Ausente | CPU 100m–500m / Mem 128Mi–512Mi |
| Liveness probe | Ausente | `GET /healthz` |
| Readiness probe | Ausente | `GET /ready` |
| SecurityContext (pod) | Root implícito | `runAsNonRoot`, `runAsUser: 1000`, `seccompProfile` |
| SecurityContext (container) | Sem restrições | `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities drop ALL` |
| PodDisruptionBudget | Ausente | `minAvailable: 2` |
| Autoscaling | Manual | HPA — CPU 70% / Mem 80% |
