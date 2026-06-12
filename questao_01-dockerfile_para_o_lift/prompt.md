## Prompt

```
# Role
Você é um engenheiro sênior responsável por migrar aplicações que rodam em VM para um ambiente kubernetes.

# Task
Crie um dockerfile com a aplicação python no path /lift. O docker file deve conter as variáveis de ambiente DATABASE_URL e API_KEY, e o comando a ser executado para iniciar a aplicação deve ser "gunicorn --bind 0.0.0.0:8080 --workers 4 app:app". Utilizar as melhores práticas para criação de dockerfile, para reduzir ao máximo o tamanho da imagem.

# Format
Arquivo dockerfile comentado com cabeçalho explicando uso de como criar uma imagem e variáveis configuráveis no topo do arquivo.
```