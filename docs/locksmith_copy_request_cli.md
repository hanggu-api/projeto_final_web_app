# Atalho CLI: Cópia de Chave Simples

Este atalho cria um serviço de teste de chaveiro perto do Mix Mateus da Babaçulândia, marca como pago e dispara o `dispatch` sem precisar abrir o app.

## Variáveis obrigatórias

```bash
export SUPABASE_URL="https://SEU_PROJETO.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="SUA_SERVICE_ROLE_KEY"
```

## Execução padrão

```bash
./bin/create_paid_locksmith_copy_request.sh
```

## Defaults do cenário

- profissão: `Chaveiro`
- tarefa: `Cópia de Chave Simples`
- endereço: `Mix Mateus - Babaçulândia, Imperatriz - MA (próximo ao Matheus)`
- coordenadas: `-5.5017472, -47.45835915`
- prestadores preparados online: `chaveiro10@gmail.com,chaveiro12@gmail.com`
- status final do serviço: `searching`
- pagamento final: `paid_manual`

## Variáveis opcionais

```bash
export CLIENT_EMAIL="cliente@exemplo.com"
export PROVIDER_EMAILS_CSV="chaveiro10@gmail.com,chaveiro12@gmail.com"
export TASK_NAME="Cópia de Chave Simples"
export SERVICE_DESCRIPTION="Pedido teste: cópia de chave simples próximo ao Mix Mateus da Babaçulândia"
export PRICE_ESTIMATED_OVERRIDE="13.5"
export CALL_DISPATCH="1"
```

## Saída

O script imprime um JSON com:

- serviço criado,
- profissão e tarefa resolvidas,
- cliente usado no teste,
- resposta do `dispatch`,
- fila gerada em `notificacao_de_servicos`.
