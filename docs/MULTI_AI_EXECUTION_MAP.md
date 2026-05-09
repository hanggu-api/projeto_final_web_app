# Mapa de Execução Multi-IA (Lock Estrito)

Objetivo: permitir execução paralela por lotes sem quebrar código estabilizado pelo Codex.

## Regras globais
- Toda IA deve ler `AGENTS.md` e `RELATORIO_DEV.md` antes de editar.
- Toda IA deve rodar guardrails:
  - `./tool/revision_guard.sh`
  - `./tool/strict_stage_guard.sh --stage <stage_id>`
- Alteração fora da allowlist da etapa é bloqueada.
- Toda mudança precisa registrar entrada no `RELATORIO_DEV.md`.

## Lotes por etapa

### Lote 1 - Contrato canônico
- Stage ID: `stage_01_contract`
- Objetivo: consolidar estados, eventos, permissões, transições e idempotência.
- Arquivos permitidos: `lib/core/contracts/**`, `docs/SERVICE_FLOW_CANONICAL_CONTRACT.md`, `test/core/contracts/**`.
- Testes mínimos: transições válidas/inválidas, permissão por papel, terminalidade.
- Definition of done: contrato único aprovado e sem quebra de análise.

### Lote 2 - Dispatch e notificação
- Stage ID: `stage_02_dispatch`
- Objetivo: enfileiramento, oferta, aceite/recusa, timeout e requeue.
- Arquivos permitidos: `supabase/functions/dispatch/**`, `supabase/functions/push-notifications/**`, `lib/services/api_service.dart`, `lib/features/provider/provider_home_mobile.dart`.
- Testes mínimos: aceite único, recusa com requeue, timeout controlado.
- Definition of done: fluxo de oferta auditável e idempotente.

### Lote 3 - PIX 70%
- Stage ID: `stage_03_pix_down_payment`
- Objetivo: criação/confirmação/expiração de cobrança PIX 70%.
- Arquivos permitidos: `supabase/functions/mp-*/**`, `lib/features/client/service_tracking_page.dart`, `lib/services/api_service.dart`.
- Testes mínimos: created->pending->paid, expiração e bloqueio de duplicidade.
- Definition of done: não há dupla cobrança e estado canônico avança corretamente.

### Lote 4 - Código de conclusão
- Stage ID: `stage_04_completion_code`
- Objetivo: emissão, TTL, validação e consumo único do código.
- Arquivos permitidos: `supabase/functions/service-request/**`, `lib/features/client/service_tracking_page.dart`, `lib/features/provider/provider_active_service_mobile_screen.dart`.
- Testes mínimos: código inválido/expirado/reutilizado.
- Definition of done: conclusão só ocorre após validação canônica.

### Lote 5 - Avaliação
- Stage ID: `stage_05_review_prompt`
- Objetivo: disparo do modal de avaliação após `completed`.
- Arquivos permitidos: `lib/features/common/review_screen.dart`, `lib/features/client/service_tracking_page.dart`, `lib/services/api_service.dart`.
- Testes mínimos: modal em fluxo feliz, avaliação única idempotente.
- Definition of done: avaliação aparece no momento correto sem duplicidade.
