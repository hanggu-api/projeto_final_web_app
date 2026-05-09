# Patrol E2E

Base atual de testes E2E com Patrol para validar interface grafica e dialogs nativos.

## Suite inicial

- `patrol_test/smoke_app_test.dart`
  - sobe o app real;
  - concede dialogs nativos de permissao quando aparecerem;
  - valida que o app chega a uma tela estavel:
    - `login`, ou
    - `home` com busca, ou
    - `home-search`.

## Pre-requisitos

Instalar a CLI do Patrol no ambiente:

```bash
/snap/bin/dart pub global activate patrol_cli
```

Se necessario, garanta que `~/.pub-cache/bin` esteja no `PATH`.

Para evitar divergencia de SDK e conflitos de porta que ja apareceram no projeto,
prefira sempre rodar com o ambiente explicitamente fixado:

```bash
env PATH="$HOME/.pub-cache/bin:/snap/bin:/usr/bin:/bin" \
  PATROL_ANALYTICS_ENABLED=false \
  PATROL_FLUTTER_COMMAND=/snap/bin/flutter
```

## Rodar no celular

```bash
env PATH="$HOME/.pub-cache/bin:/snap/bin:/usr/bin:/bin" \
  PATROL_ANALYTICS_ENABLED=false \
  PATROL_FLUTTER_COMMAND=/snap/bin/flutter \
  patrol test --target patrol_test/smoke_app_test.dart --device ZF524PNH5V --app-server-port 8083 --test-server-port 8084
```

Ou usar o wrapper mais legivel:

```bash
bin/run_patrol_suite.sh busca phone ZF524PNH5V
```

## Rodar no emulador

Listar e subir um emulador:

```bash
flutter emulators
flutter emulators --launch Pixel_6
```

Depois rodar o teste:

```bash
env PATH="$HOME/.pub-cache/bin:/snap/bin:/usr/bin:/bin" \
  PATROL_ANALYTICS_ENABLED=false \
  PATROL_FLUTTER_COMMAND=/snap/bin/flutter \
  patrol test --target patrol_test/smoke_app_test.dart --device emulator-5554 --app-server-port 8083
```

Ou usar o wrapper mais legivel:

```bash
bin/run_patrol_suite.sh busca emulator emulator-5554
```

## Suites atuais

- `patrol_test/smoke_app_test.dart`
  - valida a tela `Buscar serviços` e a digitação na barra principal.
- `patrol_test/login_screen_test.dart`
  - valida renderização do login, digitação e a guarda de ambiente controlado.
- `patrol_test/pix_payment_screen_test.dart`
  - valida a tela `Pagamento Pix`, o motivo da cobrança e a cópia do código Pix.

## Script unico com resumo humano

Para evitar decorar os comandos completos e para receber um resumo final de:

- o que foi testado
- em qual aparelho
- se passou ou falhou
- onde olhar o log

use:

```bash
bin/run_patrol_suite.sh <suite> <ambiente> [device-id]
```

Suites suportadas:

- `busca`
- `login`
- `pix`

Ambientes suportados:

- `emulator`
- `phone`

Exemplos:

```bash
bin/run_patrol_suite.sh login emulator emulator-5554
bin/run_patrol_suite.sh pix emulator
bin/run_patrol_suite.sh busca,login,pix emulator
bin/run_patrol_suite.sh all emulator
bin/run_patrol_suite.sh login phone ZF524PNH5V
```

Esse script:

- aplica o `PATH` correto
- fixa `PATROL_FLUTTER_COMMAND=/snap/bin/flutter`
- usa as portas estáveis do projeto
- salva o log completo em `build/patrol_logs/`
- imprime um resumo final em linguagem simples
- aceita uma suite isolada ou um pacote de suites separadas por virgula
- gera um resumo consolidado no final do pacote

## Fluxo recomendado para aparelho real

Quando o runner do Android ficar intermitente, limpar o estado antes de rodar:

```bash
adb -s ZF524PNH5V shell am force-stop com.play101.app || true
adb -s ZF524PNH5V shell am force-stop com.play101.app.test || true
adb -s ZF524PNH5V uninstall com.play101.app >/dev/null 2>&1 || true
adb -s ZF524PNH5V uninstall com.play101.app.test >/dev/null 2>&1 || true
adb -s ZF524PNH5V logcat -c
```

## Observacoes

- O runner Android esta configurado para `clearPackageData=true`, entao os testes partem de um estado mais limpo e previsivel.
- No celular real, a estabilizacao final exigiu separar as portas do Patrol:
  - `--app-server-port 8083`
  - `--test-server-port 8084`
- Se aparecer `Invalid SDK hash`, a rodada foi executada com `dart`/`flutter` divergentes do `snap`.
- Se aparecer `OK (0 tests)` / `Instrumentation did not complete`, normalmente ha conflito de porta ou residuo de instalacao no aparelho.
