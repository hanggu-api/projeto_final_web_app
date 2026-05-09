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
- [x] **Dynamic Car Telemetry Balloon**: Balão informativo flutuante sobre o ícone do carro exibindo velocidade (km/h), tempo estimado (min) e distância (km).
- [x] **Auto-Rotation Navigation**: Mapa gira e centraliza automaticamente no ícone do carro durante o deslocamento.
- [x] **Pickup Trailing Route**: Rota verde destacada para o trajeto de busca, que desaparece gradualmente à medida que o motorista avança.
- [x] **Smart Payment Flow**: Validação automática de cartão cadastrado ao selecionar "Cartão (Plataforma)" com redirecionamento para cadastro se necessário.
- [x] **Auto-Home on Cancellation**: Navegação reativa para a tela inicial imediata após o cancelamento de uma viagem.

## 💳 Mercado Pago & KYC Integration
- [x] **Automated Provisioning**: Mercado Pago collector account linked automatically when a driver goes online for the first time.
- [x] **KYC Data Sync**: CNH and Selfie documents uploaded and validated for split payments.
- [x] **OCR Pre-fill**: Driver information (Name, DOB, CPF) pre-filled from OCR results for account verification.
- [x] **Secure Trigger**: Provisioning triggered via 'mp-onboarding-handler' Edge Function using user JWT.
- [x] **Card Tokenization**: Credit cards tokenized via 'mp-tokenize-card' for platform payments.
- [x] **Split Payments**: Automated 30/70 split handling for drivers via Mercado Pago.
- [x] **Cash Payment Fix**: Corrigir erro 401 na confirmação de pagamento em dinheiro (Refazer deploy com `verify_jwt: false`).
