# Modelo

Fiz um teste com o modelo Gemini 2.5 Pro e gerou exatamente o mesmo resultado. Então deixei a versão gerada com o modelo Claude Sonnet 4.6 pois é o modelo que eu já tenho como default no Github Copilot do VS Code e geralmente utilizo com frequencia e tem me atendido bem. 

# Justificativa

**Role**

Enunciado: "O Lift vai sair das VMs onde vem rodando e entrar no cluster Kubernetes da empresa."

Prompt: A seção # Role traduz esse contexto para a persona que a IA deve assumir: Você é um engenheiro sênior responsável por migrar aplicações que rodam em VM para um ambiente kubernetes.

**Task**

Enunciado: "...uma API Python/Flask na porta 8080, dependências declaradas em requirements.txt, e duas variáveis de ambiente que precisam estar presentes no runtime, DATABASE_URL e API_KEY."

Prompt: A seção # Task detalha a tarefa específica, incorporando todos os requisitos técnicos do enunciado: Crie um dockerfile com a aplicação python no path /lift. O docker file deve conter as variáveis de ambiente DATABASE_URL e API_KEY, e o comando a ser executado para iniciar a aplicação deve ser "gunicorn --bind 0.0.0.0:8080 --workers 4 app:app".

**Format**   

Prompt: A seção # Format especifica como a saída deve ser estruturada, garantindo que o resultado seja claro e utilizável: Arquivo dockerfile comentado com cabeçalho explicando uso de como criar uma imagem e variáveis configuráveis no topo do arquivo.