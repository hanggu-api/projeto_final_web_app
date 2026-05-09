# Master Implementation Plan - Projeto 101 Modular

## Objetivo

Este documento define o plano oficial de execucao do novo Projeto 101 Modular como um projeto do zero.

Diretriz obrigatoria:

- o novo projeto nao deve ser adaptacao tecnica do sistema atual;
- o sistema atual deve ser usado somente como inspiracao funcional;
- o legado serve para descoberta de regras de negocio, fluxos reais, excecoes e requisitos;
- a nova arquitetura deve nascer limpa, modular, testavel e independente desde o primeiro commit.

## Resultado esperado

Ao final da execucao deste plano, o projeto deve ter:

- um novo workspace isolado do legado;
- um novo app Flutter;
- um novo backend Supabase local;
- contratos canonicos entre app e backend;
- modularizacao por dominio desde a fundacao;
- testes desde as primeiras camadas;
- homologacao funcional comparativa contra o produto antigo, sem dependencia tecnica dele.

## Papel do legado

### O que o legado pode fornecer

- referencia de fluxo de cliente, prestador e admin;
- regras de negocio ja descobertas;
- edge cases reais;
- nomenclaturas de eventos e estados que merecem revisao;
- insumos para checklist de paridade funcional.

### O que o legado nao pode fornecer

- base estrutural do novo app;
- servicos compartilhados;
- contratos copiados sem revisao;
- schema herdado sem reconcepcao;
- `api_service.dart`, `notification_service.dart`, `main.dart` ou qualquer arquivo como fundacao tecnica do novo projeto.

## Fontes funcionais de referencia

Usar como referencia de negocio:

- `docs/domain-architecture.md`
- `docs/dispatch-flow.md`
- `docs/tracking-domain.md`
- `docs/payments-domain.md`
- `docs/notifications-domain.md`
- `docs/presence-profile-domain.md`

## Principios de execucao

1. O novo projeto nasce do zero.
2. O legado e referencia funcional, nao base tecnica.
3. Backend e fonte de verdade.
4. UI nao decide regra de negocio critica.
5. Toda regra nasce no dominio correto.
6. Toda mudanca de banco nasce com RLS, indices, contratos e validacao.
7. Realtime e preferencial; polling e fallback explicito.
8. Nada de pasta generica virando deposito de regra solta.
9. Qualquer reaproveitamento conceitual do legado deve ser reescrito sob a nova arquitetura.

## Regra de camadas

Arquitetura obrigatoria:

```text
features -> domains -> integrations
```

Regras:

- `features` nunca acessa Supabase, Firebase, mapas, storage ou gateway de pagamento diretamente;
- `features` consome `UseCase`, `Repository` ou contrato do dominio;
- `domains` define contratos, entidades, estados e casos de uso;
- `integrations` implementa acesso concreto a servicos externos;
- o backend continua como autoridade final mesmo quando existir regra no dominio do app.

## Estrategia oficial

Construir um novo produto paralelo com:

- arquitetura preparada para multiapp;
- novo workspace;
- novo projeto Flutter;
- nova estrutura `lib/`;
- novo projeto Supabase local;
- camada de contratos de backend;
- novas migrations;
- novas edge functions;
- nova suite de testes;
- nova trilha de release.

O sistema atual entra apenas como apoio de descoberta e homologacao.

## Estrutura alvo

```text
projeto-central-modular/
  apps/
    client_app/
    provider_app/
    admin_app/
    manager_app/
  packages/
    core_ui/
    core_domain/
    core_security/
    core_network/
  backend/
    supabase/
    edge_functions/
    contracts/
    openapi/
  contracts/
    v1/
      auth/
      orders/
      dispatch/
      tracking/
      payments/
      notifications/
  docs/
    adr/
```

## Ownership

- `apps/`: composicao de produto por papel de usuario.
- `packages/core_ui`: design system, tokens, widgets compartilhados.
- `packages/core_domain`: entidades, casos de uso, contratos e estados.
- `packages/core_security`: sessao, guards, storage seguro, politicas de acesso no app.
- `packages/core_network`: clients, serializacao, transporte e adapters de contratos.
- `backend/contracts`: contratos de backend e fronteiras estaveis de payload.
- `contracts/v1`: contratos JSON versionados consumidos pelos apps.
- `docs/adr`: decisoes arquiteturais registradas.

## Regra multiapp

O projeto deve avaliar e decidir explicitamente entre:

- monoapp modular;
- multiapp com packages compartilhados.

Direcao recomendada:

- multiapp se cliente, prestador, admin e manager tiverem jornadas, releases ou permisos significativamente diferentes;
- monoapp apenas se a separacao operacional nao compensar o custo.

Essa decisao deve ser registrada em ADR antes da fundacao definitiva do workspace.

## Regra de contratos de backend

Mesmo usando Supabase, os apps nao devem conhecer tabelas demais nem operar diretamente sobre elas para fluxos criticos.

Camada obrigatoria:

```text
backend/
  supabase/
  edge_functions/
  contracts/
  openapi/
```

Os apps devem consumir contratos estaveis, e nao payloads ad hoc.

## Decisao arquitetural de API

O backend sera tratado como uma API JSON oficial.

Diretrizes:

- todo app Flutter envia requisicoes JSON para contratos versionados;
- o backend valida autenticacao, autorizacao, payload, ownership, estado atual e idempotencia;
- o backend responde sempre em JSON padronizado;
- toda chamada usa HTTPS/TLS;
- criptografia adicional manual so entra para campos realmente sensiveis quando houver necessidade concreta.

## Fluxo seguro recomendado

```text
Flutter App
  ↓ HTTPS/TLS
API JSON / Edge Function
  ↓ valida JWT
  ↓ valida schema JSON
  ↓ valida role/permissao
  ↓ valida ownership
  ↓ valida estado atual
  ↓ executa regra
  ↓ grava evento/audit log
  ↓ responde JSON
Supabase/Postgres
```

## Responsabilidades criticas do backend

O app Flutter nao decide:

- qual prestador recebe pedido;
- preco final;
- status financeiro;
- cancelamento com multa;
- repasse;
- aceite valido;
- transicao critica de status.

Tudo isso deve passar por:

- RPC segura;
- Edge Function;
- trigger controlada;
- tabela de eventos.

Regra complementar:

- nenhuma operacao pode confiar apenas no ID enviado pelo cliente;
- toda leitura e escrita critica deve validar ownership, role e estado atual do recurso no backend.

## Fase A - Descoberta funcional

### Objetivo

Extrair do produto atual apenas o que precisa existir no novo projeto.

### Entregaveis

- inventario funcional;
- mapa de atores;
- lista de jornadas criticas;
- glossario de estados;
- matriz de riscos do legado que nao podem se repetir.

### Tarefas

1. Mapear jornadas de cliente, prestador e admin.
2. Identificar fluxos obrigatorios para MVP e para paridade.
3. Catalogar estados, excecoes e integrações do sistema atual.
4. Registrar decisoes do que sera mantido, simplificado ou descartado.
5. Criar checklist de paridade funcional.

### Criterios de aceite

- equipe sabe o que o novo sistema precisa fazer;
- requisitos dependem de negocio e nao da implementacao antiga;
- existe clareza do que nao sera herdado.

## Fase S - Seguranca e threat model

### Objetivo

Tornar seguranca parte da fundacao, e nao acabamento tardio.

### Entregaveis

- checklist de ameacas por dominio;
- politica de RLS por tabela publica;
- estrategia de validacao de payload;
- estrategia de idempotencia;
- politica de logs seguros;
- politica de storage segura.

### Checklist obrigatorio

- RLS em todas as tabelas publicas;
- teste automatizado de RLS;
- nenhuma chave sensivel no Flutter;
- validacao de payload em Edge Functions;
- rate limit em acoes criticas;
- idempotencia em pagamentos, webhooks e dispatch;
- logs sem dados sensiveis;
- storage com policies;
- protecao contra Broken Object Level Authorization.

### Checklist mobile

- armazenamento seguro de tokens;
- protecao contra logs sensiveis;
- TLS obrigatorio;
- validacao de sessao;
- avaliacao de deteccao de root/jailbreak quando fizer sentido;
- nenhum segredo no app;
- ofuscacao no release.

### Criterios de aceite

- regras de acesso estao documentadas e testadas;
- operacoes sensiveis tem protecoes claras;
- o novo projeto nao depende de "seguranca por convencao".

## Fase D - Decisao de arquitetura multiapp

### Objetivo

Definir cedo se a plataforma sera monoapp modular ou multiapp com packages compartilhados.

### Entregaveis

- ADR da decisao;
- criterios de separacao entre apps;
- estrategia de compartilhamento via `packages/`;
- matriz de ownership por app.

### Criterios de aceite

- decisao de arquitetura registrada;
- workspace futuro nao depende de improviso estrutural;
- custo operacional de cada app ficou explicito.

## Fase B0 - Infra local e backend base

### Objetivo

Criar o backend local do novo projeto do zero.

### Entregaveis

- `supabase/` inicializado no novo workspace;
- ambiente local executando com `supabase start`;
- auth, db, realtime e functions habilitados;
- seed minima reproduzivel;
- documento de bootstrap local.

### Tarefas

1. Inicializar `supabase/`.
2. Configurar `config.toml` do novo projeto.
3. Subir stack local com `supabase start`.
4. Definir rotina de reset com `supabase db reset`.
5. Criar seed minima:
   - papeis
   - categorias
   - profissoes
   - usuarios de teste
   - perfis base
6. Documentar portas, servicos e pre-requisitos.

### Criterios de aceite

- qualquer dev sobe o backend local do zero;
- seed prepara ambiente minimo de teste;
- nenhuma dependencia de producao e necessaria para comecar.

## Fase B1 - Schema canonico

### Objetivo

Desenhar o schema do zero a partir do dominio, e nao a partir das tabelas antigas.

### Estruturas minimas

- `organizations`
- `addresses`
- `profiles`
- `user_roles`
- `service_categories`
- `service_pricing_rules`
- `service_quotes`
- `provider_profiles`
- `provider_documents`
- `provider_verifications`
- `client_profiles`
- `provider_presence`
- `provider_locations`
- `service_requests`
- `service_assignments`
- `service_status_transitions`
- `service_events`
- `payment_transactions`
- `payment_events`
- `notification_deliveries`
- `notification_events`
- `dispatch_events`
- `audit_logs`
- `device_tokens`
- `chat_threads`
- `chat_messages`

### Metadados obrigatorios por tabela critica

- `id`
- `created_at`
- `updated_at`
- `created_by`
- `tenant_id` quando houver caminho para multiempresa
- indice para consultas principais
- policy RLS testada

### Regras obrigatorias

- RLS em toda tabela exposta;
- `update` com policy de `select` correspondente;
- nada de autorizacao com metadata editavel;
- functions privilegiadas fora de schema exposto quando necessario;
- indices nas consultas criticas, realtime e geolocalizacao.

### Tarefas

1. Levantar entidades do dominio.
2. Modelar agregados e relacoes.
3. Criar migrations pequenas por dominio.
4. Padronizar status, ids e timestamps.
5. Criar trilha de eventos de negocio.
6. Garantir idempotencia das operacoes criticas.

### Criterios de aceite

- schema atende auth, dispatch, tracking, pagamentos e notificacoes;
- nomes e relacoes fazem sentido no dominio novo;
- nao existe dependencia conceitual de tabela antiga.

## Fase B2 - RLS e testes de acesso

### Objetivo

Garantir que seguranca de dados nao fique implícita nem dependa de comportamento do app.

### Entregaveis

- policies por tabela publica;
- testes automatizados de RLS;
- validacoes de ownership e role;
- protecao contra acesso cruzado entre usuarios.

### Criterios de aceite

- tabelas publicas possuem RLS testado;
- cenarios de Broken Object Level Authorization estao cobertos;
- operacoes criticas falham com seguranca quando o ator nao tem permissao.

## Fase B3 - Edge Functions e contratos backend

### Objetivo

Concentrar operacoes sensiveis e integracoes no backend novo.

### Functions esperadas

- dispatch
- dispatch-queue
- mp-webhook
- mp-pix-webhook
- push-notifications
- auth-profile-bootstrap
- payment-simulation-local

### Modelo de autoridade operacional

Operacoes criticas devem ser resolvidas pelo backend usando:

- RPC segura;
- Edge Function;
- trigger;
- tabela de eventos;
- verificacao idempotente.

### Regras

- payloads documentados;
- idempotencia para webhooks;
- logs com correlation id;
- sem segredo sensivel no cliente.

### Tarefas

1. Definir contratos de entrada e saida.
2. Separar o que sera RPC, trigger e Edge Function.
3. Criar simuladores locais para pagamentos e notificacoes.
4. Definir erros esperados e observabilidade.
5. Garantir validacao de payload, role, ownership, estado atual e idempotencia em cada function critica.

### Criterios de aceite

- cliente chama contratos pequenos e previsiveis;
- backend novo concentra regra sensivel;
- falhas sao rastreaveis.

## Fase C0 - Contratos JSON versionados

### Objetivo

Evitar payloads soltos e permitir evolucao segura entre apps e backend.

### Estrutura

```text
contracts/
  v1/
    auth/
    orders/
    dispatch/
    tracking/
    payments/
    notifications/
```

### Regra

Nenhum app deve consumir payload solto em fluxo critico.

### Exemplo de envelope

```json
{
  "version": "v1",
  "type": "service_request_created",
  "request_id": "...",
  "client_id": "...",
  "status": "pending_dispatch"
}
```

### Criterios de aceite

- contratos estao versionados;
- apps e backend compartilham definicoes claras;
- mudancas de payload podem ser validadas e evoluidas com seguranca.

## Fase API - Contratos JSON seguros

### Objetivo

Expor o backend como API JSON segura, padronizada e versionada.

### Regras obrigatorias

1. Toda entrada deve ser JSON validado por schema.
2. Toda saida deve seguir envelope JSON padronizado.
3. Toda chamada deve usar HTTPS/TLS.
4. Toda chamada autenticada deve enviar JWT.
5. O backend deve validar role, ownership e estado atual do recurso.
6. Nenhuma operacao critica pode confiar apenas no ID enviado pelo cliente.
7. Toda operacao critica deve ter `request_id` para idempotencia.
8. Toda resposta de erro deve usar codigo padronizado.
9. Logs nao podem conter token, senha, documento, cartao ou dado sensivel.
10. Payloads sensiveis podem usar criptografia adicional campo a campo quando realmente necessario.

### Exemplo de request

```json
{
  "version": "v1",
  "request_id": "uuid",
  "device_id": "uuid",
  "action": "create_service_request",
  "payload": {
    "category_id": "uuid",
    "pickup_address_id": "uuid",
    "description": "texto"
  }
}
```

### Exemplo de response de sucesso

```json
{
  "success": true,
  "request_id": "uuid",
  "data": {
    "service_request_id": "uuid",
    "status": "pending_dispatch"
  },
  "error": null
}
```

### Exemplo de response de erro

```json
{
  "success": false,
  "request_id": "uuid",
  "data": null,
  "error": {
    "code": "FORBIDDEN",
    "message": "Voce nao tem permissao para esta operacao."
  }
}
```

### Obrigatorio por padrao

- HTTPS/TLS em 100% das chamadas
- JWT no header `Authorization`
- RLS no banco
- validacao de payload
- logs sem dados sensiveis
- nenhuma chave secreta no Flutter

### Opcional para dados muito sensiveis

- criptografia campo a campo
- assinatura HMAC do payload
- nonce/timestamp contra replay attack
- device binding
- mTLS para APIs administrativas

### Criterios de aceite

- backend responde com envelope JSON consistente;
- operacoes criticas sao validaveis e idempotentes;
- transporte criptografado via TLS e tratado como padrao obrigatorio;
- criptografia adicional so entra onde houver justificativa real.

## Fase F0 - Flutter workspace

### Objetivo

Criar o novo app Flutter sem herdar estrutura ruim do antigo.

### Entregaveis

- novo projeto Flutter;
- bootstrap controlado;
- navegacao centralizada;
- tema base;
- configuracao de ambiente.

### Tarefas

1. Criar o projeto Flutter novo.
2. Estruturar `core`, `domains`, `integrations` e `features`.
3. Configurar Riverpod, GoRouter, Supabase e Firebase.
4. Criar `AppEnvironment`.
5. Manter `main.dart` pequeno desde o inicio.
6. Garantir que nenhuma tela acesse integration concreta sem passar pelo dominio.

### Criterios de aceite

- arquitetura nasce limpa;
- dependencias ficam em lugares previsiveis;
- app pode crescer sem cair em service global generico.

## Fase F1 - Packages compartilhados

### Objetivo

Criar base reutilizavel para multiplos apps.

### Escopo

- `core_ui`
- `core_domain`
- `core_security`
- `core_network`

### Criterios de aceite

- compartilhamento fica explicito;
- codigo comum nao depende de um app especifico;
- contratos e design system ficam centralizados.

## Fase F2 - Apps separados

### Objetivo

Estruturar os apps finais da plataforma.

### Escopo

- `client_app`
- `provider_app`
- `admin_app`
- `manager_app`

### Criterios de aceite

- cada app possui responsabilidade clara;
- dependencias compartilhadas vem de `packages/`;
- nao existe mistura de navegacao e jornada entre papeis por descuido estrutural.

## Fase 1 - Dominio Auth

### Contratos minimos

- `AuthRepository`
- `SessionRepository`
- `ProfileRepository`
- `AuthState`
- `UserRole`
- `CurrentIdentity`

### Fluxo oficial

1. usuario autentica;
2. backend garante perfil canonico;
3. app carrega identidade consolidada;
4. guards usam contrato de sessao.

### Criterios de aceite

- login e sessao independem do legado;
- roles e perfil chegam por contrato unico.

## Fase 2 - Dominio Profile/Presence

### Contratos minimos

- `ProviderPresenceRepository`
- `ProviderLocationRepository`
- `ProviderProfileRepository`
- `ProviderPresenceState`
- `ProviderAvailabilityWindow`

### Criterios de aceite

- presenca operacional e separada de perfil;
- localizacao segue politica unica;
- dispatch e tracking dependem do contrato novo.

## Fase 3 - Dominio Orders

### Objetivo

Separar o ciclo de vida do pedido da logica de dispatch.

### Contratos minimos

- `OrderRepository`
- `ServiceRequest`
- `ServiceQuote`
- `ServiceAssignment`
- `ServiceStatusTransition`
- `CreateOrderUseCase`
- `CancelOrderUseCase`

### Criterios de aceite

- pedido existe como agregado proprio;
- lifecycle do pedido nao fica misturado com match/dispatch;
- tracking e pagamentos dependem do contrato de ordem, nao do motor de oferta.

## Fase 4 - Dominio Dispatch

### Contratos minimos

- `DispatchRepository`
- `DispatchQueueItem`
- `ServiceOfferState`
- `DispatchTimelineEvent`
- `AcceptOfferUseCase`
- `RejectOfferUseCase`

### Linha de eventos recomendada

- `service_request_created`
- `quote_generated`
- `dispatch_started`
- `provider_offered`
- `provider_timeout`
- `provider_rejected`
- `provider_accepted`
- `provider_assigned`
- `provider_arrived`
- `service_started`
- `service_completed`
- `payment_confirmed`
- `service_closed`

### Criterios de aceite

- app nao decide rodada nem proximo prestador;
- backend novo orquestra o fluxo inteiro;
- UI apenas consome estados canonicos.

## Fase 5 - Dominio Service Tracking

### Contratos minimos

- `TrackingRepository`
- `ServiceStatusView`
- `TrackingSnapshot`
- `TrackingRouteState`
- `ServiceProgressState`

### Criterios de aceite

- cliente e prestador enxergam o mesmo status;
- telas nao inventam transicoes locais.

## Fase 6 - Dominio Payments

### Contratos minimos

- `PaymentRepository`
- `PaymentGateway`
- `PaymentIntent`
- `PaymentTransaction`
- `PaymentWebhookEvent`
- `PaymentSettlement`
- `ProviderPayout`
- `Refund`
- `Dispute`
- `PaymentStatus`
- `PixCharge`
- `PaymentSettlementResult`

### Criterios de aceite

- fluxo financeiro e separado do gateway;
- webhooks sao idempotentes;
- pagamentos sao testaveis localmente.

## Fase 7 - Dominio Notifications/Chat

### Contratos minimos

- `NotificationRepository`
- `NotificationEnvelope`
- `NotificationAction`
- `NotificationRouteIntent`
- `ChatInboxRepository`

### Criterios de aceite

- payloads tem contrato claro;
- toque em notificacao abre destino correto;
- notificacao nao decide regra de dispatch.

## Fase 8 - Admin, Reviews e Support

### Objetivo

Cobrir modulos operacionais e de confianca da plataforma.

### Escopo

- painel admin
- reviews
- suporte
- verificacoes de prestador
- auditoria operacional

### Criterios de aceite

- operacao administrativa nao depende de gambiarra no banco;
- reviews e suporte possuem contratos proprios;
- verificacoes de prestador ficam fora do dominio de auth basico.

## Fase 9 - UI modular e validacao funcional

### Objetivo

Construir telas novas sobre contratos novos e validar equivalencia funcional com o produto antigo.

### Ordem sugerida

1. auth/onboarding
2. dispatch provider
3. tracking cliente/prestador
4. pagamentos
5. home/search
6. perfil/presenca
7. chat/notificacoes

### Regra de construcao

Cada tela nova deve:

- consumir contratos do dominio;
- nascer sem dependencia estrutural do legado;
- ser comparada com o fluxo antigo apenas como referencia funcional;
- sair com validacao minima automatizada.

## Fase 10 - Qualidade e observabilidade

### Suite minima

- `flutter test`
- `dart analyze`
- `supabase db reset`
- testes de RLS
- testes de Edge Functions
- testes de contrato JSON
- smoke test ponta a ponta
- testes unitarios por dominio;
- testes de contrato de adapters;
- integration test com Supabase local;
- golden test para telas criticas;
- smoke tests de fluxos criticos;
- validacao de migrations e RLS;
- verificacao de edge functions.

## Fase DevOps - CI/CD

### Pipeline minima obrigatoria

- `dart analyze`
- `flutter test`
- `supabase db reset`
- teste de migrations
- teste de Edge Functions
- teste de contratos
- security lint
- build Android
- build iOS

### Criterios de aceite

- o projeto pode evoluir sem quebrar silenciosamente;
- backend, contratos e apps entram no mesmo funil de validacao;
- build de release possui minimo de confiabilidade automatizada.

### Observabilidade

- correlation id por servico;
- request id;
- user id;
- service_request_id;
- payment_id;
- event_type;
- severity;
- created_at;
- logs estruturados;
- telemetria de falhas criticas;
- trilha de eventos de negocio.

### Regras de log em Edge Functions

Cada Edge Function deve registrar:

- entrada validada;
- decisao tomada;
- resultado;
- erro padronizado.

## Fase 11 - Homologacao e release

### Objetivo

Liberar o novo sistema quando ele estiver funcionalmente pronto para substituir o antigo.

### Tarefas

1. revisar gaps contra checklist de paridade;
2. validar backend e app em staging;
3. executar smoke tests ponta a ponta;
4. definir rollout e rollback;
5. publicar o novo sistema.

### Criterios de aceite

- jornada principal funciona ponta a ponta;
- paridade funcional minima foi atingida;
- release independe tecnicamente do sistema antigo.

## Backlog priorizado

### Bloco 1 - Descoberta e seguranca

- inventario funcional
- threat model
- regras de RLS
- checklist de acesso a dados

### Bloco 2 - Criacao do novo projeto

- criar novo workspace
- criar novo app Flutter
- criar novo Supabase local
- documentar bootstrap do novo projeto

### Bloco 3 - Contratos canonicos

- auth
- presence/profile
- orders
- dispatch
- tracking
- payments
- notifications

### Bloco 4 - Fluxos criticos

- login e sessao
- criacao de pedido
- oferta do prestador
- tracking cliente
- fluxo de conclusao e pagamento

### Bloco 5 - Homologacao funcional

- comparar com fluxos antigos
- medir gaps
- fechar checklist de paridade

### Bloco 6 - Governanca tecnica

- ADRs em `docs/adr/`
- decisao multiapp documentada
- contratos versionados
- politica de CI/CD
- politica de ownership por app

## Definition of Done por entrega

- contrato do dominio definido;
- implementacao integrada;
- backend ajustado quando necessario;
- contrato JSON definido quando aplicavel;
- ADR criada ou atualizada quando a decisao for arquitetural;
- logs/erros padronizados;
- documentacao atualizada;
- analise estatica executada;
- validacao funcional registrada.

## Anti-padroes proibidos

- copiar servico legado para dentro do projeto novo;
- criar service global generico como deposito de regra;
- misturar status financeiro e operacional;
- duplicar timeout de backend na UI como verdade;
- criar migration enorme sem ownership por dominio;
- levar bug conceitual do legado para o projeto novo por inercia.

## Prompt operacional para usar no Codex

```text
Trabalhe no novo Projeto 101 Modular usando `docs/master-implementation-plan.md` como fonte principal.

Regras obrigatorias:
1. Este projeto deve ser construido do zero.
2. O sistema antigo serve apenas como inspiracao funcional e fonte de requisitos.
3. Nao copie arquitetura, servicos globais, contratos ou schema do legado sem revisao explicita.
4. A arquitetura deve seguir camadas: `features -> domains -> integrations`.
5. A UI nunca acessa Supabase, Firebase, pagamentos ou mapas diretamente.
6. Toda regra critica deve estar no dominio ou backend.
7. Toda operacao sensivel deve passar por RPC, Edge Function, trigger ou policy segura.
8. Toda tabela publica deve ter RLS, indices e testes.
9. Toda mudanca deve incluir contrato JSON, validacao, erro esperado e teste quando aplicavel.
10. Pagamentos, dispatch, tracking e notificacoes devem ser idempotentes.
11. Avalie explicitamente se a plataforma deve ser monoapp modular ou multiapp com packages compartilhados.
12. Registre decisoes arquiteturais em `docs/adr/`.
13. Use OWASP MASVS como referencia de seguranca mobile e OWASP API Security para protecao de API.
14. Trate o backend como API JSON oficial com request/response padronizados, JWT, TLS e validacao de ownership/estado.
15. Respeite `docs/domain-architecture.md`, `docs/dispatch-flow.md`, `docs/tracking-domain.md`, `docs/payments-domain.md`, `docs/notifications-domain.md` e `docs/presence-profile-domain.md` como referencia de negocio.
16. Ao final, registre no `RELATORIO_DEV.md` o que foi feito, como foi validado e quais arquivos foram impactados.
```

## Proxima ordem recomendada

1. descoberta funcional;
2. seguranca e threat model;
3. decisao de arquitetura multiapp;
4. subir o novo Supabase local;
5. modelar schema canonico;
6. aplicar RLS e testes;
7. definir Edge Functions;
8. criar contratos JSON versionados;
9. formalizar a API JSON segura;
10. montar Flutter workspace;
11. criar packages compartilhados;
12. estruturar apps separados;
13. formalizar contratos de `auth`, `profile/presence` e `orders`;
14. construir `dispatch` e `tracking`;
15. construir `payments` e `notifications`;
16. construir admin, reviews e support;
17. fechar CI/CD, observabilidade e release.
