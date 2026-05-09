# Política de Convergência de Legado

## Regra geral

Fluxos antigos podem continuar temporariamente, mas só atrás de camada de compatibilidade explícita.

## Trilha oficial atual

- dispatch sequencial:
  - `dispatch`
  - `dispatch-queue`
  - `push-notifications`
- oferta do prestador:
  - tipo canônico `service_offer`

## Fluxos tratados como legado

- `offer`
- `assignment`
- `notify-drivers`
- aliases antigos de payload e status

## Como evoluir

- consumidores novos devem apontar para a trilha oficial;
- adaptadores temporários devem ser pequenos e documentados;
- legado sem consumidor deve ser removido, não preservado indefinidamente.
