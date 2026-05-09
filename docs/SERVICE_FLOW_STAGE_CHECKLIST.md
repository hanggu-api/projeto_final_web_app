# Checklist Canônico por Etapa do Fluxo de Serviço

Este é o artefato obrigatório para execução por humanos e outras IAs.
Cada etapa só pode ser considerada concluída quando todos os critérios estiverem `OK`.

## Etapa 1 - Busca e seleção de serviço
- Entrada obrigatória: cliente autenticado, localização válida, categoria escolhida.
- Validações: serviço ativo, escopo (`mobile|fixed`), preço base carregado.
- Ações backend/app: carregar catálogo, normalizar payload para contrato canônico.
- Saída esperada: requisição pronta para criação sem campos nulos críticos.
- Erros/recuperação: fallback de busca e retry de rede com timeout curto.
- Critérios de aceite: cliente consegue avançar para criação sem inconsistência de status.

## Etapa 2 - Criação do pedido
- Entrada obrigatória: `service_scope`, `profession_id`, endereço, forma de pagamento inicial.
- Validações: role do usuário = cliente, payload canônico válido.
- Ações backend/app: persistir pedido e definir estado `searching_provider`.
- Saída esperada: `service_id` canônico + estado inicial confirmado.
- Erros/recuperação: idempotência por chave de requisição.
- Critérios de aceite: criação duplicada não gera 2 serviços ativos.

## Etapa 3 - Enfileiramento e disparo de notificação
- Entrada obrigatória: serviço em `searching_provider|open_for_schedule`.
- Validações: prestadores elegíveis online e aptos para categoria.
- Ações backend/app: enfileirar dispatch e emitir evento `offer_dispatched`.
- Saída esperada: serviço em `offered_to_provider` com trilha de evento.
- Erros/recuperação: timeout de oferta + requeue controlado.
- Critérios de aceite: tentativa expirada não bloqueia próximo prestador elegível.

## Etapa 4 - Aceite/recusa do prestador
- Entrada obrigatória: oferta ativa para prestador autenticado.
- Validações: ownership da oferta e validade temporal.
- Ações backend/app: `acceptOffer` ou `rejectOffer` com idempotência.
- Saída esperada: `provider_accepted` ou `provider_rejected` + evento de dispatch.
- Erros/recuperação: recusa volta para fila; aceite duplicado retorna resultado estável.
- Critérios de aceite: somente um prestador consegue aceitar o mesmo serviço.

## Etapa 5 - Prestador chegou
- Entrada obrigatória: serviço em `provider_accepted`.
- Validações: prestador correto e geolocalização mínima.
- Ações backend/app: registrar chegada com timestamp auditável.
- Saída esperada: `provider_arrived`.
- Erros/recuperação: tentativa fora de ordem bloqueada e logada.
- Critérios de aceite: cliente visualiza status de chegada em tempo real.

## Etapa 6 - Geração/cobrança PIX 70%
- Entrada obrigatória: serviço em `provider_arrived`.
- Validações: pagador cliente, recebedor prestador, split/valor canônico.
- Ações backend/app: gerar cobrança PIX (`created|pending`) e confirmar pagamento (`paid`).
- Saída esperada: `waiting_pix_down_payment` -> `pix_down_payment_paid`.
- Erros/recuperação: expiração de cobrança, reemissão controlada, bloqueio de dupla cobrança.
- Critérios de aceite: pagamento duplicado não altera saldo duas vezes.

## Etapa 7 - Início e execução do serviço
- Entrada obrigatória: PIX 70% confirmado.
- Validações: role do prestador e estado atual.
- Ações backend/app: iniciar execução e registrar `in_progress`.
- Saída esperada: serviço em andamento com trilha de auditoria.
- Erros/recuperação: tentativa sem PIX confirmado deve falhar.
- Critérios de aceite: transição ilegal para `in_progress` é bloqueada.

## Etapa 8 - Código de confirmação
- Entrada obrigatória: serviço em `in_progress`.
- Validações: gerar código único, TTL e consumo único.
- Ações backend/app: cliente recebe código, prestador informa, backend valida.
- Saída esperada: `awaiting_completion_code` pronto para finalizar.
- Erros/recuperação: código inválido/expirado com nova emissão controlada.
- Critérios de aceite: código não pode ser reutilizado após consumo.

## Etapa 9 - Finalização do serviço
- Entrada obrigatória: código validado ou trilha autorizada de exceção.
- Validações: estado consistente, ator autorizado, idempotência de finalização.
- Ações backend/app: concluir serviço e consolidar financeiro.
- Saída esperada: `completed`.
- Erros/recuperação: disputa abre `disputed` em vez de completar à força.
- Critérios de aceite: finalização não ocorre em estados fora da máquina canônica.

## Etapa 10 - Modal de avaliação do cliente
- Entrada obrigatória: serviço em `completed`.
- Validações: avaliação única por serviço/cliente.
- Ações backend/app: disparar `review_trigger` e salvar avaliação.
- Saída esperada: modal exibido e avaliação persistida.
- Erros/recuperação: reenvio idempotente da avaliação.
- Critérios de aceite: cliente recebe modal ao concluir fluxo feliz.
