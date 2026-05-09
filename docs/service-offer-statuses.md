# Service Offer Statuses

## Objetivo

Padronizar os estados relevantes da oferta enviada ao prestador durante o dispatch sequencial.

## Estados principais da oferta

- `queued`
  - oferta materializada na fila, ainda não enviada ao prestador.

- `notified`
  - push enviado e oferta ativa para resposta do prestador.

- `accepted`
  - prestador aceitou a oferta e a fila deve encerrar.

- `rejected`
  - prestador recusou explicitamente a oferta.

- `timeout`
  - prazo da oferta expirou sem aceite válido.

## Estados de limpeza / fallback

- `skipped_duplicate_provider`
  - o worker detectou que aquele prestador já havia sido tentado para o mesmo serviço.

- `skipped_permanent_push`
  - o push não era entregável de forma permanente, por exemplo token ausente ou inválido.

## Regras de UI

O modal do prestador deve permanecer aberto apenas enquanto o estado ativo for:

- `notified`

O modal deve fechar quando o backend devolver qualquer outro estado, por exemplo:

- `accepted`
- `rejected`
- `timeout`
- `skipped_duplicate_provider`
- `skipped_permanent_push`

## Convenções recomendadas

- usar um único tipo canônico de payload para oferta de serviço;
- evitar aliases como `offer`, `service_offered` e `service.offered` em novos fluxos;
- tratar o backend como fonte de verdade para `response_deadline_at`.
