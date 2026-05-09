# Arquitetura de Domínios

## Direção oficial

O `101 Service` passa a evoluir por domínios estáveis, e não por arquivos genéricos ou por histórico de experimentos de IA.

## Domínios alvo

- `core`
  - bootstrap
  - configuração
  - guards
  - logging
  - erros
- `domains/dispatch`
  - fila
  - oferta
  - aceite/recusa
  - estado do prestador
- `domains/service_tracking`
  - status consolidado
  - rota ativa
  - realtime e fallback
- `domains/payments`
  - gateways
  - payout
  - estados financeiros
- `domains/chat_notifications`
  - push
  - inbox
  - notificações locais
- `domains/profile_presence`
  - perfil
  - disponibilidade
  - presença
  - localização
- `integrations`
  - Supabase
  - FCM
  - Mapbox
  - IA/ML
  - gateways externos

## Regras de evolução

- Não criar nova regra crítica em `main.dart`, `api_service.dart` ou `notification_service.dart` se ela já tiver domínio claro.
- Arquivos legados grandes passam a ser fachada/orquestração, não destino final de código novo.
- Contratos entre UI e backend devem nascer em `domains/*/models`.
