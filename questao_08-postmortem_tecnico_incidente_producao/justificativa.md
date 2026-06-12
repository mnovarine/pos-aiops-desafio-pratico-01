# Modelo

Fiz um teste com o modelo Gemini 2.5 Pro que está localizado no path [gemini](gemini).
O modelo Claude Sonnet 4.6 gerou um procedimento um pouco mais completo e organizado.

# Justificativa

## Como os componentes aparecem no prompt

**Role**

```
"Você é um SRE responsável pelo plantão e por criar runbooks e procedimentos documentados..."
```

Define quem o modelo deve ser. Ao assumir o papel de SRE de plantão, o modelo calibra o vocabulário, o nível técnico e o senso de urgência adequados para um incidente em produção — em vez de responder como um assistente genérico.

**Input**

Fornece todos os artefatos que o modelo precisa para analisar o problema:

| Artefato | O que representa |
| --- | --- |
| Evento do deploy | Changelog do v2.48.0 com as mudanças que podem ser causa raiz | 
| Métricas do Beacon | Série temporal mostrando a degradação progressiva (p99, req/s, err%) | 
| Logs do pod | Evidências diretas: pool exhausted, timeout, circuit-breaker OPEN |
| Estado do Reactor | Impacto downstream — backlog de 50k mensagens crescendo |
| Estado do cluster | Limites atingidos: HPA no máximo, 240/250 conexões RDS |

**Steps**

```
"1. Analisar os eventos do deploy... 2. Analisar as métricas... 6. Montar a timeline..."
```

Define a ordem de raciocínio esperada. Isso evita que o modelo pule para uma conclusão sem passar pela análise de cada fonte de dados — importante para um postmortem que precisa ser auditável.

**Expectation**

Especifica o que o output deve conter, em dois níveis:

1. Conteúdo decisório — árvore de decisão (rollback vs scaling), tempo estimado de cada opção, roteiro detalhado de execução.
2. Formato do documento — título, data/duração/severidade, resumo executivo, timeline, causa raiz, ações corretivas com responsável/prazo, ações preventivas.


## Comparação: Frameworks de Prompt vs Outputs Gerados

**1. Estrutura dos Frameworks**

| Dimensão | RISE | RTF | TAG |
| --- | --- | --- | --- | 
| Acrônimo | Role · Input · Steps · Expectation | Role · Task · Format | Task · Action · Goal |
| Foco principal | Processo passo a passo | Entrega direta com formato | Objetivo final e análise |
| Persona | Explícita (# Role) | Explícita (# Role) | Implícita (inferida da Task) |
| Dados de entrada | Seção dedicada (# Input) | Inline no # Task | Inline no # Task |
| Sequência lógica | Sim — 6 passos numerados | Não — livre | Não — orientado por ação |
| Controle do output | # Expectation (detalhado) | # Format (direto) | # Goal (orientado a resultado) |
| Tamanho do prompt | Maior | Médio | Médio-Maior (duplo Goal) |

**2. Características dos Outputs Gerados**

| Característica | Output RISE | Output RTF | Output TAG |
| --- | --- | --- | --- | 
| Seções geradas | 10+ seções | 9 seções | 8 seções + 5 sub-análises
| Timeline | Muito detalhada com labels [DEPLOY], [WARN], [CRIT] | Detalhada com análise inline por evento | Compacta com [FALHA], [ALERTA] |
| Causa raiz | 3 níveis (imediata, técnica, processo) | Diagrama de cascata + causas primária/secundária | 5 causas em ordem de probabilidade com evidências individuais |
| Comandos CLI | Presentes, moderados | Moderados (kubectl + AWS) | Mais extensos — cada causa tem comandos AWS para validar |
| Árvore de decisão	Textual/ASCII | ASCII + tabela comparativa | ASCII + tabela com 8 opções e tempos |
| Ações corretivas | 10 corretivas + 8 preventivas | 8 corretivas | Por causa raiz (embutidas) |
| Seções extras | Lições Aprendidas (não solicitada) | Diagrama de falha em cascata | Rate limit emergencial no ALB |
| Profundidade analítica | Alta — contexto sistêmico | Alta — foco na decisão | Maior — diagnóstico estruturado |
| Tom | Narrativo + técnico | Pragmático | Investigativo/forense |

**3. Qualidade por Critério de Uso**

| Critério | RISE | RTF | TAG |
| --- | --- | --- | --- | 
| Usar em reunião com o CTO | ★★★★★ | ★★★★☆ | ★★★☆☆ |
| Usar durante o incidente (ação imediata) | ★★★☆☆ | ★★★★★ | ★★★★☆ |
| Diagnóstico de causa raiz | ★★★★☆ | ★★★★☆ | ★★★★★ |
| Roteiro de rollback/scaling | ★★★★★ | ★★★★☆ | ★★★★☆ |
| Ações preventivas / longo prazo | ★★★★★ | ★★★☆☆ | ★★★☆☆ |
| Comandos CLI prontos | ★★★★☆ | ★★★★☆ | ★★★★★ |
| Facilidade de seguir sob pressão | ★★★☆☆ | ★★★★★ | ★★★★☆ |

**4. Diferença Principal na Prática**

**RISE** controlou o processo de raciocínio da IA via Steps — a IA seguiu a sequência e produziu o documento mais completo e elaborado, com seções além do solicitado (Lições Aprendidas). Ideal para documentação formal pós-incidente.

**RTF** controlou a entrega via Format sem prescrever como chegar lá — a IA tomou decisões próprias sobre a análise e produziu o output mais pragmático e a melhor tabela comparativa de decisão. Ideal para comunicação rápida com gestores.

**TAG** o Action no início ("liste as 5 causas mais prováveis") funcionou como um meta-prompt de raciocínio estruturado que redefiniu o output inteiro — a IA produziu o documento mais investigativo, com os comandos AWS mais detalhados por causa raiz e a tabela de tempo mais completa (8 opções). Ideal para times de plantão que precisam validar hipóteses sistematicamente.

**5. Resumo**

RISE → melhor para documentação e cobertura completa

RTF → melhor para decisão rápida sob pressão

TAG → melhor para análise forense de causa raiz

**6. O que se Ganha e o que se Perde em Cada Framework**

| | RISE | RTF | TAG |
| --- | --- | --- | --- |
| **Ganha** | Raciocínio guiado passo a passo — a IA raramente pula etapas críticas | Output direto ao ponto — menos prolixidade, fácil de ler sob pressão | Diagnóstico estruturado e priorizado — as causas mais prováveis vêm primeiro |
| **Ganha** | Separação clara entre contexto (`Input`) e expectativa (`Expectation`) — reduz ambiguidade | `Format` elimina a necessidade de reler o prompt para entender o que foi pedido | `Action` no topo ancora o raciocínio antes mesmo de processar os dados |
| **Ganha** | Output mais completo e com maior cobertura de seções | Melhor para prompts iterativos — fácil de ajustar só o `Format` sem reescrever tudo | `Goal` duplo (início e fim) reforça o objetivo e reduz desvios temáticos |
| **Ganha** | Ideal quando o processo de chegada ao resultado importa tanto quanto o resultado | Menor curva de aprendizado — 3 seções simples e memoráveis | Gera comandos de validação por hipótese — output mais acionável por engenheiros |
| **Perde** | Prompt mais longo e trabalhoso de escrever | Sem `Steps`, a IA pode pular etapas de análise importantes | Sem `Role` explícito, o tom pode variar entre execuções |
| **Perde** | `Steps` prescritivos podem inibir a IA de explorar caminhos não previstos no prompt | Sem `Input` separado, contexto extenso fica misturado com a instrução — dificulta manutenção | `Task` e `Goal` podem se sobrepor semanticamente, gerando redundância no prompt |
| **Perde** | Output tende a ser mais longo, menos adequado para comunicação executiva rápida | Sem `Steps`, a profundidade da análise depende inteiramente do modelo — menos previsível | Menos adequado para documentação narrativa — foco em diagnóstico pode sacrificar contexto de negócio |
| **Perde** | Menos flexível para tarefas abertas onde a IA precisa de autonomia para explorar | Ações preventivas e lições aprendidas tendem a ser superficiais ou ausentes | Estrutura de 5 causas pode forçar causas de baixa probabilidade que não agregam valor real |

**7. Minha Opinião**

O framework RISE produziu o documento mais completo e elaborado dos três. Mesmo sob a pressão de 20 minutos, acredito que daria tempo de escrever o prompt e gerar um post-mortem de qualidade — a estrutura do RISE é trabalhosa de montar, mas é intuitiva: você descreve o cenário no `Input`, lista os passos no `Steps` e define exatamente o que quer no `Expectation`. Uma vez que essa lógica está internalizada, o prompt sai rápido.

Dito isso, a escolha do framework ideal depende do momento do incidente. Durante a crise, com o circuit breaker aberto e a fila crescendo, eu usaria o **RTF** — ele é direto, fácil de escrever sob pressão e produz uma árvore de decisão clara o suficiente para agir em minutos. O **TAG** seria minha escolha para uma análise forense logo após a estabilização, quando o time precisa investigar hipóteses com comandos concretos antes de escrever o post-mortem formal.

O **RISE**, por sua vez, é o framework que eu usaria exatamente nesse contexto — para produzir o documento final que vai para o CTO, com timeline completa, ações corretivas e preventivas, e as lições aprendidas. O fato de o output ter gerado seções além do solicitado (como "Lições Aprendidas") mostra que o `Steps` bem construído leva a IA a raciocinar de forma mais ampla, entregando valor além do mínimo pedido.