# Backend-First Total Migration Plan

## Objetivo

Este documento define o plano oficial para transformar o `101 Service` em uma plataforma `backend-first` total, onde:

- o frontend Flutter passa a ser principalmente uma casca de apresentação;
- toda regra crítica de negócio passa a ser executada no backend;
- toda comunicação operacional entre app e backend passa a ocorrer via API JSON versionada;
- o app deixa de conhecer tabelas, transições e regras sensíveis de forma direta;
- o backend se torna a única fonte de verdade para estado, autorização, decisão e auditoria.

## Resultado Alvo

Ao final da migração:

- o app não grava mais diretamente estados críticos no banco;
- o app não reconstrói localmente fluxos críticos a partir de múltiplas tabelas;
- `ApiService` deixa de ser o centro de regra de negócio;
- `NotificationService`, `RealtimeService` e `DataGateway` passam a ser orquestradores finos;
- telas consomem `screen state`, `resource state` e `command responses` vindos do backend;
- toda mutação importante acontece através de endpoints autenticados e auditáveis;
- o backend responde sempre em JSON padronizado e versionado.

## Princípios Obrigatórios

1. Backend é a única autoridade de negócio.
2. Frontend não decide transição crítica de estado.
3. Frontend não escreve diretamente em tabelas operacionais críticas.
4. Toda operação importante usa contrato JSON versionado.
5. JWT é obrigatório para qualquer rota autenticada.
6. Role, ownership, idempotência e estado atual são validados no backend.
7. Toda mutação crítica gera evento de auditoria.
8. Realtime e push entregam eventos; snapshots oficiais vêm do backend.
9. Compatibilidade visual do app atual deve ser preservada durante a migração.
10. A convivência entre lógica antiga e nova deve ser curta e explicitamente planejada.

## Arquitetura Alvo

```text
Flutter App
  -> Features (UI)
  -> Controllers / ViewModels
  -> API Client JSON
  -> HTTPS/TLS

Backend API
  -> Auth Middleware
  -> Validation Middleware
  -> Authorization / Ownership
  -> Domain Services / Use Cases
  -> Repositories
  -> Postgres / Supabase
```

## Papel do Supabase

O Supabase continua relevante, mas com papel mais disciplinado:

- `Auth`: emissão e gestão de JWT / sessão
- `Postgres`: persistência e consultas
- `Storage`: mídia e anexos
- `Realtime`: broadcast e notificação de eventos
- `Edge Functions`: compatibilidade transitória e rotas específicas quando fizer sentido

O Supabase deixa de ser usado como "API informal" pelo app para fluxos críticos.

## Responsabilidades do Frontend no Estado Final

O frontend deve:

- renderizar interfaces;
- manter estado local de UX;
- enviar intenção de ação ao backend;
- exibir resultado, erro e loading;
- consumir snapshots e payloads JSON;
- manter compatibilidade visual e responsividade;
- realizar apenas validações locais de usabilidade.

O frontend não deve:

- decidir aceite oficial de dispatch;
- decidir transição canônica de status;
- calcular regra financeira final;
- escolher próximo prestador;
- concluir cancelamento com efeito de negócio;
- atualizar diretamente status crítico em tabelas;
- consultar várias tabelas operacionais para reconstruir verdade de uma tela.

## Responsabilidades do Backend no Estado Final

O backend deve:

- validar JWT;
- resolver identidade do usuário com base no token;
- validar role e ownership;
- validar payload JSON;
- validar pré-condições de estado;
- aplicar regras de negócio;
- garantir idempotência em operações críticas;
- persistir mudanças;
- registrar eventos e auditoria;
- responder com JSON padronizado;
- materializar snapshots de tela e estado operacional.

## Segurança

### Transporte

- todo tráfego em produção deve ocorrer via `HTTPS/TLS`;
- nenhum endpoint sensível deve aceitar downgrade de segurança.

### Autenticação

- o app envia o JWT do Supabase em `Authorization: Bearer <token>`;
- o backend valida assinatura, expiração e claims do token;
- o backend nunca confia em `user_id` informado apenas no payload.

### Autorização

- toda rota autenticada valida:
  - usuário autenticado
  - role
  - ownership
  - escopo da ação

### Idempotência

Operações como:

- aceite e recusa de oferta
- criação de intent de pagamento
- confirmação de pagamento
- cancelamento
- saque
- criação de booking

devem exigir `idempotency_key`.

### Auditoria

Toda mutação crítica deve gerar evento com:

- actor
- role
- target entity
- action
- previous state
- next state
- correlation id
- timestamp
- source (`app`, `worker`, `webhook`, `admin`)

### Criptografia Adicional

Quando houver necessidade concreta, aplicar criptografia em repouso para:

- documento pessoal
- campos bancários sensíveis
- payloads altamente sensíveis

Na maior parte do sistema, `TLS + JWT + autorização server-side + RLS/ownership + auditoria` é a base principal de segurança.

## Contrato Padrão de Resposta

### Sucesso

```json
{
  "success": true,
  "data": {},
  "meta": {},
  "errors": []
}
```

### Erro

```json
{
  "success": false,
  "data": null,
  "meta": {},
  "errors": [
    {
      "code": "SERVICE_STATUS_INVALID",
      "message": "Transição inválida para o estado atual."
    }
  ]
}
```

## Estrutura Alvo do Backend

```text
backend-api/
  src/
    config/
    middleware/
    shared/
      errors/
      http/
      security/
      utils/
    modules/
      auth/
      profile/
      home/
      services/
      dispatch/
      tracking/
      scheduling/
      payments/
      chat/
      notifications/
      provider-presence/
      remote-ui/
    app.ts
    server.ts
  prisma/
  tests/
    unit/
    integration/
    e2e/
```

## Estrutura Interna de Cada Módulo

```text
module/
  controller.ts
  service.ts
  repository.ts
  dto.ts
  schema.ts
  mapper.ts
```

## Contratos v1 por Domínio

### Auth

- `GET /api/v1/auth/bootstrap`
- `POST /api/v1/auth/logout`
- `GET /api/v1/profile/me`
- `PATCH /api/v1/profile/me`

Responsabilidades:

- resolver identidade inicial
- informar role, onboarding state, flags, permissões e tela inicial

### Home

- `GET /api/v1/home/client`
- `GET /api/v1/home/provider`

Responsabilidades:

- materializar estado da home
- banners
- serviço ativo
- ações rápidas
- disponibilidade operacional
- blocos remotos e fallback

### Services

- `GET /api/v1/services/{serviceId}`
- `POST /api/v1/services/{serviceId}/transition`
- `POST /api/v1/services/{serviceId}/cancel`
- `POST /api/v1/services/{serviceId}/complete`

Responsabilidades:

- status canônico
- transições válidas
- ownership
- auditoria

### Dispatch

- `GET /api/v1/dispatch/offers/active`
- `GET /api/v1/dispatch/offers/{offerId}`
- `POST /api/v1/dispatch/offers/{offerId}/accept`
- `POST /api/v1/dispatch/offers/{offerId}/reject`

Responsabilidades:

- fila
- timeout
- concorrência
- lock operacional
- encerramento de rodada

### Tracking

- `GET /api/v1/tracking/{serviceId}`
- `POST /api/v1/tracking/{serviceId}/refresh`

Responsabilidades:

- snapshot operacional consolidado
- rota ativa
- etapa atual
- pagamentos pendentes
- chat, timeline, ETA e indicadores

### Scheduling

- `GET /api/v1/providers/{providerId}/schedule`
- `PUT /api/v1/providers/{providerId}/schedule`
- `GET /api/v1/providers/{providerId}/availability`
- `GET /api/v1/providers/{providerId}/next-available-slot`
- `POST /api/v1/bookings/intents`
- `POST /api/v1/bookings/confirm`

Responsabilidades:

- agenda oficial
- exceções
- slot availability
- booking intent
- confirmação de reserva

### Payments

- `POST /api/v1/payments/intents`
- `GET /api/v1/payments/service/{serviceId}`
- `POST /api/v1/payments/confirm`
- `POST /api/v1/payments/withdrawals`
- `GET /api/v1/payments/wallet`

Responsabilidades:

- estados financeiros canônicos
- integração com gateway
- idempotência
- webhook safety

### Provider Presence

- `POST /api/v1/provider-presence/toggle`
- `POST /api/v1/provider-presence/heartbeat`
- `GET /api/v1/provider-presence/status`

Responsabilidades:

- disponibilidade operacional
- heartbeat
- última localização útil
- estado de despacho

### Chat

- `GET /api/v1/chats/{serviceId}`
- `POST /api/v1/chats/{serviceId}/messages`
- `GET /api/v1/chats/{serviceId}/participants`

Responsabilidades:

- participantes canônicos
- mensagens
- ownership
- media references

### Notifications

- `GET /api/v1/notifications/inbox`
- `POST /api/v1/notifications/{id}/read`

Responsabilidades:

- inbox
- estado de leitura
- payload canônico

### Remote UI

- `POST /api/v1/remote-ui/screens/{screenKey}`
- `POST /api/v1/remote-ui/actions`

Responsabilidades:

- screen state
- command responses
- fallback controlado
- rollout por tela/role/plataforma

## Estratégia de Migração

## Onda 1 - Fundação de Backend API

Objetivo:

- criar `backend-api`
- definir auth middleware
- definir envelope JSON padrão
- definir validação de schema
- definir logging e auditoria básicos

Entregas:

- app e server
- middleware de autenticação
- middleware de erro
- middleware de validação
- padrão de resposta
- correlation id

## Onda 2 - Auth, Bootstrap e Profile

Objetivo:

- mover bootstrap inicial do app para backend

Entregas:

- `GET /api/v1/auth/bootstrap`
- `GET /api/v1/profile/me`
- front passa a resolver tela inicial pelo backend

Remover do frontend:

- decisões espalhadas de bootstrap em `main.dart` e `ApiService`

## Onda 3 - Home, Services e Tracking

Objetivo:

- transformar home e tracking em snapshots orientados por backend

Entregas:

- `GET /api/v1/home/client`
- `GET /api/v1/home/provider`
- `GET /api/v1/tracking/{serviceId}`
- `POST /api/v1/services/{id}/transition`

Remover do frontend:

- recomposição manual de home
- recomposição manual de tracking
- updates diretos de status crítico

## Onda 4 - Dispatch, Notifications e Realtime

Objetivo:

- consolidar o fluxo de oferta no backend

Entregas:

- `GET /api/v1/dispatch/offers/active`
- `POST /api/v1/dispatch/offers/{id}/accept`
- `POST /api/v1/dispatch/offers/{id}/reject`
- eventos canônicos de realtime

Remover do frontend:

- decisão local de concorrência
- leitura espalhada de fila
- timeout não-canônico

## Onda 5 - Scheduling e Fixed Booking

Objetivo:

- levar agenda, disponibilidade e booking para backend

Entregas:

- endpoints de schedule e availability
- booking intent e confirmação
- snapshot de estado de agendamento

Remover do frontend:

- mutações diretas de agenda
- confirmação de booking feita por lógica local

## Onda 6 - Payments e Wallet

Objetivo:

- transformar pagamentos em domínio server-first

Entregas:

- intents
- confirmação
- saque
- carteira
- webhook flow

Remover do frontend:

- lógica financeira espalhada
- updates financeiros diretos

## Estratégia de Refatoração do Frontend

O frontend deve migrar para o seguinte padrão:

```text
Feature Screen
  -> Controller / ViewModel
  -> API Client
  -> DTO Mapper
  -> View State
  -> Widgets
```

### Regras

- `features/` não chama Supabase diretamente para fluxo crítico;
- `domains/` define request/response/view state;
- `integrations/` implementa client HTTP;
- `services/` legados viram wrappers transitórios;
- o app não fala mais diretamente com tabela para regra crítica.

## Estratégia para `ApiService`

`ApiService` deve ser desmontado por domínio.

Cada método deve ser classificado em:

- `mover para backend-api`
- `mover para integration/http-client`
- `mover para usecase`
- `deletar`
- `manter apenas como compatibilidade transitória`

Objetivo final:

- `ApiService` deixa de conter regra de negócio;
- no máximo vira fachada fina temporária sobre clientes HTTP especializados.

## Estratégia para `NotificationService`

Objetivo final:

- ficar responsável apenas por:
  - integração FCM
  - permissão
  - roteamento de evento
  - exibição local

Não deve decidir:

- dispatch order
- timeout oficial
- aceite/concorrência
- transição crítica de serviço

## Estratégia para `RealtimeService`

Objetivo final:

- ser apenas transporte e roteamento de eventos;
- não ser dono de semântica de negócio;
- quando necessário, receber evento e solicitar snapshot atualizado via API.

## Estratégia para `DataGateway`

Objetivo final:

- deixar de ser “ponto único de verdade” para negócio crítico;
- virar adapter temporário para leituras locais/caches não críticos;
- tudo que for verdade operacional deve vir do backend API.

## Critérios de Corte do Frontend

Uma área só é considerada migrada quando:

1. a UI lê estado oficial de API JSON;
2. a UI envia ações para API JSON;
3. não há update direto em tabela crítica;
4. não há regra crítica duplicada no app;
5. há erro padronizado vindo do backend;
6. há auditoria para ações críticas.

## Política de Compatibilidade

Durante a migração:

- o visual do app deve ser preservado;
- widgets existentes podem continuar;
- a origem dos dados e das ações deve mudar;
- fallbacks locais devem ser explicitamente temporários;
- cada fallback precisa ter critério de remoção definido.

## Primeiros Alvos Recomendados

Se a execução começar imediatamente, a ordem recomendada é:

1. `auth/bootstrap/profile`
2. `home`
3. `tracking`
4. `service status transition`
5. `dispatch`
6. `notifications/realtime`
7. `scheduling`
8. `payments`
9. `presence`

## Definição Executiva

Este plano assume uma decisão forte:

- o projeto atual entra oficialmente em convergência `backend-first total`;
- toda regra nova crítica nasce no backend;
- o frontend passa a ser mantido como camada de apresentação e envio de intenção;
- contratos JSON versionados passam a ser a interface principal entre app e backend.

Essa decisão deve orientar todas as próximas implementações e revisões arquiteturais.
