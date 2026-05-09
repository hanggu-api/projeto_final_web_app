# Domínio de Notificações

## Fonte canônica

- tipo oficial de oferta: `service_offer`
- `notification_service.dart` é transicional e deve orquestrar módulos menores
- decisões específicas ficam em módulos dedicados de `services/support`

## Meta de convergência

- um contrato de payload por tipo de evento
- um fluxo consistente entre foreground, tap e background
- compatibilidade temporária com aliases antigos até migração completa

## Limite de responsabilidade

Notificações não devem decidir:
- ordem de dispatch
- timeout oficial do backend
- regra de aceite/concorrência
