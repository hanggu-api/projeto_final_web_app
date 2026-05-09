# Dispatch Flow

## Objetivo

Este documento define o fluxo oficial de dispatch sequencial do `101 Service` para o app móvel de prestadores.

## Fonte oficial

- Backend de materialização de fila: `supabase/functions/dispatch/index.ts`
- Worker sequencial: `supabase/functions/dispatch-queue/index.ts`
- Envio de push: `supabase/functions/push-notifications/index.ts`
- UI de oferta no app: `lib/features/provider/widgets/service_offer_modal.dart`

## Regra operacional

O sistema trabalha em modo `single_provider`:

1. o backend encontra candidatos por proximidade;
2. materializa a fila da rodada em `notificacao_de_servicos`;
3. o worker notifica apenas um prestador por vez;
4. aguarda aceite, recusa ou timeout;
5. se a oferta falhar, passa para o próximo `queued`;
6. quando a rodada esgota, o backend avança para a próxima;
7. quando todas as rodadas acabam, o serviço vai para `open_for_schedule`.

## Responsabilidades

### Backend

- decide a ordem dos prestadores;
- controla timeout oficial da oferta;
- impede duplicidade de tentativas para o mesmo prestador;
- registra logs operacionais;
- encerra a fila quando alguém aceita.

### App do prestador

- recebe o push;
- abre o modal da oferta;
- exibe contagem regressiva baseada no deadline do backend;
- envia `accept` ou `reject`;
- fecha a UI quando o backend informar que a oferta saiu de `notified`.

## Limites de responsabilidade

O app não deve:

- decidir quem é o próximo prestador;
- avançar rodada;
- recriar timeout do dispatch como fonte de verdade;
- consultar múltiplas tabelas de dispatch espalhadamente sem passar por uma camada de serviço.

## Direção de manutenção

Ao evoluir esse fluxo, priorizar:

- backend como fonte única da verdade;
- payloads de push padronizados;
- menos leitura direta de `notificacao_de_servicos` na UI;
- menos lógica duplicada entre `notification_service.dart` e `service_offer_modal.dart`.
