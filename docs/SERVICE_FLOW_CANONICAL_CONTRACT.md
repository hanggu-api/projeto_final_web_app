# Contrato Canônico de Fluxo de Serviço (API + App)

Fonte de verdade: backend-first.
Implementações cliente/prestador só podem refletir os estados/eventos definidos aqui.

## Estados canônicos (`ServiceState`)
- `searching_provider`
- `open_for_schedule`
- `offered_to_provider`
- `provider_accepted`
- `provider_rejected`
- `provider_arrived`
- `waiting_pix_down_payment`
- `pix_down_payment_paid`
- `in_progress`
- `awaiting_completion_code`
- `completed`
- `cancelled`
- `expired`
- `disputed`

## Eventos de dispatch (`DispatchEvent`)
- `queued`
- `offer_dispatched`
- `provider_accepted`
- `provider_rejected`
- `timeout`
- `queue_exhausted`

## Estado de pagamento PIX (`PixPaymentState`)
- `created`
- `pending`
- `paid`
- `failed`
- `expired`

## Contrato mínimo de payload
- Obrigatórios:
  - `service_id`
  - `service_state`
  - `updated_at`
- Opcionais por fase:
  - `dispatch_event`
  - `pix_state`
  - `provider_id`
  - `completion_code`
  - `completion_code_expires_at`
  - `completion_code_consumed_at`
  - `review_trigger`

## Matriz de permissão por papel
- Cliente:
  - criar solicitação
  - confirmar pagamento PIX
  - confirmar código de conclusão
  - cancelar serviço
  - abrir disputa
- Prestador:
  - aceitar/recusar oferta
  - marcar chegada
  - iniciar serviço
  - emitir/validar fluxo de código
  - concluir serviço
  - abrir disputa
- Backend:
  - disparar ofertas
  - gerar cobrança PIX
  - concluir/cancelar por regra sistêmica

## Regras de fallback
- Se payload legado vier com status alternativo, deve normalizar para estado canônico antes da UI.
- UI nunca deve inferir transições fora da máquina de estados.
- Em erro de sincronização, manter último estado canônico válido e solicitar revalidação de backend.
