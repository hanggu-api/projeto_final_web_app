# Domínio de Tracking

## Objetivo

Centralizar a visão de estado do serviço para cliente e prestador com menos lógica duplicada.

## Direção

- `service status` precisa de contrato canônico
- realtime é preferencial, polling é fallback
- telas não devem reinventar transições de status localmente

## Resultado esperado

- rota ativa previsível
- status consistente entre backend, snapshot e UI
- menos divergência entre fluxo móvel, agendado e busca de prestador
