# Backend-First Execution Roadmap

## Objetivo

Este documento converte a estratégia `backend-first total` em um projeto executável por etapas.

Meta final:

- app Flutter 100% funcional via API JSON;
- frontend atuando principalmente como casca de apresentação;
- toda regra crítica de negócio centralizada no backend;
- segurança, auditoria, ownership e transições críticas validadas no servidor;
- aparência e experiência do app atual preservadas durante a migração.

## Resultado Final Esperado

Ao final da última etapa:

- o app não faz mais mutações críticas diretas no banco;
- o app não conhece tabelas operacionais como fonte principal;
- o app consome snapshots e comandos da API;
- o backend entrega contratos estáveis para `auth`, `home`, `tracking`, `dispatch`, `scheduling`, `payments`, `presence`, `chat` e `notifications`;
- o sistema inteiro opera com `JWT + HTTPS + authorization + idempotency + audit log`.

## Regra do Projeto

Cada etapa precisa entregar:

1. backend funcional do domínio alvo;
2. contrato JSON documentado;
3. integração do app com a nova API;
4. remoção ou isolamento do caminho legado correspondente;
5. validação mínima de funcionamento.

Uma etapa só é considerada concluída quando o app já usa a API nova naquele escopo.

## Etapa 0 - Fundação e Governança

### Objetivo

Preparar a fundação do novo backend e a disciplina da migração.

### Entregas

- plano arquitetural oficial
- plano de migração backend-first total
- roadmap por etapas
- `backend-api` inicial criado
- middleware de autenticação
- envelope JSON padrão
- tratamento de erro
- base de contexto por request

## Etapa 1 - Fundação Técnica do Backend API

### Objetivo

Subir a estrutura operacional mínima do backend novo.

### Escopo

- `Express + TypeScript`
- config/env
- auth middleware
- error handler
- response envelope
- admin supabase client
- módulos iniciais: `auth`, `profile`, `home`

### Endpoints

- `GET /health`
- `GET /api/v1/auth/bootstrap`
- `GET /api/v1/profile/me`
- `GET /api/v1/home/client`
- `GET /api/v1/home/provider`

### Critério de Conclusão

- backend sobe localmente
- `typecheck` passa
- endpoints iniciais respondem

## Etapa 2 - Bootstrap, Sessão e Perfil via API

### Objetivo

Fazer o app depender do backend novo para decidir bootstrap, sessão e perfil inicial.

### Escopo Backend

- evoluir `GET /api/v1/auth/bootstrap`
- evoluir `GET /api/v1/profile/me`
- incluir:
  - `authenticated`
  - `role`
  - `is_medical`
  - `is_fixed_location`
  - `register_step`
  - `next_route`
  - `feature_flags`

### Escopo Frontend

- criar client HTTP base
- criar DTOs de bootstrap/profile
- ligar `main.dart` / bootstrap ao novo endpoint
- reduzir dependência de bootstrap em `ApiService`

### Critério de Conclusão

- app decide rota inicial com base no backend
- perfil inicial vem da API nova

## Etapa 3 - Home do Cliente e do Prestador via Snapshot

### Objetivo

Transformar a home em tela montada por snapshot do backend.

### Escopo Backend

- consolidar `GET /api/v1/home/client`
- consolidar `GET /api/v1/home/provider`
- incluir:
  - banner states
  - active service summary
  - pending payments
  - upcoming appointments
  - quick actions
  - remote sections

### Escopo Frontend

- criar mappers `HomeResponse -> HomeViewState`
- adaptar `HomeScreen`, `ProviderHome*` para consumir snapshot
- manter widgets atuais, trocar origem de dados

## Etapa 4 - Services e Tracking 100% Server-Driven

### Objetivo

Centralizar estado do serviço e tracking no backend.

### Escopo Backend

- `GET /api/v1/services/{serviceId}`
- `GET /api/v1/tracking/{serviceId}`
- `POST /api/v1/services/{serviceId}/transition`

### Escopo Frontend

- adaptar páginas de tracking e serviço ativo
- parar de reinterpretar status localmente
- parar de atualizar status crítico direto em tabela

## Etapa 5 - Dispatch e Ofertas via API

### Objetivo

Levar o fluxo de oferta e aceite/recusa para backend-first total.

### Escopo Backend

- `GET /api/v1/dispatch/offers/active`
- `GET /api/v1/dispatch/offers/{offerId}`
- `POST /api/v1/dispatch/offers/{offerId}/accept`
- `POST /api/v1/dispatch/offers/{offerId}/reject`

## Etapa 6 - Notifications e Realtime como Transporte

### Objetivo

Reduzir `notification_service.dart` e `realtime_service.dart` a transporte/orquestração.

### Escopo Backend

- eventos canônicos
- payloads estáveis
- inbox e leitura
- gatilhos de refresh por recurso

## Etapa 7 - Scheduling e Fixed Booking via API

### Objetivo

Migrar agenda, disponibilidade e reserva fixa para backend autoritativo.

### Escopo Backend

- `GET /api/v1/providers/{providerId}/schedule`
- `PUT /api/v1/providers/{providerId}/schedule`
- `GET /api/v1/providers/{providerId}/availability`
- `GET /api/v1/providers/{providerId}/next-available-slot`
- `POST /api/v1/bookings/intents`
- `POST /api/v1/bookings/confirm`

## Etapa 8 - Payments, Wallet e Payouts

### Objetivo

Centralizar todo o domínio financeiro no backend.

### Escopo Backend

- `POST /api/v1/payments/intents`
- `POST /api/v1/payments/confirm`
- `GET /api/v1/payments/service/{serviceId}`
- `POST /api/v1/payments/withdrawals`
- `GET /api/v1/payments/wallet`

## Etapa 9 - Presence, Availability e Heartbeat

### Objetivo

Tornar presença operacional uma responsabilidade clara do backend.

### Escopo Backend

- `POST /api/v1/provider-presence/toggle`
- `POST /api/v1/provider-presence/heartbeat`
- `GET /api/v1/provider-presence/status`

## Etapa 10 - Chat e Participantes Canônicos

### Objetivo

Levar chat e participantes para contratos estáveis da API.

### Escopo Backend

- `GET /api/v1/chats/{serviceId}`
- `POST /api/v1/chats/{serviceId}/messages`
- `GET /api/v1/chats/{serviceId}/participants`

## Etapa 11 - Remote UI Expandida e Comandos Totais

### Objetivo

Transformar o app em casca operacional mais explícita usando snapshots e comandos server-driven.

### Escopo Backend

- expandir `remote-ui`
- respostas por `screen`, `sections`, `actions`, `effects`
- ações críticas resolvidas no backend

## Etapa 12 - Encerramento do Legado Interno

### Objetivo

Desativar o papel central do legado no frontend.

### Escopo

- desmontar `ApiService` como centro do sistema
- reduzir `NotificationService`
- reduzir `RealtimeService`
- reduzir `DataGateway`
- remover escrita direta crítica restante

## Etapa Final - App 100% Funcional via API

### Definição de Conclusão

O projeto só termina quando:

- login, bootstrap e perfil vêm da API
- home vem da API
- tracking vem da API
- dispatch vem da API
- agenda e booking vêm da API
- pagamentos vêm da API
- presença vem da API
- chat e notificações usam contratos canônicos
- frontend não executa mais regra crítica como dono da decisão

## Ordem Recomendada de Execução

1. Etapa 1
2. Etapa 2
3. Etapa 3
4. Etapa 4
5. Etapa 5
6. Etapa 6
7. Etapa 7
8. Etapa 8
9. Etapa 9
10. Etapa 10
11. Etapa 11
12. Etapa 12

## Indicador de Sucesso

Se ao final a pergunta “de onde vem a regra?” puder ser respondida com “do backend” para qualquer fluxo crítico, então a migração foi concluída corretamente.
