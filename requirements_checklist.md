# Uber App Feature Requirements Checklist

This document tracks all implemented features and UI requirements to prevent regressions during ongoing development.

## 🗺️ Search & Location UI
- [x] **White Background Card**: Search results must be inside a white card with rounded corners (16px).
- [x] **Soft Shadow**: The search results container must have a subtle floating shadow.
- [x] **Thin Dividers**: Dividers between results must be light gray (`grey.shade200`), 1px thick, with specific indents.
- [x] **relocated 'Set on Map'**: The "Definir no mapa" option must be at the VERY END of the search results list, inside the same white container.
- [x] **'SUGESTÕES' Header**: A stylized uppercase header for search suggestions.

## 🏘️ Address & Neighborhood Data
- [x] **Full Address Display**: Results must show the full street name and number.
- [x] **Bairro em destaque**: O nome do bairro aparece em uma etiqueta cinza em cada resultado.
- [x] **Dados Limpos**: O selo do bairro e o endereço secundário NÃO mostram cidade/estado se o bairro for identificado (ex: apenas "BACURI").
- [x] **Busca Enriquecida (MANDATÓRIO)**: O sistema DEVE usar geocodificação reversa (Nominatim/Edge Function) como fonte PRINCIPAL para o nome do bairro, pois o TomTom não entrega essa informação de forma confiável. O TomTom é apenas um fallback.
- [x] **Bairro Badge**: Display the neighborhood name in a small gray badge at the bottom of the result.

## 🎨 Icons & Styling
- [x] **Dynamic Category Colors**: Category icons must have vibrant background circles:
  - 🟢 Green: Markets/Shopping
  - 🍱 Orange: Food/Restaurants
  - 🔵 Blue: Gas/Banks/Transport
  - 🔴 Red: Health/Hospitals
- [x] **iOS Maps Style**: Icons should be white, centered in their colored circles, size 22.

## 🐛 Critical Fixes
- [x] **Syntax Errors**: All bracket mismatches and undefined variable errors fixed.
- [x] **Variable Names**: Use `_isPickingOnMap` instead of legacy `_isManualSelecting`.

## 🚗 Active Trip Redirection
- [x] **Persistent Ride Access**: Garantir redirecionamento automático para tela de tracking quando houver viagem ativa. (Implementado via go_router redirect em main.dart e verificação no home_screen.dart)
- [x] **Real Driver Data**: Carregar e exibir o nome real e foto do motorista e detalhes do veículo na tela de acompanhamento a partir da tabela `users`.
- [x] **Premium Driver Marker**: Ícone de carro/moto amarelo com fundo de círculo amarelo e borda branca.
- [x] **Origin & Destination Pins**: Novos marcadores de pino premium (Azul para Origem e Vermelho para Destino) com hastes de precisão apontando no mapa.
- [x] **Searching State Premium**: Tela de busca com barra de progresso amarela, botão de cancelar e exibição clara de partida/destino.
- [x] **Data Persistence (Soft Delete)**: Desabilitada a remoção física de viagens no banco de dados para garantir estabilidade e histórico.
- [x] **Map Visibility Fix**: TileLayer sincronizado entre telas para garantir carregamento de texturas (TileSize 512 + ZoomOffset -1).
- [x] **Ultra-Compact Layout**: Otimização de paddings e sizedbox para maximizar a visibilidade da rota no mapa.
- [x] **Standard Premium Route**: Rota azul sólida (`#2196F3`) implementada em todas as telas de pedido e rastreamento.

## 💬 Uber Chat Integration
- [x] **Universal Chat Access**: Passageiros e motoristas podem abrir o bate-papo a qualquer momento durante uma corrida ativa usando o ícone de mensagem.
- [x] **Unified Chat Data**: Reutilização da lógica do `ChatScreen` original de "serviços", com fallback de consultas direcionadas à tabela `trips` se o ID não for encontrado em `service_requests_new`.
- [x] **Real-time Messaging**: Mensagens trafegam usando os mesmos endpoints/streams Supabase de envio de mensagens do SuperApp, garantindo estabilidade e anexos.
