# OTA Release Playbook

## Objetivo

Padronizar quando o app pode usar patch OTA e quando precisa de nova publicação na loja.

## Stack oficial

- `Shorebird` para patch de código Dart
- `Supabase` para flags, kill switches e `remote_ui`
- `Firebase` apenas para `FCM` e `Crashlytics`

## Política de decisão

Use patch OTA quando a mudança estiver limitada a:

- correção de lógica em Dart
- correção de UI Flutter
- ajustes de providers, use cases e chamadas Supabase
- mudança de comportamento controlada por flag já existente
- rollback funcional por kill switch ou fallback local

Exija nova versão da loja quando houver:

- alteração em `AndroidManifest.xml`
- nova permissão nativa
- novo SDK/plugin nativo
- mudança em Kotlin, Gradle, Firebase config, assets nativos ou ícones de app
- alteração que dependa de código Android/iOS compilado

## Fluxo operacional

1. Publicar a versão base na Play Store com `APP_VERSION` novo.
2. Registrar essa versão como base do release OTA.
3. Validar runtime no app:
   - `store version`
   - `patch version`
   - `environment`
4. Se houver incidente corrigível por Dart:
   - aplicar correção
   - validar fallback/flag relacionado
   - publicar patch OTA
5. Monitorar `Crashlytics` e logs de runtime após o patch.

## Aprovação

- Produto aprova ativação de flag ou kill switch.
- Engenharia aprova publicação de patch OTA.
- Mudanças nativas sempre exigem ciclo normal de loja.

## Convenções remotas

- flags: `flag.<dominio>.<recurso>.<acao>`
- kill switches: `kill_switch.<dominio>.<recurso>`
- configs operacionais: `ops.<dominio>.<parametro>`
- conteúdo remoto: `content.<dominio>.<chave>`

## Superfícies liberadas para remote_ui no rollout inicial

- `help`
- `home_explore`
- banners, campanhas, FAQs, estados vazios e catálogos

## Superfícies proibidas no rollout inicial

- autenticação
- login
- PIX/cartão
- tracking em tempo real
- permissões nativas
