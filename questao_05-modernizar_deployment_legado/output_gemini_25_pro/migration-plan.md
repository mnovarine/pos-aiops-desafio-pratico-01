# Plano de Migração: Modernização do Deployment `chronos-api`

Este documento descreve o plano de migração em fases para atualizar o `Deployment` da aplicação `chronos-api` no ambiente de produção, incorporando práticas modernas de segurança, alta disponibilidade e resiliência, sem causar indisponibilidade (`zero-downtime`).

## Fases da Migração

A migração será dividida em fases para isolar as mudanças, facilitar a validação e permitir um rollback controlado em caso de problemas.

### Fase 1: Externalização de Segredos

**Objetivo:** Remover dados sensíveis (segredos) do manifesto do `Deployment` e armazená-los em um objeto `Secret` do Kubernetes.

**Passos:**
1.  **Criar o Secret:** Aplique o manifesto `secret.yaml` para criar o `Secret` `chronos-api-secret` contendo as variáveis `DB_PASSWORD` e `JWT_SECRET`.
    ```bash
    kubectl apply -f secret.yaml
    ```
2.  **Atualizar o Deployment (Canary Release):** Crie uma cópia do deployment atual com um novo nome (ex: `chronos-api-v2`) e altere-o para referenciar as variáveis do `Secret` recém-criado. Mantenha o número de réplicas em 1 para este novo deployment. O tráfego ainda será direcionado para a versão antiga.
3.  **Validação:** Verifique os logs do novo pod `chronos-api-v2` para garantir que a aplicação inicia e funciona corretamente com os segredos injetados.
4.  **Rollout Gradual:** Se a validação for bem-sucedida, atualize o `Deployment` original (`chronos-api`) para usar os segredos, aplicando a mudança de forma gradual (rolling update). O Kubernetes substituirá os pods um a um.
    *   *Nota: A aplicação do `deployment.yaml` moderno já fará isso na Fase 3.*

**Plano de Rollback (Fase 1):**
*   Se a nova versão com `Secret` apresentar falhas, simplesmente delete o deployment `chronos-api-v2`.
*   Se o `Deployment` principal foi atualizado e falhou, reverta para a revisão anterior usando `kubectl rollout undo`.
    ```bash
    kubectl rollout undo deployment/chronos-api -n production
    ```

### Fase 2: Implementando Alta Disponibilidade (HA)

**Objetivo:** Garantir que a aplicação possa tolerar falhas de nós ou manutenções voluntárias sem ficar indisponível.

**Passos:**
1.  **Aplicar o PodDisruptionBudget (PDB):** Crie o PDB para garantir que sempre haverá um número mínimo de réplicas disponíveis.
    ```bash
    kubectl apply -f pdb.yaml
    ```
2.  **Aumentar as Réplicas:** Escale o `Deployment` atual para 3 réplicas para garantir a distribuição entre os nós.
    ```bash
    kubectl scale deployment/chronos-api --replicas=3 -n production
    ```
3.  **Aplicar o HorizontalPodAutoscaler (HPA):** Permita que o deployment escale automaticamente com base na demanda.
    ```bash
    kubectl apply -f hpa.yaml
    ```

**Plano de Rollback (Fase 2):**
*   Remova o HPA e o PDB.
    ```bash
    kubectl delete -f hpa.yaml
    kubectl delete -f pdb.yaml
    ```
*   Reduza o número de réplicas para o valor original.
    ```bash
    kubectl scale deployment/chronos-api --replicas=1 -n production
    ```

### Fase 3: Atualização Completa do Deployment

**Objetivo:** Aplicar todas as melhorias restantes: imagem versionada, probes de saúde, resource limits e security context.

**Passos:**
1.  **Verificar Pré-requisitos:**
    *   A imagem `chronos-api:1.0.0` deve estar disponível no registry.
    *   Os endpoints `/healthz` e `/ready` devem estar implementados na aplicação.
2.  **Aplicar o Novo Deployment:** Aplique o manifesto `deployment.yaml` modernizado. O Kubernetes executará uma `Rolling Update` por padrão, substituindo os pods antigos pelos novos de forma gradual, respeitando as regras de `maxSurge` e `maxUnavailable`.
    ```bash
    kubectl apply -f deployment.yaml
    ```
3.  **Monitoramento:** Acompanhe o rollout com o comando:
    ```bash
    kubectl rollout status deployment/chronos-api -n production --watch
    ```
    Verifique os logs dos novos pods e o comportamento geral da aplicação.

**Plano de Rollback (Fase 3):**
*   Se o novo `Deployment` apresentar problemas, execute o comando de rollback para retornar à última configuração estável.
    ```bash
    kubectl rollout undo deployment/chronos-api -n production
    ```
    O Kubernetes fará o processo inverso, substituindo os pods novos pelos antigos.

## Resumo dos Comandos para Execução

```bash
# Fase 1
kubectl apply -f secret.yaml

# Fase 2
kubectl apply -f pdb.yaml
# Aumentar réplicas e aplicar HPA já está incluso no novo deployment.yaml,
# mas pode ser feito antes no deployment antigo se desejado.
# kubectl scale deployment/chronos-api --replicas=3 -n production
kubectl apply -f hpa.yaml

# Fase 3
# Garanta que a imagem e os endpoints de probe existem!
kubectl apply -f deployment.yaml

# Monitorar
kubectl rollout status deployment/chronos-api -n production --watch
```
