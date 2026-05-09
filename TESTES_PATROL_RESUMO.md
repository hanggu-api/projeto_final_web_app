# Testes Patrol - Resumo Pratico

Este arquivo explica, em linguagem direta, o que os testes Patrol do projeto realmente fazem.

## O que e o Patrol

O Patrol roda o app de verdade em um Android real ou emulador e executa passos automáticos na interface, como se fosse um usuário:

- abrir uma tela
- encontrar textos e campos
- digitar
- tocar em botões
- verificar se algo apareceu na tela

Ou seja: ele não testa só widget isolado. Ele testa a interface rodando no aparelho.

## Onde ficam os testes

Os testes Patrol ficam em:

- [patrol_test/smoke_app_test.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/patrol_test/smoke_app_test.dart)
- [patrol_test/login_screen_test.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/patrol_test/login_screen_test.dart)
- [patrol_test/pix_payment_screen_test.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/patrol_test/pix_payment_screen_test.dart)

## O que cada teste valida

### 1. Busca

Arquivo:
- [patrol_test/smoke_app_test.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/patrol_test/smoke_app_test.dart)

O que ele faz:
- abre a tela `Buscar serviços`
- valida o título da tela
- valida a barra principal da busca
- encontra o campo de texto
- digita `chaveiro`
- confirma que o texto ficou no campo

Em termos práticos:
- garante que a tela principal de busca abre e aceita digitação

## 2. Login

Arquivo:
- [patrol_test/login_screen_test.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/patrol_test/login_screen_test.dart)

O que ele faz:
- abre a tela de login
- valida o shell principal da tela
- encontra campo de email
- encontra campo de senha
- encontra o botão `ENTRAR`
- digita valores de teste
- toca no botão entrar
- valida a resposta esperada do ambiente controlado

Em termos práticos:
- garante que a tela de login está montada corretamente e reage ao envio

## 3. Pix controlado

Arquivo:
- [patrol_test/pix_payment_screen_test.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/patrol_test/pix_payment_screen_test.dart)

O que ele faz:
- abre a tela `Pagamento Pix` com dados controlados
- valida título, valor e motivo da cobrança
- valida referência do prestador
- rola a tela até o botão `Copiar Pix`
- toca no botão
- valida o snackbar `Código Pix copiado!`

Em termos práticos:
- garante que a tela Pix exibe as informações principais e permite copiar o código

## Como entender o output

Dentro dos testes, cada suite agora imprime passos claros no console, por exemplo:

- `[PATROL][BUSCA] Passo 1: abrir a tela Buscar serviços em ambiente controlado.`
- `[PATROL][LOGIN] Passo 4: preencher email e senha de teste.`
- `[PATROL][PIX] Passo 5: tocar no botão para copiar o código Pix.`

Essas mensagens mostram o que o teste está fazendo, sem depender só dos logs do Gradle ou da instrumentação Android.

## Comandos principais

Os comandos completos e padronizados estão em:

- [PATROL_TESTING.md](/home/servirce/Documentos/101/projeto-central-/mobile_app/PATROL_TESTING.md)

Se quiser um jeito mais simples, existe agora um script único:

- [bin/run_patrol_suite.sh](/home/servirce/Documentos/101/projeto-central-/mobile_app/bin/run_patrol_suite.sh)

Exemplo:

```bash
bin/run_patrol_suite.sh pix emulator
bin/run_patrol_suite.sh busca,login,pix emulator
```

Esse comando já:

- escolhe a suite certa
- aplica o ambiente certo
- usa as portas estáveis do projeto
- salva o log completo
- imprime um resumo final mais fácil de ler
- também pode rodar um pacote de suites e fechar com um resumo consolidado

Exemplo de execução no emulador:

```bash
env PATH="$HOME/.pub-cache/bin:/snap/bin:/usr/bin:/bin" \
  PATROL_ANALYTICS_ENABLED=false \
  PATROL_FLUTTER_COMMAND=/snap/bin/flutter \
  patrol test --target patrol_test/pix_payment_screen_test.dart --device emulator-5554 --app-server-port 8083
```

Exemplo de execução no celular real:

```bash
env PATH="$HOME/.pub-cache/bin:/snap/bin:/usr/bin:/bin" \
  PATROL_ANALYTICS_ENABLED=false \
  PATROL_FLUTTER_COMMAND=/snap/bin/flutter \
  patrol test --target patrol_test/pix_payment_screen_test.dart --device ZF524PNH5V --app-server-port 8083 --test-server-port 8084
```

## Leitura curta do resultado

Se aparecer algo assim:

- `✅ abre pagamento pix controlado e copia o codigo`

significa que o caso completo passou.

Se aparecer algo assim:

- `❌ Failed`

então a falha precisa ser lida no nome do caso e no último passo impresso pelo próprio teste para entender em que parte ele parou.
