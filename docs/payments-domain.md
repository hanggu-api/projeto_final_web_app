# Domínio de Pagamentos

## Direção

Separar política de pagamento do provedor externo.

## Regras

- status financeiro canônico
- gateways tratados como adapters
- webhooks e confirmações precisam ser idempotentes

## Meta

- menos ifs espalhados por provider/gateway
- menos mistura entre UI, edge function e regra financeira
