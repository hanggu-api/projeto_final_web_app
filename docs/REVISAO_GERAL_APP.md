# Revisao Geral do App (Backend-First)

## Objetivo
- Consolidar o que ja foi alterado no app cliente e prestador.
- Definir trilha unica de negocio: API REST/Supabase como fonte de verdade.
- Criar travas para reduzir risco de regressao.

## Resumo do que ja mudou
- Tracking canônico unificado no eixo `/service-tracking/:serviceId`.
- Snapshot/active-service viraram base de decisao de tela.
- Fluxo de prestador ajustado para usar status canônico do `service`.
- Cliente em `open_for_schedule` permanece na Home com card de espera.
- Textos de card de espera passaram a suportar payload canônico (`activeServiceUi`).
- Guard rails de Supabase/arquitetura adicionados e reforcados.

## Contratos canônicos (na pratica)
- Backend decide estado de tela.
- App renderiza e envia comandos REST.
- Status de regra de negocio nao pode ser inferido localmente com heuristica solta.

## Principais arquivos de referencia
- Backend API: `supabase/functions/api/index.ts`
- Home cliente: `lib/features/home/home_screen.dart`
- Banner espera cliente: `lib/features/home/widgets/home_waiting_service_banner.dart`
- Home prestador: `lib/features/provider/provider_home_mobile.dart`
- Card prestador: `lib/features/provider/widgets/provider_service_card.dart`
- Estado home backend: `lib/core/home/backend_client_home_state.dart`
- Estado tracking backend: `lib/core/tracking/backend_active_service_state.dart`

## Travas de regressao
- `scripts/supabase_guard.sh check`
  - garante layout canônico e politica `verify_jwt = false` para `[functions.api]`.
- `tool/check_no_direct_supabase.sh --changed`
  - bloqueia acesso direto ao Supabase em Dart novo/alterado.
- `tool/ci_quality_gate.sh`
  - gate basico de qualidade local.
- `tool/revision_guard.sh`
  - comando unico de revisao forte (policy + contrato + analyze + quality gate).

## Como rodar a revisao completa
```bash
./tool/revision_guard.sh
```

## Criterios de aprovacao
- Sem erro no `revision_guard`.
- Sem acesso direto novo ao Supabase em `lib/`.
- Arquitetura backend-first preservada nos pontos canônicos.
- Sem erro de analise nos arquivos criticos.
