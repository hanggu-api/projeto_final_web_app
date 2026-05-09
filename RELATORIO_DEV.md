# RELATORIO DEV

## 2026-05-09 - Cadastro volta a mostrar icones das etapas no topo

### Alterações Realizadas

- Ajustado `lib/features/auth/register_screen.dart` para restaurar o trilho de etapas com icones no topo do cadastro.
- Cada etapa agora exibe um icone e rotulo curto, com destaque visual para etapa atual e check para etapas concluidas.
- Mantida a barra fina de progresso abaixo dos icones para indicar o avanço geral do fluxo.

### Efeito prático

- O usuario volta a enxergar em qual etapa do cadastro esta, como na versao boa lembrada.
- O fluxo de prestador continua começando por prova de vida, mas agora com indicador visual de etapas no topo.

### Arquivos Impactados

- `lib/features/auth/register_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/auth/register_screen.dart`
  - `flutter analyze --no-pub lib/features/auth/register_screen.dart`
- Resultado:
  - arquivo Dart formatado;
  - `No issues found!`

## 2026-05-09 - Prova de vida do cadastro volta ao modo normal completo

### Alterações Realizadas

- Ajustado `lib/features/auth/steps/facial_liveness_step.dart` para abrir a câmera de prova de vida sem `blinkOnly`.
- Ajustado `lib/features/shared/widgets/in_app_camera_screen.dart` para permitir forçar o liveness completo mesmo quando o aparelho preferiria o modo simplificado.
- O cadastro de prestador agora usa `forceFullLiveness: true`, preservando o fluxo normal com instruções faladas, piscada, virar a cabeça para esquerda/direita e fixar o rosto.
- Atualizadas as instruções visuais da etapa para mencionar que o usuário deve seguir as instruções faladas e fazer os movimentos solicitados.

### Efeito prático

- A primeira etapa do cadastro de prestador deixa de ser o modo leve de apenas piscada/captura simplificada.
- A prova de vida volta ao comportamento esperado da versão boa: desafio completo guiado por voz.

### Arquivos Impactados

- `lib/features/auth/steps/facial_liveness_step.dart`
- `lib/features/shared/widgets/in_app_camera_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/auth/steps/facial_liveness_step.dart lib/features/shared/widgets/in_app_camera_screen.dart`
  - `flutter analyze --no-pub lib/features/auth/steps/facial_liveness_step.dart lib/features/shared/widgets/in_app_camera_screen.dart`
- Resultado:
  - arquivos Dart formatados;
  - `No issues found!`

## 2026-05-09 - Build Web publicado passa a ser referencia absoluta de restauracao

### Alterações Realizadas

- Confirmado que `https://www.101service.com.br/login` e `vercel_dist/main.dart.js` representam o mesmo build web publicado:
  - versao `1.0.2+6`;
  - `main.dart.js` com `7739710` bytes;
  - SHA-256 `e843dd1c4a271fcecfc0c2089d983129d157335cfe578e488b7d3d59066723cb`.
- Criado `docs/WEB_BUILD_REFERENCE_INVENTORY.md` com rotas, textos, hashes e contratos observados no bundle bom.
- Revertida a divergencia local que fazia a Home executar busca inline como fluxo principal.
- A Home voltou ao comportamento observado no bundle publicado:
  - barra em `launcherMode`;
  - toque/digitacao direcionando para `/home-search`;
  - atalhos de servicos, beleza e profissao abrindo a busca dedicada.

### Efeito prático

- O app local volta a seguir o build web bom como fonte de verdade para Home/busca.
- A restauracao futura de cadastro, prestador, tracking e pagamento passa a ter um inventario local objetivo para comparacao.
- A anotacao anterior sobre Home inline fica superada por esta decisao: o build publicado prevalece sobre a alteracao local.

### Arquivos Impactados

- `docs/WEB_BUILD_REFERENCE_INVENTORY.md`
- `lib/features/home/home_screen.dart`
- `lib/features/home/widgets/home_search_bar.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - validacao de hashes e metadados em `vercel_dist/`
  - `dart format lib/features/home/home_screen.dart lib/features/home/widgets/home_search_bar.dart`
  - `flutter analyze --no-pub lib/features/home/home_screen.dart lib/features/home/widgets/home_search_bar.dart`
  - `flutter analyze --no-pub`
  - `flutter build web --release`
- Resultado:
  - restauracao alinhada ao bundle web publicado;
  - recorte de Home/AppDrawer: `No issues found!`;
  - analise global sem erros, permanecendo apenas warnings/infos antigos;
  - build web local concluido com sucesso em `build/web`;
  - `build/web/version.json` e `build/web/assets/AssetManifest.bin.json` batem com `vercel_dist`;
  - `build/web/main.dart.js` difere em hash/tamanho do `vercel_dist`, esperado enquanto o source local mantem a correcao minima de compilacao do `AppDrawer` e nao ha sourcemap para reproducao byte a byte.

## 2026-05-09 - Home/busca restaurada como fluxo inline principal

### Alterações Realizadas

- Ajustado `lib/features/home/home_screen.dart` para que os atalhos de Home alimentem a busca inline em vez de navegar para `/home-search`.
- Adicionado controle local de `seedQuery`/`seedVersion` na Home para semear a barra com termos como `serviços`, `beleza` e nome da profissão selecionada.
- Ajustado `lib/features/home/widgets/home_search_bar.dart` para disparar a busca interna quando recebe uma nova seed programática.
- Mantida a tela `/home-search` existente para compatibilidade de rota, mas a Home volta a ser a superfície principal de busca do fluxo inicial.

### Efeito prático

- tocar em categorias/profissões na Home não arranca mais o usuário para outra tela;
- a busca e as sugestões permanecem dentro do card/painel da Home;
- reduz a regressão visual/funcional em que a Home parecia voltar para um fluxo separado e menos moderno.

### Arquivos Impactados

- `lib/features/home/home_screen.dart`
- `lib/features/home/widgets/home_search_bar.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/home/home_screen.dart lib/features/home/widgets/home_search_bar.dart`
  - `flutter analyze --no-pub lib/features/home/home_screen.dart lib/features/home/widgets/home_search_bar.dart`
- Resultado:
  - `No issues found!`

## 2026-05-09 - Perícia de regressão e estabilização mínima do analyzer

### Alterações Realizadas

- Executada análise de regressão com Git, comparando `main/origin/main`, `backup/2026-05-09-safety-snapshot`, branch remoto de Copilot e worktree de Copilot.
- Confirmado que o branch remoto `copilot/vscode-mmiwc4gu-fuxh` não contém a grande regressão do app; ele adiciona apenas workflow de CI.
- Identificado que a grande mudança local está concentrada no snapshot `0792b8d`, com alterações amplas em Home, cliente, prestador, tracking, `core`, `domains`, Supabase e artefatos gerados.
- Ajustado `lib/widgets/app_drawer.dart` para aceitar `asPage`, corrigindo o uso feito por `lib/features/shared/app_menu_screen.dart`.
- Ajustado `analysis_options.yaml` para excluir `test_sp.dart`, um arquivo local solto de experimento que importava `screen_protector` sem fazer parte do app distribuído.

### Efeito prático

- O app volta a ter uma base de análise mais confiável antes de qualquer rollback cirúrgico.
- A correção não altera os fluxos de cliente/prestador; apenas remove erros estruturais que atrapalhavam a perícia.
- Fica documentado que o `RELATORIO_DEV.md` ajuda como contexto, mas o Git é a fonte principal para recuperação.

### Arquivos Impactados

- `lib/widgets/app_drawer.dart`
- `analysis_options.yaml`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `flutter analyze --no-pub`
- Resultado:
  - análise inicial apontou 2 erros reais: parâmetro `asPage` ausente em `AppDrawer` e `test_sp.dart` importando pacote inexistente;
  - após a correção mínima, `flutter analyze --no-pub` não reportou erros;
  - permaneceram 7 warnings antigos em `provider_home_mobile.dart` e `api_service.dart`, além de 2 infos de dependências referenciadas em arquivos auxiliares.

## 2026-05-09 - Home volta a usar busca inline no card com decisao canonica de prestador fixo/movel

### Alterações Realizadas

- Ajustado `lib/features/home/home_screen.dart` para tirar a barra principal da Home do `launcherMode`.
- A busca da Home voltou a usar o autocomplete inline dentro do proprio card/painel, sem redirecionar a digitacao para `/home-search`.
- Reaproveitada na Home a mesma logica canonica da `HomeSearchScreen` para resolver `service_type`:
  - quando a sugestao nao vem classificada, a Home tenta `ApiService.classifyService(query)`;
  - se o resultado indicar `at_provider`, abre o fluxo `/beauty-booking`;
  - se o resultado indicar `on_site`, abre `MobileServiceRequestReviewScreen`;
  - quando houver `provider_profile`, a Home continua abrindo o perfil do prestador.
- Mantido fallback heuristico somente quando a classificacao nao vier pronta, preservando a decisao guiada por banco/backend como caminho principal.

### Efeito prático

- a Home volta ao comportamento mais moderno em que o input e a listagem ficam contidos no proprio card;
- reduz a sensacao de “Home antiga” causada pelo desvio imediato para a tela separada de busca;
- melhora a consistencia da diferenciacao entre prestador fixo e movel usando o mesmo criterio que ja estava funcionando na busca dedicada.

### Arquivos Impactados

- `lib/features/home/home_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/home/home_screen.dart`
  - `dart analyze lib/features/home/home_screen.dart`
- Resultado:
  - `No issues found!`

## 2026-05-09 - Restauração parcial de comportamento moderno no cadastro e na Home

### Alterações Realizadas

- Ajustado `lib/features/auth/register_screen.dart` para recolocar a etapa `FacialLivenessStep` no início do fluxo do prestador, em vez de deixá-la no final.
- Ajustado o botão principal do cadastro para voltar a uma aparência mais escura, com fundo `AppTheme.textDark` e texto branco.
- Ajustado `lib/features/home/widgets/home_search_bar.dart` para suportar `launcherMode`.
- Ajustado `lib/features/home/home_screen.dart` para usar a barra da Home em modo launcher:
  - sem autocomplete inline dentro do painel principal;
  - toque abre o fluxo normal de busca;
  - evita expandir sugestões na própria Home.
- Ajustado `lib/widgets/app_drawer.dart` e `lib/main.dart` para corrigir a navegação do menu do prestador:
  - `Configurações` volta a abrir a página normal de perfil do prestador;
  - `Segurança` deixa de apontar para rota inexistente;
  - criada compatibilidade de rota `/driver-settings` para a página de perfil/configurações do prestador.

### Efeito prático

- aproxima o cadastro do prestador do fluxo que você descreveu, com prova de vida logo no começo;
- devolve ao cadastro a ação principal com visual mais escuro;
- reduz a sensação de “Home antiga” causada pela barra de busca expandindo conteúdo inline em vez de delegar para a tela de busca.

### Arquivos Impactados

- `lib/features/auth/register_screen.dart`
- `lib/features/home/widgets/home_search_bar.dart`
- `lib/features/home/home_screen.dart`
- `lib/widgets/app_drawer.dart`
- `lib/main.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/auth/register_screen.dart lib/features/home/home_screen.dart lib/features/home/widgets/home_search_bar.dart lib/widgets/app_drawer.dart lib/main.dart`
  - `dart analyze lib/features/auth/register_screen.dart lib/features/home/home_screen.dart lib/features/home/widgets/home_search_bar.dart lib/widgets/app_drawer.dart lib/main.dart`
- Resultado:
  - `No issues found!`

## 2026-05-09 - Perfil e FCM deixam de acionar rotas legadas `/users/:id` no bootstrap do app

### Alterações Realizadas

- Ajustado `lib/services/api_service.dart` para que `unregisterDeviceToken(...)` deixe de chamar rotas backend legadas `/api/v1/users/me/fcm` e `/api/v1/users/{id}/fcm`.
- O desligamento do token FCM agora limpa `fcm_token` direto na tabela `users` via Supabase, alinhado com o caminho já usado no registro do token.
- Ajustado `ApiService.getMyProfile()` para tentar `loadToken()` antes de concluir que não existe snapshot de identidade, reduzindo falhas prematuras de `no_identity_snapshot`.
- Ajustado `lib/services/media_service.dart` para que, ao carregar avatar do próprio usuário, use primeiro `loadMyAvatarBytes()` e evite `GET /api/v1/users/{meu_id}` desnecessário.

### Efeito prático

- reduz logs de `404 route_not_found` em `/api/users/<id>`;
- elimina o `405 method_not_allowed` ao tentar limpar FCM por rota legada;
- melhora a chance de o perfil carregar corretamente durante a reidratação inicial da sessão.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `lib/services/media_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart lib/services/media_service.dart lib/widgets/app_drawer.dart`
  - `dart analyze lib/services/api_service.dart lib/services/media_service.dart lib/widgets/app_drawer.dart`
- Resultado:
  - sem erros novos das alterações;
  - permaneceram 3 warnings antigos de `unused_catch_clause` em `lib/services/api_service.dart`;
  - ao final, o processo tentou gravar telemetria em `~/.dart-tool` e encontrou bloqueio de filesystem fora do workspace no sandbox atual.

## 2026-05-09 - Drawer passa a usar perfil canônico e cache hidratado para evitar cabeçalho parcial

### Alterações Realizadas

- Ajustado `lib/widgets/app_drawer.dart` para carregar o cabeçalho do menu lateral com prioridade em fontes mais estáveis.
- A drawer agora resolve o perfil nesta ordem:
  - cache já hidratado em `ApiService.userData`
  - `SharedPreferences`
  - perfil canônico via `BackendProfileApi.fetchMyProfile()`
  - `ApiService.getMyProfile()` como complemento e fallback, especialmente para avatar
- Adicionadas rotinas locais para normalizar valores inválidos como string `'null'` e evitar sobrescrever nome/avatar bons com payload parcial.

### Efeito prático

- reduz os casos em que o menu lateral mostra nome/avatar incompletos ou antigos em uma página específica;
- deixa o cabeçalho do drawer mais consistente com o perfil canônico já usado na tela de configurações;
- evita regressão visual quando um endpoint devolve apenas dados parciais do usuário.

### Arquivos Impactados

- `lib/widgets/app_drawer.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/widgets/app_drawer.dart`
  - `dart analyze lib/widgets/app_drawer.dart`
- Resultado:
  - `No issues found!`
  - ao final, o processo tentou gravar telemetria em `~/.dart-tool` e encontrou bloqueio de filesystem fora do workspace no sandbox atual.

## 2026-05-09 - Refresh da aba Disponíveis preserva dados ricos do card de agendamento

### Alterações Realizadas

- Ajustado `lib/features/provider/provider_home_mobile.dart` para que o reload de `_loadData()` não sobrescreva cegamente um item já enriquecido da aba `Disponíveis` com uma versão mais pobre vinda do payload seguinte.
- Adicionado merge local entre o payload novo e `_availableServices` atual, preservando campos mais ricos já carregados em memória, como:
  - `description`
  - `address`
  - `profession`
  - `category_name`
  - `task_name`
  - `latitude` / `longitude`
  - preços
- Refinado `_shouldEnrichAvailableService(...)` para tratar placeholders como `Endereço não disponível` também como dado faltante, forçando novo enriquecimento canônico quando necessário.

### Efeito prático

- corrige o cenário em que o card do prestador abre certo por alguns segundos e depois “empobrece” no refresh, perdendo endereço e coordenadas;
- reduz a chance de o app voltar a cair em `Invalid destination coords` para serviços que já foram corretamente hidratados;
- mantém o comportamento mais estável da vitrine `Disponíveis` após os ajustes no fluxo de agendamento.

### Arquivos Impactados

- `lib/features/provider/provider_home_mobile.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/provider/provider_home_mobile.dart`
  - `dart analyze lib/features/provider/provider_home_mobile.dart`
- Resultado:
  - sem erros novos das alterações;
  - permaneceram apenas warnings antigos de `unused_element` em `lib/features/provider/provider_home_mobile.dart`;
  - ao final, o processo tentou gravar telemetria em `~/.dart-tool` e encontrou bloqueio de filesystem fora do workspace no sandbox atual.

## 2026-05-09 - Botão AGENDAR SERVIÇO deixa de sumir no refresh por variação textual de status

### Alterações Realizadas

- Ajustado `lib/features/provider/widgets/provider_service_card.dart` para que os blocos de agendamento usem `statusLower` normalizado em vez de depender do texto cru de `status`.
- O card agora decide exibir:
  - faixa de `scheduled`
  - bloco de `schedule_proposed`
  - botão `AGENDAR SERVIÇO`
  com base no status normalizado da tela.

### Efeito prático

- evita que o botão `AGENDAR SERVIÇO` suma quando o refresh trouxer o mesmo estado com alias, casing ou formato diferente;
- deixa o card de `open_for_schedule` mais estável durante recargas sucessivas da aba `Disponíveis`.

### Arquivos Impactados

- `lib/features/provider/widgets/provider_service_card.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/provider/widgets/provider_service_card.dart`
  - `dart analyze lib/features/provider/widgets/provider_service_card.dart`
- Resultado:
  - `No issues found!`
  - ao final, o processo tentou gravar telemetria em `~/.dart-tool` e encontrou bloqueio de filesystem fora do workspace no sandbox atual.

## 2026-05-09 - Card passa a tratar provider_id placeholder como serviço ainda livre para agendamento

### Alterações Realizadas

- Refinado `lib/features/provider/widgets/provider_service_card.dart` na identificação de serviço “sem prestador”.
- O card agora trata `provider_id` vindo como:
  - `null`
  - string vazia
  - `'null'`
  - `'0'`
  como estado não atribuído.
- A ação `AGENDAR SERVIÇO` também passa a depender explicitamente de `widget.onSchedule != null`, reduzindo acoplamento com payload inconsistente do refresh.

### Efeito prático

- evita que o botão de agendamento e a ação de recusa sumam quando o backend retornar `provider_id` placeholder durante o reload;
- melhora a resiliência do card de `open_for_schedule` mesmo quando o payload oscilante vier parcialmente “sujo”.

### Arquivos Impactados

- `lib/features/provider/widgets/provider_service_card.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/provider/widgets/provider_service_card.dart`
  - `dart analyze lib/features/provider/widgets/provider_service_card.dart`
- Resultado:
  - `No issues found!`
  - ao final, o processo tentou gravar telemetria em `~/.dart-tool` e encontrou bloqueio de filesystem fora do workspace no sandbox atual.

## 2026-05-09 - Travel do prestador ganha fallback direto por id em service_requests

### Alterações Realizadas

- Adicionado `loadServiceRequestById(...)` em `lib/services/data_gateway.dart` para leitura direta de `service_requests` por `id`, com enriquecimento leve de `category_name`.
- Ajustado `lib/features/provider/provider_home_mobile.dart` para que a hidratação de itens da aba `Disponíveis` tente primeiro esse fallback local direto por `id` antes de depender apenas de `ApiService.getServiceDetails(...)`.
- Adicionado guard local para evitar repetir infinitamente a mesma hidratação de travel para o mesmo `serviceId`.

### Efeito prático

- reduz a dependência do payload resumido da vitrine e também do snapshot backend-first quando o objetivo é apenas recuperar coordenadas e endereço do pedido aberto;
- evita spam infinito de retries de travel para o mesmo item;
- melhora a chance de recuperar coordenadas válidas para cards `open_for_schedule` que existem corretamente no banco.

### Arquivos Impactados

- `lib/services/data_gateway.dart`
- `lib/features/provider/provider_home_mobile.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/data_gateway.dart lib/features/provider/provider_home_mobile.dart`
  - `dart analyze lib/services/data_gateway.dart lib/features/provider/provider_home_mobile.dart`
- Resultado:
  - sem erros novos das alterações;
  - permaneceram 4 warnings antigos de `unused_element` em `lib/features/provider/provider_home_mobile.dart`;
  - ao final, o processo tentou gravar telemetria em `~/.dart-tool` e encontrou bloqueio de filesystem fora do workspace no sandbox atual.

## 2026-05-09 - Card do prestador busca detalhes canônicos quando a lista disponível vier sem coordenadas

### Alterações Realizadas

- Ajustado `lib/features/provider/provider_home_mobile.dart` no carregamento de travel/distância da aba `Disponíveis`.
- Quando um item aberto para agendamento chega sem `latitude/longitude`, a tela agora tenta hidratar o serviço com `ApiService.getServiceDetails(..., scope: mobileOnly)` antes de desistir do cálculo.
- Após a hidratação, o item correspondente em `_availableServices` é atualizado em memória com os dados canônicos recuperados.

### Efeito prático

- reduz os casos em que a aba `Disponíveis` mostra o card com descrição correta, mas ainda sem endereço/distância por payload parcial;
- evita depender exclusivamente do payload resumido da vitrine de prestador para calcular deslocamento;
- melhora a chance de recuperar endereço e coordenadas sem exigir refresh manual do app.

### Arquivos Impactados

- `lib/features/provider/provider_home_mobile.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/provider/provider_home_mobile.dart`
  - `dart analyze lib/features/provider/provider_home_mobile.dart`
- Resultado:
  - sem erros novos das alterações;
  - permaneceram warnings antigos de `unused_element` já existentes no arquivo;
  - ao final, o processo tentou gravar telemetria em `~/.dart-tool` e encontrou bloqueio de filesystem fora do workspace no sandbox atual.

## 2026-05-09 - Enriquecimento da vitrine do prestador passa a recuperar coordenadas mesmo com payload parcialmente vazio

### Alterações Realizadas

- Refinado `lib/features/provider/provider_home_mobile.dart` no merge entre a lista principal de `Disponíveis` e o fallback canônico de `service_requests`.
- O enriquecimento agora também trata `latitude`, `longitude` e preços vindos como string vazia ou valor inválido como campos faltantes.
- Antes disso, o merge só preenchia quando o campo estivesse `null`, o que deixava pedidos abertos com coordenadas presentes no banco mas ausentes no card do prestador.

### Efeito prático

- reduz o erro `Invalid destination coords` em pedidos `open_for_schedule` que existem corretamente no banco;
- aumenta a chance de o card do prestador voltar a exibir distância e tempo para serviços reabertos para agendamento;
- mantém o fluxo estável do tracking sem reintroduzir modal duplicado na Home do cliente.

### Arquivos Impactados

- `lib/features/provider/provider_home_mobile.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/provider/provider_home_mobile.dart`
  - `dart analyze lib/features/provider/provider_home_mobile.dart`
- Resultado:
  - sem erros novos das alterações;
  - permaneceram 4 warnings antigos de `unused_element` em `lib/features/provider/provider_home_mobile.dart`;
  - ao final, o processo tentou gravar telemetria em `~/.dart-tool` e encontrou bloqueio de filesystem fora do workspace no sandbox atual.

## 2026-05-09 - Disponíveis do prestador volta a enriquecer pedidos abertos para agendamento

### Alterações Realizadas

- Revisado o fluxo do prestador à luz do ponto estável documentado após a remoção do modal duplicado sobre o tracking.
- Ajustado `lib/features/provider/provider_home_mobile.dart` para enriquecer itens `open_for_schedule` da aba `Disponíveis` com dados canônicos vindos do fallback de `service_requests`, mesmo quando o payload principal chegar incompleto.
- O merge agora preenche campos críticos ausentes como:
  - `description`
  - `address`
  - `profession`
  - `category_name`
  - `latitude` / `longitude`
  - preços
- Ajustado `lib/features/provider/widgets/provider_service_card.dart` para priorizar `description` no título do card antes de cair em rótulos mais genéricos.

### Efeito prático

- pedidos reabertos em `open_for_schedule` voltam a aparecer na aba `Disponíveis` do prestador com dados mais próximos do estado “normal”;
- o card deixa de cair com tanta facilidade no título genérico `Serviço`;
- o fluxo de agendamento do prestador fica mais consistente com o estado estável em que o tracking do cliente é a fonte principal da negociação e a vitrine do prestador apenas apresenta corretamente o pedido aberto.

### Arquivos Impactados

- `lib/features/provider/provider_home_mobile.dart`
- `lib/features/provider/widgets/provider_service_card.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/provider/provider_home_mobile.dart lib/features/provider/widgets/provider_service_card.dart`
  - `dart analyze lib/features/provider/provider_home_mobile.dart lib/features/provider/widgets/provider_service_card.dart`
- Resultado:
  - sem erros novos das alterações;
  - permaneceram 4 warnings antigos de `unused_element` em `lib/features/provider/provider_home_mobile.dart`;
  - ao final, o processo tentou gravar telemetria em `~/.dart-tool` e encontrou bloqueio de filesystem fora do workspace no sandbox atual.

## 2026-05-09 - Fallback do prestador deixa de depender de relação ausente e backend passa a recarregar token

### Alterações Realizadas

- Ajustado `lib/services/data_gateway.dart` para que `loadEmergencyOpenServices()` não dependa mais do embed `service_categories!category_id(name)` em `service_requests`.
- O fallback agora:
  - busca os serviços abertos direto em `service_requests`;
  - carrega os `category_id` encontrados;
  - enriquece os itens com nomes vindos de `service_categories` em uma segunda consulta.
- Ajustado `lib/core/network/backend_api_client.dart` para tentar recarregar o token via `ApiService().loadToken()` antes de montar os headers do backend quando `currentToken` estiver vazio.
- Atualizado o log de fallback em `lib/features/provider/provider_home_mobile.dart` para refletir o schema atual `service_requests`.

### Efeito prático

- elimina o erro `PGRST200` sobre relação ausente entre `service_requests` e `service_categories`;
- reduz casos em que chamadas de background ao backend sobem sem `Authorization` por token ainda não hidratado no isolate;
- deixa o fallback do home do prestador coerente com o banco atual.

### Arquivos Impactados

- `lib/services/data_gateway.dart`
- `lib/core/network/backend_api_client.dart`
- `lib/features/provider/provider_home_mobile.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/network/backend_api_client.dart lib/services/data_gateway.dart lib/features/provider/provider_home_mobile.dart`
  - `dart analyze lib/core/network/backend_api_client.dart lib/services/data_gateway.dart lib/features/provider/provider_home_mobile.dart`
- Resultado:
  - sem erros novos das alterações;
  - permaneceram 4 warnings antigos de `unused_element` em `lib/features/provider/provider_home_mobile.dart`;
  - ao final, o processo tentou gravar telemetria em `~/.dart-tool` e encontrou bloqueio de filesystem fora do workspace no sandbox atual.

## 2026-05-09 - Fluxo de disponibilidade do prestador deixa de quebrar com schema antigo e payload inconsistente

### Alterações Realizadas

- Ajustado `lib/services/api_service.dart` no método `getAvailableForSchedule()`.
- O parser agora aceita corretamente o contrato atual do backend em `/api/v1/providers/schedule/available`, que retorna `{"data": [...]}`, sem tentar indexar a lista como mapa.
- Corrigido `lib/services/data_gateway.dart` para consultar `service_requests` em vez de `service_requests_new` no fallback de serviços abertos.
- Ajustado `lib/services/provider_presence/provider_presence_service.dart` para não tratar heartbeat `401/unauthorized` como sucesso silencioso quando o `BackendApiClient` devolve `null`.

### Efeito prático

- elimina o erro `type 'String' is not a subtype of type 'int' of 'index'` no carregamento de serviços disponíveis para agendamento;
- elimina o erro de schema `Could not find the table 'public.service_requests_new'`;
- deixa o log de heartbeat refletir falha real de autenticação, em vez de registrar `ok` com resposta nula.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `lib/services/data_gateway.dart`
- `lib/services/provider_presence/provider_presence_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart lib/services/data_gateway.dart lib/services/provider_presence/provider_presence_service.dart`
  - `dart analyze lib/services/api_service.dart lib/services/data_gateway.dart lib/services/provider_presence/provider_presence_service.dart`
- Resultado:
  - sem erros novos das alterações;
  - permaneceram 3 warnings antigos de `unused_catch_clause` em `lib/services/api_service.dart`;
  - ao final, o processo tentou gravar telemetria em `~/.dart-tool` e encontrou bloqueio de filesystem fora do workspace no sandbox atual.

## 2026-05-09 - Home permite reenviar serviço aguardando retorno para nova rodada de agendamento

### Alterações Realizadas

- Ajustada a Home do cliente em `lib/features/home/home_screen.dart`.
- Quando o serviço móvel estiver em `open_for_schedule`, o bottom sheet de detalhes agora exibe a ação `Enviar novamente para agendamento`.
- A nova ação reaproveita o mesmo serviço ativo e chama `updateServiceStatus(..., 'searching_provider')`.
- Após o reenvio:
  - o app mostra feedback de sucesso;
  - recarrega o serviço ativo;
  - devolve o fluxo para uma nova rodada de busca/agendamento, sem o cliente precisar criar outra solicitação.

### Efeito prático

- O cliente consegue pegar o serviço que ficou aguardando retorno de prestadores e mandar novamente para agendamento direto pela Home.
- Isso reduz o atrito do fluxo quando a primeira rodada não avançar.

### Arquivos Impactados

- `lib/features/home/home_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/home/home_screen.dart`
  - `dart analyze lib/features/home/home_screen.dart`
- Resultado:
  - `dart analyze` reportou `No issues found!`
  - ao final, o processo tentou gravar telemetria em `~/.dart-tool` e encontrou bloqueio de filesystem fora do workspace no sandbox atual; isso não apontou erro no arquivo analisado.

## 2026-05-09 - Lógica de serviço móvel fica explícita com classificador canônico de fluxo

### Alterações Realizadas

- Revisada a base de decisão entre serviço `mobile`, `fixed` e `trip`.
- Criado o classificador central `lib/core/utils/service_flow_classifier.dart`.
- A classificação agora prioriza, nesta ordem:
  - `service_scope` / `service_kind`
  - `tipo_fluxo`
  - `is_mobile` / `is_fixed` / `at_provider`
  - `location_type` / `service_type`
  - fallback final controlado
- Aplicado o classificador em pontos críticos:
  - `lib/core/utils/fixed_schedule_gate.dart`
  - `lib/core/utils/mobile_client_navigation_gate.dart`
  - `lib/services/api_service.dart`
  - `lib/features/provider/provider_home_mobile.dart`
  - `lib/features/client/service_tracking_page.dart`
- Ajustes práticos feitos junto:
  - o gate de cliente móvel deixou de tratar “móvel” apenas como “não fixo”;
  - o roteamento do cliente agora separa melhor `trip`, `fixed` e `mobile`;
  - o tracking do cliente só inventa fallback de status vazio para `waiting_payment` quando o serviço classificado for realmente móvel;
  - corrigido o cancelamento no tracking para preservar diretamente o `ServiceDataScope` real, sem comparar com strings erradas.

### Efeito prático

- “Serviço móvel” passa a ser uma categoria explícita no código, e não apenas o resto do que sobrou após excluir fixo.
- Isso reduz ambiguidades no fluxo de agendamento, tracking e cancelamento.
- Também prepara melhor o terreno para futuras regras específicas de cada fluxo sem espalhar heurísticas duplicadas.

### Arquivos Impactados

- `lib/core/utils/service_flow_classifier.dart`
- `lib/core/utils/fixed_schedule_gate.dart`
- `lib/core/utils/mobile_client_navigation_gate.dart`
- `lib/services/api_service.dart`
- `lib/features/provider/provider_home_mobile.dart`
- `lib/features/client/service_tracking_page.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/utils/service_flow_classifier.dart lib/core/utils/fixed_schedule_gate.dart lib/core/utils/mobile_client_navigation_gate.dart lib/services/api_service.dart lib/features/provider/provider_home_mobile.dart lib/features/client/service_tracking_page.dart`
  - `flutter analyze --no-pub lib/core/utils/service_flow_classifier.dart lib/core/utils/fixed_schedule_gate.dart lib/core/utils/mobile_client_navigation_gate.dart lib/services/api_service.dart lib/features/provider/provider_home_mobile.dart lib/features/client/service_tracking_page.dart`
- Resultado:
  - sem erros novos da alteração;
  - permaneceram 7 warnings antigos já existentes:
    - 4 `unused_element` em `lib/features/provider/provider_home_mobile.dart`
    - 3 `unused_catch_clause` em `lib/services/api_service.dart`

## 2026-05-09 - Sino abre menu suspenso de notificações em vez de página dedicada

### Alterações Realizadas

- Substituída a navegação para `/notifications` por um menu suspenso de notificações no próprio contexto da tela.
- Criado o componente compartilhado `lib/features/shared/widgets/notification_dropdown_menu.dart`.
- O dropdown:
  - abre ancorado no topo direito, no padrão de inbox rápida;
  - lê as notificações em tempo real da tabela `notifications`;
  - reutiliza `NotificationItem`;
  - marca a notificação como lida ao toque;
  - encaminha a ação da notificação via `NotificationService().handleNotificationTap(...)`.
- Aplicado nos pontos principais do sino:
  - `lib/features/provider/provider_home_mobile.dart`
  - `lib/features/provider/provider_home_fixed.dart`
  - `lib/features/provider/medical_home_screen.dart`
- Efeito prático:
  - o usuário não precisa mais sair da tela atual para consultar notificações;
  - o comportamento fica mais próximo do padrão de apps e sites com menu suspenso no sino.

### Arquivos Impactados

- `lib/features/shared/widgets/notification_dropdown_menu.dart`
- `lib/features/provider/provider_home_mobile.dart`
- `lib/features/provider/provider_home_fixed.dart`
- `lib/features/provider/medical_home_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/shared/widgets/notification_dropdown_menu.dart lib/features/provider/provider_home_mobile.dart lib/features/provider/provider_home_fixed.dart lib/features/provider/medical_home_screen.dart`
  - `flutter analyze --no-pub lib/features/shared/widgets/notification_dropdown_menu.dart lib/features/provider/provider_home_mobile.dart lib/features/provider/provider_home_fixed.dart lib/features/provider/medical_home_screen.dart`
- Resultado:
  - sem erros novos da alteração;
  - permaneceram 4 warnings antigos de `unused_element` em `lib/features/provider/provider_home_mobile.dart`.

## 2026-05-09 - Proposta de agendamento ganha canal e som mais chamativos

### Alterações Realizadas

- Reforçada a apresentação de `schedule_proposal` em `lib/services/notification_service.dart`.
- Adicionado canal dedicado `schedule_proposals_channel_v1` para proposta de agendamento.
- O tipo `schedule_proposal` e também `schedule_proposal_expired` agora usam:
  - canal próprio;
  - prioridade máxima;
  - importance máxima;
  - som mais forte já existente no app (`notification_order`).
- Também foram ajustados os textos auxiliares do Android/iOS para esse grupo, com contexto de negociação de agenda.
- Efeito prático:
  - a proposta de agendamento deixa de parecer uma atualização genérica;
  - o push/local notification fica mais visível e sonoramente mais destacado para chamar a atenção do usuário.

### Arquivos Impactados

- `lib/services/notification_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/notification_service.dart`
  - `flutter analyze --no-pub lib/services/notification_service.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`

## 2026-05-09 - Notificações de sistema voltam a aparecer para proposta de agendamento

### Alterações Realizadas

- Ajustado o listener de foreground em `lib/services/notification_service.dart`.
- O app passou a disparar notificação local do sistema também para updates importantes de serviço, mesmo quando o `RemoteMessage` vier sem `message.notification` preenchido.
- Cobertos explicitamente tipos como:
  - `schedule_proposal`
  - `schedule_proposal_expired`
  - `schedule_confirmed`
  - `schedule_30m_reminder`
  - atualizações de pagamento e status do serviço
- Efeito prático:
  - o badge do sino continua vindo da tabela `notifications`;
  - além disso, quando o app estiver aberto em foreground, o Android agora mostra a notificação do sistema para proposta de agendamento em vez de atualizar só a contagem interna.

### Arquivos Impactados

- `lib/services/notification_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/notification_service.dart`
  - `flutter analyze --no-pub lib/services/notification_service.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`

## 2026-05-09 - Tracking do cliente não oferece nova edição após contraproposta enviada

### Alterações Realizadas

- Refinado o card de negociação em `lib/features/client/service_tracking_page.dart`.
- Quando o status representa uma contraproposta já enviada pelo próprio cliente, a tela agora mostra apenas o card informativo de aguardando resposta.
- O botão `ALTERAR MINHA SUGESTÃO` deixou de aparecer nesse estado.
- Efeito prático:
  - evita incentivar várias reedições seguidas enquanto a proposta atual ainda está pendente;
  - deixa o fluxo mais coerente com a regra de “aguardar a outra ponta responder”.

### Arquivos Impactados

- `lib/features/client/service_tracking_page.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/client/service_tracking_page.dart`
  - `flutter analyze --no-pub lib/features/client/service_tracking_page.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`

## 2026-05-09 - Confirmação de agendamento bloqueia o próprio autor da proposta no app

### Alterações Realizadas

- Endurecida a validação de confirmação de agenda no app para seguir a mesma regra do backend canônico.
- Em `lib/services/api_service.dart`:
  - `confirmSchedule(...)` agora recarrega o serviço antes de confirmar;
  - se `schedule_proposed_by_user_id` for o mesmo `user_id` autenticado, o app interrompe a ação localmente e lança mensagem orientando a aguardar a outra ponta ou alterar o horário.
- Em `lib/features/client/service_tracking_page.dart`, `lib/features/home/home_screen.dart` e `lib/features/home/widgets/mobile_service_card.dart`:
  - a identificação de “proposta feita por mim” deixou de depender apenas de `client_id`;
  - a UI passou a priorizar o `user_id` autenticado para decidir se deve exibir ação de aceitar ou apenas estado de aguardando resposta.
- Efeito prático:
  - evita o `POST /confirm-schedule` em cenários onde o próprio autor da proposta tenta confirmar;
  - reduz falsos positivos de botão `Aceitar agendamento` quando o snapshot do serviço vier parcial ou desalinhado.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `lib/features/client/service_tracking_page.dart`
- `lib/features/home/home_screen.dart`
- `lib/features/home/widgets/mobile_service_card.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart lib/features/client/service_tracking_page.dart lib/features/home/home_screen.dart lib/features/home/widgets/mobile_service_card.dart`
  - `flutter analyze --no-pub lib/services/api_service.dart lib/features/client/service_tracking_page.dart lib/features/home/home_screen.dart lib/features/home/widgets/mobile_service_card.dart`
- Resultado:
  - sem erros novos da alteração;
  - permaneceram 3 warnings antigos de `unused_catch_clause` em `lib/services/api_service.dart`.

## 2026-05-09 - Home do cliente deixa de sobrepor modal à proposta de agendamento

### Alterações Realizadas

- Adicionada uma proteção em `lib/features/home/home_screen.dart` para o fluxo `schedule_proposed`.
- Quando a Home tentar abrir os detalhes de um serviço nesse status, ela agora redireciona direto para `resolveClientActiveServiceRoute(...)` e retorna imediatamente.
- Efeito prático:
  - evita abrir o bottom sheet legado de detalhes por cima da tela de tracking;
  - deixa somente o card inline de proposta de agendamento dentro do tracking, sem duplicação visual.

### Arquivos Impactados

- `lib/features/home/home_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/home/home_screen.dart`
  - `flutter analyze --no-pub lib/features/home/home_screen.dart lib/features/client/service_tracking_page.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`

## 2026-05-09 - Cliente contrapropõe horário com o mesmo layout do prestador

### Alterações Realizadas

- Ajustado o card de proposta de agendamento na tela de tracking do cliente para abandonar o fluxo antigo de picker solto.
- Em `lib/features/client/service_tracking_page.dart`:
  - `Sugerir outro horário` passou a expandir um formulário inline no próprio card;
  - o formulário agora usa o mesmo padrão visual do prestador: seleção de dia, hora, botão `Agora`, `Cancelar` e ação principal para envio;
  - removida a autoabertura de um modal duplicado por cima do tracking, que estava exibindo uma versão congelada do card antigo;
  - o envio continua usando o backend canônico já existente de contraproposta.
- Efeito prático:
  - a contraproposta do cliente fica visualmente consistente com a experiência do prestador;
  - elimina o “botão feio” seguido de picker separado que quebrava a continuidade visual do fluxo;
  - deixa somente o card inline reativo da tela, permitindo que o clique realmente expanda o formulário novo.

### Arquivos Impactados

- `lib/features/client/service_tracking_page.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/client/service_tracking_page.dart`
  - `flutter analyze --no-pub lib/features/client/service_tracking_page.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`

## 2026-05-09 - Proposta de agendamento atualiza a tela do prestador na hora

### Alterações Realizadas

- Reforçada a atualização do fluxo de agendamento na Home móvel do prestador.
- Em `lib/services/data_gateway.dart`:
  - `loadMyServices()` deixou de depender de snapshot único quando o papel é `provider`;
  - agora busca diretamente em `service_requests` por `provider_id`, incluindo estados ativos relevantes como `schedule_proposed` e `scheduled`.
- Em `lib/features/provider/provider_home_mobile.dart`:
  - adicionado update otimista local após `proposeSchedule(...)`, movendo o serviço de `Disponíveis` para `Meus` com status `schedule_proposed`;
  - adicionado update otimista local após `confirmSchedule(...)`, atualizando o item para `scheduled`;
  - mantido refresh em background logo após a ação para reconciliar com o backend.
- Efeito prático:
  - ao tocar em `ENVIAR PARA CLIENTE`, a tela do prestador muda imediatamente para o estado “aguardando confirmação do cliente”;
  - quando a confirmação chegar, a lista “Meus” tem fonte mais fiel para refletir `scheduled`.

### Arquivos Impactados

- `lib/services/data_gateway.dart`
- `lib/features/provider/provider_home_mobile.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/data_gateway.dart lib/features/provider/provider_home_mobile.dart`
  - `flutter analyze --no-pub lib/services/data_gateway.dart lib/features/provider/provider_home_mobile.dart`
- Resultado:
  - sem erros novos da alteração;
  - permaneceram 4 warnings antigos já existentes de `unused_element` em `provider_home_mobile.dart`.

## 2026-05-09 - Home do prestador atualiza automaticamente após confirmação de agendamento

### Alterações Realizadas

- Ajustado o refresh prioritário da Home móvel do prestador para cobrir também o fluxo de agendamento.
- Em `lib/features/provider/provider_home_mobile.dart`:
  - `_shouldUsePaymentStatusPolling()` passou a considerar também serviços em `schedule_proposed` e `scheduled`;
  - o loop de refresh de 10 segundos deixou de ser exclusivo para pagamento restante e passou a cobrir confirmação de agenda.
- Efeito prático:
  - quando o cliente aceita uma proposta de agendamento, a home do prestador deixa de depender só do realtime/socket para refletir a mudança;
  - em até um ciclo curto de refresh, o card sai de “aguardando confirmação do cliente” para o estado atualizado.

### Arquivos Impactados

- `lib/features/provider/provider_home_mobile.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/provider/provider_home_mobile.dart`
  - `flutter analyze --no-pub lib/features/provider/provider_home_mobile.dart`
- Resultado:
  - sem erros novos da alteração;
  - permaneceram 4 warnings antigos já existentes de `unused_element` no arquivo.

## 2026-05-09 - Proposta de agendamento abre o tracking correto do serviço

### Alterações Realizadas

- Ajustado o roteamento do cliente para tratar `schedule_proposed` como fluxo de tracking, não como permanência na Home.
- Em `lib/core/constants/trip_statuses.dart`:
  - `schedule_proposed` foi removido de `ServiceStatusSets.clientHomeFallback`;
  - `schedule_proposed` foi adicionado a `ServiceStatusSets.clientTracking`.
- Em `lib/features/home/home_screen.dart`:
  - o gatilho automático de proposta de agendamento deixou de abrir o modal local da Home e passou a redirecionar para `resolveClientActiveServiceRoute(...)`;
  - o toque no banner de `Proposta de agendamento` também passou a abrir a tela de tracking do serviço em vez do sheet improvisado da Home.
- Efeito prático:
  - quando existir serviço com proposta de agendamento, o cliente abre a tela de tracking desse serviço;
  - a negociação usa o card/fluxo nativo do tracking, com os botões corretos de aceitar, contrapropor e cancelar.

### Arquivos Impactados

- `lib/core/constants/trip_statuses.dart`
- `lib/features/home/home_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/constants/trip_statuses.dart lib/features/home/home_screen.dart`
  - `flutter analyze --no-pub lib/core/constants/trip_statuses.dart lib/core/utils/mobile_client_navigation_gate.dart lib/features/home/home_screen.dart lib/features/client/service_tracking_page.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`

## 2026-05-09 - Home do cliente executa as 3 ações da proposta de agendamento

### Alterações Realizadas

- Revisada a lógica do modal `Proposta de agendamento` aberto na Home do cliente.
- Em `lib/features/home/home_screen.dart`:
  - `Aceitar agendamento` passou a confirmar diretamente via `BackendTrackingApi.confirmSchedule(...)` e depois recarregar o serviço;
  - `Responder proposta` deixou de apenas navegar e passou a abrir os pickers de data/hora, enviar contraproposta via `BackendTrackingApi.proposeSchedule(...)` e recarregar o serviço;
  - `Cancelar serviço` ganhou confirmação explícita antes de chamar `ApiService.cancelService(...)` e limpar o banner local;
  - adicionado estado de submissão para evitar toques duplicados durante a negociação.
- Efeito prático:
  - os 3 botões do modal da Home executam ação real dentro do próprio fluxo;
  - a home deixa de depender da navegação para a tela de tracking só para responder a proposta.

### Arquivos Impactados

- `lib/features/home/home_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/home/home_screen.dart`
  - `flutter analyze --no-pub lib/features/home/home_screen.dart lib/core/tracking/backend_tracking_api.dart lib/features/client/service_tracking_page.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`

## 2026-05-09 - Home do cliente deixa de abrir modal de proposta automaticamente

### Alterações Realizadas

- Revertido o ajuste anterior após alinhamento do comportamento esperado.
- Em `lib/features/home/home_screen.dart`:
  - restaurada a rotina que autoabre o bottom sheet de proposta de agendamento quando a Home detecta um serviço em `schedule_proposed`;
  - restaurados os gatilhos automáticos no refresh periódico do banner ativo e no stream realtime de serviços;
  - mantido o guard por chave (`service_id + round + scheduled_at`) para evitar reabertura infinita da mesma proposta.
- Efeito prático:
  - se existir serviço com proposta de agendamento do prestador, a Home do cliente já abre com a proposta/agenda em destaque;
  - o modal continua sem loop de reabertura para a mesma rodada da negociação.

### Arquivos Impactados

- `lib/features/home/home_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/home/home_screen.dart`
  - `flutter analyze --no-pub lib/features/home/home_screen.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`

## 2026-05-09 - Home do cliente com deduplicação e fail-fast do snapshot canônico

### Alterações Realizadas

- Reduzido o impacto dos timeouts repetidos em `GET /api/v1/home/client`.
- Em `lib/core/home/backend_home_api.dart`:
  - adicionado cache em memória de `fetchClientHome()` e `fetchProviderHome()` com TTL de 20 segundos;
  - adicionada deduplicação de requisições em voo, para múltiplos widgets/telas reutilizarem a mesma chamada em vez de dispararem várias em paralelo;
  - o fetch do snapshot da home passou a usar timeout menor (`6s`) e apenas `1` tentativa, porque o app já possui caminhos de fallback para catálogo/home e não precisa ficar preso em `10s x 3`.
- Efeito prático:
  - reduz spam de logs `Timeout GET /api/home/client`;
  - evita que várias partes da home concorram pelo mesmo endpoint ao mesmo tempo;
  - quando o backend demora, o app reaproveita snapshot recente em vez de bloquear a UX por tentativas longas.

### Arquivos Impactados

- `lib/core/home/backend_home_api.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/home/backend_home_api.dart`
  - `flutter analyze --no-pub lib/core/home/backend_home_api.dart lib/features/home/home_screen.dart lib/features/home/widgets/home_search_bar.dart lib/features/home/home_search_screen.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`

## 2026-05-09 - Proposta de agendamento passa a notificar o cliente

### Alterações Realizadas

- Ajustado o endpoint canônico `POST /api/v1/tracking/services/:id/propose-schedule` para disparar notificação para a outra ponta da negociação logo após salvar `schedule_proposed`.
- Em `../supabase/functions/api/index.ts`:
  - adicionado helper interno para envio a `push-notifications`;
  - o `propose-schedule` agora carrega `profession`, `description` e `location_type` para montar a mensagem;
  - o fluxo passou a enviar payload `schedule_proposal` com `service_id`, `scheduled_at`, `schedule_expires_at`, `schedule_round`, `schedule_client_rounds`, `schedule_provider_rounds` e `proposed_by_user_id`.
- Corrigido `../supabase/functions/push-notifications/index.ts` para persistir notificações in-app usando apenas o subconjunto de colunas compatível entre os schemas legados/atuais da tabela `notifications`, evitando falha silenciosa ao inserir `service_id`/`read` em ambientes híbridos.
- Efeito prático:
  - quando o prestador envia a proposta de agendamento, o cliente recebe a notificação in-app mesmo que o token FCM esteja inválido;
  - o endpoint canônico deixa de depender exclusivamente da fallback `mobile-schedule-negotiation` para avisar o cliente.

### Arquivos Impactados

- `../supabase/functions/api/index.ts`
- `../supabase/functions/push-notifications/index.ts`
- `RELATORIO_DEV.md`

### Deploy

- `supabase functions deploy api --project-ref mroesvsmylnaxelrhqtl`
- `supabase functions deploy push-notifications --project-ref mroesvsmylnaxelrhqtl`

### Validação

- Executado:
  - `npx deno fmt ../supabase/functions/api/index.ts`
  - `npx deno fmt ../supabase/functions/push-notifications/index.ts`
  - validação real com o serviço `f806fac0-2a60-487b-b284-fc2194273486`, autenticando como `chaveiro10@gmail.com` e chamando `POST /functions/v1/api/api/v1/tracking/services/:id/propose-schedule`
  - validação direta de `POST /functions/v1/push-notifications`
- Resultado:
  - o `propose-schedule` retornou `HTTP 200` e moveu o serviço para `schedule_proposed`;
  - a tabela `notifications` passou a registrar a linha do cliente `419` com título `Proposta de agendamento`;
  - o push FCM do cliente ainda respondeu `UNREGISTERED`, indicando token inválido/desatualizado no cadastro do usuário, mas sem impedir a notificação in-app.

## 2026-05-01 - Correção da busca na Home: fallback quando snapshot canônico indisponível

### Alterações Realizadas

- Corrigido o fluxo da tela `Buscar serviços` para evitar falso “Nenhum resultado” quando `GET /api/v1/home/client` falha ou retorna catálogo vazio.
- Em `HomeSearchScreen`:
  - adicionado `BackendApiClient` local para fallback de catálogo;
  - `_loadServiceAutocompleteCatalog()` agora tenta carregar tarefas via `GET /api/v1/tasks?active_eq=true&limit=2000` quando `snapshot.services` vem vazio;
  - no `catch` do carregamento principal, também tenta fallback REST antes de encerrar com lista vazia;
  - criado `_loadTaskCatalogFallback()` para normalizar campos (`task_name`, `profession_name`, `profession_id`, `service_type`) a partir da resposta REST.
- Efeito prático:
  - a busca continua sugerindo serviços mesmo quando o snapshot da home do cliente está indisponível;
  - reduz dependência rígida do snapshot canônico para renderização do autocomplete.

### Arquivos Impactados

- `lib/features/home/home_search_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/home/home_search_screen.dart`
  - `dart analyze lib/features/home/home_search_screen.dart lib/core/home/backend_home_api.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart tentou gravar telemetria em área somente leitura e exibiu aviso de `FileSystemException`; não representa erro do código alterado.

## 2026-04-30 - Etapa 10 iniciada: chat sem fallback de escrita direta no banco

### Alterações Realizadas

- Iniciado o fechamento da Etapa 10 (Chat e Participantes Canônicos).
- Em `DataGateway.sendChatMessage(...)`:
  - removido fallback legado `_sendChatMessageDirectly(...)` que escrevia direto em `chat_messages`;
  - envio de mensagem passa a depender somente do comando canônico `send-chat-message` (Edge/backend command).
- Efeito prático:
  - elimina divergência de regra entre comando canônico e insert direto no banco;
  - reforça o chat como fluxo server-driven para envio.

### Arquivos Impactados

- `lib/services/data_gateway.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/data_gateway.dart`
  - `dart analyze lib/services/data_gateway.dart lib/features/shared/chat_screen.dart lib/features/shared/chat_list_screen.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado.

## 2026-04-30 - Etapa 10 avanço: lista de conversas via DataGateway canônico

### Alterações Realizadas

- Continuidade da Etapa 10 com foco em reduzir dependência de `ApiService` no fluxo de chat.
- `DataGateway` ganhou `loadChatConversations()`:
  - resolve o usuário atual;
  - busca `service_id` em `service_chat_participants`;
  - carrega serviços associados para alimentar a lista de conversas.
- `ChatListScreen`:
  - removida leitura via `ApiService.getMyServices()`;
  - carregamento passa a usar `DataGateway.loadChatConversations()`.
- Efeito prático:
  - lista de conversas passa a seguir caminho de participantes canônicos;
  - menor acoplamento direto da UI de chat ao agregador legado de serviços.

### Arquivos Impactados

- `lib/services/data_gateway.dart`
- `lib/features/shared/chat_list_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/data_gateway.dart lib/features/shared/chat_list_screen.dart`
  - `dart analyze lib/services/data_gateway.dart lib/features/shared/chat_list_screen.dart lib/features/shared/chat_screen.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado.

## 2026-04-30 - Etapa 9 concluída no app: perfil/mídia com snapshot canônico no fluxo principal

### Alterações Realizadas

- Concluído o fechamento da Etapa 9 no fluxo principal de perfil/mídia do app.
- `ProviderProfileContent`:
  - leitura de perfil migrou de `ApiService.getMyProfile()` para `BackendProfileApi.fetchMyProfile()`.
- `ClientSettingsScreen`:
  - leitura de perfil migrou de `ApiService.getMyProfile()` para `BackendProfileApi.fetchMyProfile()`.
- `MediaService.loadMyAvatarBytes()`:
  - passou a usar snapshot canônico de perfil (`BackendProfileApi`) como fonte primária para resolver `avatar_url`.
- Efeito prático:
  - telas centrais de perfil e carregamento principal de avatar deixam de depender do caminho legado de perfil;
  - camada de perfil/mídia fica alinhada ao modelo backend-first adotado nas etapas anteriores.

### Arquivos Impactados

- `lib/features/provider/provider_profile_content.dart`
- `lib/features/client/client_settings_screen.dart`
- `lib/services/media_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/media_service.dart lib/features/provider/provider_profile_content.dart lib/features/client/client_settings_screen.dart`
  - `dart analyze lib/services/media_service.dart lib/features/provider/provider_profile_content.dart lib/features/client/client_settings_screen.dart lib/core/profile/backend_profile_api.dart lib/core/profile/backend_profile_state.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado.

## 2026-04-30 - Etapa 8 iniciada em passada única: domínio de saque backend-first canônico

### Alterações Realizadas

- Iniciada a Etapa 8 (Payments/Wallet/Payouts) em recorte único e seguro no domínio de pagamento do app.
- Criado `BackendPaymentApi` para comando canônico:
  - `POST /api/v1/payments/withdrawals`
- Atualizado `SupabasePaymentRepository`:
  - removido acesso direto ao Supabase (`insert` em `withdrawals`) no fluxo de domínio;
  - `requestWithdrawal(amount)` agora usa `BackendPaymentApi.requestWithdrawal(...)`;
  - em falha/resposta inválida, o repositório lança erro explícito (`throw Exception(...)`), sem fallback silencioso.
- Efeito prático:
  - o caminho de saque do domínio de pagamento passa a ser backend-first;
  - reduzido acoplamento direto do domínio de pagamentos com tabela local legada.

### Arquivos Impactados

- `lib/core/payment/backend_payment_api.dart`
- `lib/integrations/supabase/payment/supabase_payment_repository.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/payment/backend_payment_api.dart lib/integrations/supabase/payment/supabase_payment_repository.dart`
  - `dart analyze lib/core/payment/backend_payment_api.dart lib/integrations/supabase/payment/supabase_payment_repository.dart lib/domains/payment`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado.

## 2026-04-30 - Etapa 8 avanço: wallet leitura no fluxo principal via backend canônico

### Alterações Realizadas

- Continuidade da Etapa 8 no mesmo padrão backend-first para leitura de carteira.
- `BackendPaymentApi` foi expandido com:
  - `GET /api/v1/payments/wallet` (`fetchWallet()`).
- `DriverEarningsCard` (fluxo principal do prestador) foi atualizado:
  - removida leitura de carteira via `ApiService.getWalletData()`;
  - leitura agora usa `BackendPaymentApi.fetchWallet()` como fonte canônica;
  - em ausência de payload canônico, o fluxo falha explicitamente para evitar mascarar inconsistência financeira.

### Arquivos Impactados

- `lib/core/payment/backend_payment_api.dart`
- `lib/features/home/widgets/driver_earnings_card.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/payment/backend_payment_api.dart lib/features/home/widgets/driver_earnings_card.dart`
  - `dart analyze lib/core/payment/backend_payment_api.dart lib/features/home/widgets/driver_earnings_card.dart lib/integrations/supabase/payment/supabase_payment_repository.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado.

## 2026-04-30 - Etapa 8 avanço: confirmação manual de pagamento sem fallback legado

### Alterações Realizadas

- Continuidade da Etapa 8 no fluxo principal de confirmação manual de pagamento.
- Em `CentralService.confirmCashPayment()`:
  - removido fallback legado para Edge Function `confirm-cash-payment`;
  - mantido apenas o comando canônico `mp-confirm-cash-payment`;
  - mantido log de auditoria financeiro com evento único `manual_payment_confirm_ok`.
- Efeito prático:
  - confirmação manual de pagamento passa a ter um único caminho operacional canônico;
  - eliminado desvio legado que podia mascarar divergência entre versões de regra financeira.

### Arquivos Impactados

- `lib/services/central_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/central_service.dart`
  - `dart analyze lib/services/central_service.dart lib/core/payment/backend_payment_api.dart lib/features/home/widgets/driver_earnings_card.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado.

## 2026-04-30 - Etapa 8 concluída no app: remoção de caminhos financeiros legados paralelos

### Alterações Realizadas

- Fechadas as pendências residuais da Etapa 8 identificadas na auditoria.
- Removido caminho financeiro legado paralelo em `ApiService`:
  - `requestWithdrawal(...)` agora está explicitamente desativado com `UnsupportedError`;
  - `getWalletData()` agora está explicitamente desativado com `UnsupportedError`.
- Atualizado fluxo secundário de saque (diálogo de perfil do prestador):
  - `WithdrawalDialog` deixou de chamar `ApiService.requestWithdrawal(...)`;
  - passa a usar `SupabasePaymentRepository.requestWithdrawal(...)` (backend canônico).
- Limpeza de legado baixo impacto:
  - removida constante legada `confirm-cash-payment` de `EdgeFunctions`;
  - mantida apenas `mp-confirm-cash-payment` para confirmação manual.

### Arquivos Impactados

- `lib/features/provider/widgets/provider_profile_widgets.dart`
- `lib/services/api_service.dart`
- `lib/core/constants/edge_functions.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/provider/widgets/provider_profile_widgets.dart lib/services/api_service.dart lib/core/constants/edge_functions.dart`
  - `dart analyze lib/features/provider/widgets/provider_profile_widgets.dart lib/services/api_service.dart lib/core/constants/edge_functions.dart lib/core/payment/backend_payment_api.dart lib/integrations/supabase/payment/supabase_payment_repository.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado.

## 2026-04-30 - Etapa 2 concluída no app: bootstrap/perfil sem fallback local crítico

### Alterações Realizadas

- Iniciado o ciclo de fechamento das Etapas 2→7, começando pela Etapa 2 (bootstrap, sessão e perfil).
- Em `StartupService`:
  - removido fallback de perfil para `ApiService.getMyProfile()` durante inicialização;
  - criada rotina `_refreshProfileFromBackend()` exigindo `GET /api/v1/profile/me` como fonte canônica;
  - quando o backend de perfil não responde, o fluxo agora falha explicitamente para evitar hidratação silenciosa por caminho legado.
- Em `AppBootstrapCoordinator`:
  - mantida priorização de `GET /api/v1/auth/bootstrap`;
  - adicionado fail-fast para sessão autenticada sem resposta canônica do bootstrap (`/api/v1/auth/bootstrap`), eliminando fallback local para resolver rota inicial nesse cenário.

### Arquivos Impactados

- `lib/services/startup_service.dart`
- `lib/core/bootstrap/app_bootstrap_coordinator.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/startup_service.dart lib/core/bootstrap/app_bootstrap_coordinator.dart`
  - `dart analyze lib/services/startup_service.dart lib/core/bootstrap/app_bootstrap_coordinator.dart lib/core/profile/backend_profile_api.dart lib/core/bootstrap/backend_bootstrap_api.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado.

## 2026-04-30 - Etapa 3 avançada no app: home client/provider priorizando snapshot canônico

### Alterações Realizadas

- Dado continuidade ao fechamento de Etapas 1→7 com foco da Etapa 3 (Home via snapshot backend).
- Em `ProviderHomeScreen`:
  - removido fallback para `ApiService.getMyProfile()` durante bootstrap de perfil;
  - quando `fetchProviderHome()` não responde, o fluxo passa a falhar explicitamente.
- Em `HomeScreen`:
  - removido fallback de pendência fixa para leituras legadas (`ApiService` + cache local) no carregamento principal do banner;
  - removido fallback de listagem de serviços para `ApiService.getServices()` em `_loadServices()`;
  - removido fallback de serviço ativo para `findActiveService()`, `CentralService.getActiveServiceForClient()` e lista geral em `_recoverActiveService()`;
  - os blocos acima agora priorizam o snapshot canônico da home do cliente (`BackendHomeApi.fetchClientHome()`), com comportamento explícito em indisponibilidade.

### Arquivos Impactados

- `lib/features/provider/provider_home_screen.dart`
- `lib/features/home/home_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/home/home_screen.dart lib/features/provider/provider_home_screen.dart`
  - `dart analyze lib/features/home/home_screen.dart lib/features/provider/provider_home_screen.dart lib/core/home/backend_home_api.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado.

## 2026-04-30 - Etapa 4 avançada no app: tracking com mutações críticas server-driven

### Alterações Realizadas

- Continuidade do fechamento das Etapas 1→7 com foco da Etapa 4 (tracking server-driven).
- Em `ServiceTrackingPage`:
  - `confirmSchedule` migrou de `ApiService` para `BackendTrackingApi.confirmSchedule()`;
  - `proposeSchedule` migrou de `ApiService` para `BackendTrackingApi.proposeSchedule()`;
  - `confirmFinalService` migrou de `ApiService` para `BackendTrackingApi.confirmFinalService()`;
  - `cancelService` migrou de `ApiService` para `BackendTrackingApi.cancelService()`;
  - atualização de status para `provider_near` migrou para `BackendTrackingApi.updateServiceStatus()`;
  - adicionada normalização local de escopo (`auto/mobile/fixed/trip`) para payload canônico do backend.
- As mutações acima agora falham explicitamente quando o backend rejeita o comando (`ok == false`), evitando sucesso silencioso.

### Arquivos Impactados

- `lib/features/client/service_tracking_page.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/client/service_tracking_page.dart`
  - `dart analyze lib/features/client/service_tracking_page.dart lib/core/tracking/backend_tracking_api.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado.

## 2026-04-30 - Etapa 5 avançada no app: dispatch/ofertas via API de domínio

### Alterações Realizadas

- Continuidade do fechamento das Etapas 1→7 com foco da Etapa 5 (dispatch/ofertas).
- Consolidado o caminho de aceite/recusa para usar `DispatchApi` (domínio canônico) em vez de chamar `ApiService.acceptService/rejectService` diretamente nos pontos críticos.
- Alterações aplicadas:
  - `ProviderMobileService.acceptService()` agora usa `ApiService().dispatch.acceptService(...)`;
  - `ProviderMobileService.rejectService()` agora usa `ApiService().dispatch.rejectService(...)`;
  - `ServiceOfferModal` passou a aceitar/recusar via `_api.dispatch.acceptService(...)` e `_api.dispatch.rejectService(...)`;
  - `NotificationService` (ações `service_accept`/`service_reject`) passou a usar `ApiService().dispatch`.
- Efeito prático:
  - o fluxo principal de oferta agora atravessa a superfície canônica de dispatch do domínio, reduzindo acoplamento direto em chamadas dispersas do `ApiService`.

### Arquivos Impactados

- `lib/domains/dispatch/provider_mobile_service.dart`
- `lib/features/provider/widgets/service_offer_modal.dart`
- `lib/services/notification_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/domains/dispatch/provider_mobile_service.dart lib/features/provider/widgets/service_offer_modal.dart lib/services/notification_service.dart`
  - `dart analyze lib/domains/dispatch/provider_mobile_service.dart lib/features/provider/widgets/service_offer_modal.dart lib/services/notification_service.dart lib/domains/dispatch/dispatch_api.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado.

## 2026-04-30 - Etapa 6 avançada no app: realtime como transporte sem regra de navegação embutida

### Alterações Realizadas

- Continuidade do fechamento das Etapas 1→7 com foco da Etapa 6 (notifications/realtime como transporte).
- Em `RealtimeService`:
  - removida a interceptação direta do evento `service.scheduled_started` que acionava `NotificationService.handleNotificationTap(...)` dentro da camada de realtime;
  - mantido o comportamento de broadcast/event bus para os listeners registrados;
  - reduzido acoplamento entre transporte de evento e regra de navegação/apresentação.
- Efeito prático:
  - `RealtimeService` fica mais próximo do papel de transporte/orquestração;
  - decisões de UX/navegação permanecem em camadas apropriadas (notification flow/UI handlers).

### Arquivos Impactados

- `lib/services/realtime_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/realtime_service.dart`
  - `dart analyze lib/services/realtime_service.dart lib/services/notification_service.dart lib/services/support/service_offer_notification_handler.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado.

## 2026-04-30 - Hardening Etapa 7 (bloco 1): sem fallback legado em agenda core

### Alterações Realizadas

- Iniciado o hardening pós-fechamento da Etapa 7 no app Flutter, removendo fallback legado de agenda core no `SchedulingRepository`.
- Em `SupabaseSchedulingRepository`:
  - `getScheduleConfigResult()` deixou de cair para `ApiService` quando o backend falha e agora retorna estado vazio controlado;
  - `saveScheduleConfig()` deixou de tentar gravação legada no `ApiService`;
  - `getScheduleExceptions()` deixou de ler exceptions pelo caminho legado;
  - `saveScheduleExceptions()` deixou de gravar exceptions pelo caminho legado;
  - `getProviderSlots()` deixou de buscar slots do painel por `ApiService`;
  - `getProviderNextAvailableSlot()` deixou de consultar o próximo slot no legado.
- O bloco acima ficou 100% backend-first, mantendo fallback legado apenas nos fluxos de transição ainda fora deste recorte (ex.: comandos operacionais e parte dos intents).

### Arquivos Impactados

- `lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- `RELATORIO_DEV.md`

## 2026-04-30 - Hardening Etapa 7 (bloco 2): comandos operacionais sem fallback legado

### Alterações Realizadas

- Continuado o hardening pós-fechamento da Etapa 7 removendo fallback legado dos comandos operacionais de agenda.
- Em `SupabaseSchedulingRepository`:
  - `markSlotBusy()` deixou de cair para `ApiService.markSlotBusy()` quando o backend falha;
  - `bookSlot()` deixou de cair para `ApiService.bookSlot()` quando o backend falha;
  - `createManualAppointment()` deixou de cair para `ApiService.createManualAppointment()` quando o backend falha;
  - `deleteAppointment()` deixou de cair para `ApiService.deleteAppointment()` quando o backend falha.
- Com isso, o bloco operacional de slots/appointments no app ficou backend-first sem contingência legada local.

### Arquivos Impactados

- `lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
  - `dart analyze lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart lib/core/scheduling/backend_scheduling_api.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado.

## 2026-04-30 - Hardening Etapa 7 (bloco 3): intents sem fallback legado

### Alterações Realizadas

- Removido fallback legado de intents fixas no `SupabaseSchedulingRepository`.
- Em `createPendingFixedBookingIntent()`:
  - removida a chamada de contingência para `ApiService.createPendingFixedBookingIntent()`;
  - em falha do backend canônico, o fluxo agora falha explicitamente com exceção.
- Em `getPendingFixedBookingIntent()`:
  - removida a leitura legada via `ApiService.getPendingFixedBookingIntent()`.
- Em `getLatestPendingIntentForClient()`:
  - removida a leitura legada via `ApiService.getLatestPendingFixedBookingIntentForCurrentClient()`.
- Em `cancelPendingFixedBookingIntent()`:
  - removida a chamada legada via `ApiService.cancelPendingFixedBookingIntent()`.
- Observação de fronteira de domínio:
  - `confirmSchedule()` permanece delegado ao `ApiService`, pois esse comando está no domínio de `tracking` (`BackendTrackingApi`), não no `BackendSchedulingApi`.

### Arquivos Impactados

- `lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
  - `dart analyze lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart lib/core/scheduling/backend_scheduling_api.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado.

## 2026-04-30 - Separação explícita de domínio: confirmSchedule fora do ApiService

### Alterações Realizadas

- Eliminada a dependência cruzada final do `SchedulingRepository` com `ApiService` para confirmação de agenda.
- Em `SupabaseSchedulingRepository`:
  - `confirmSchedule()` deixou de delegar para `ApiService.confirmSchedule()`;
  - `confirmSchedule()` passou a chamar diretamente `BackendTrackingApi.confirmSchedule()` (domínio correto de tracking);
  - em falha do backend canônico, o método agora falha explicitamente com exceção.
- Mantida compatibilidade de assinatura do construtor para os chamadores atuais, sem uso operacional do `ApiService` dentro do repositório.

### Arquivos Impactados

- `lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
  - `dart analyze lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart lib/core/tracking/backend_tracking_api.dart lib/domains/scheduling`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado.

## 2026-04-30 - Etapa 7 hardening final: contrato de erro explícito e limpeza de injeção

### Alterações Realizadas

- Padronizado contrato de erro no `SupabaseSchedulingRepository` para evitar sucesso silencioso em mutações backend-first.
- Métodos que antes terminavam com `return;` em falha agora lançam erro explícito (`throw Exception(...)`):
  - `saveScheduleConfig()`
  - `saveScheduleExceptions()`
  - `markSlotBusy()`
  - `bookSlot()`
  - `createManualAppointment()`
  - `deleteAppointment()`
  - `cancelPendingFixedBookingIntent()`
- Atualizadas mensagens de log para refletir o estado atual:
  - removida a menção de “usando ApiService legado” dos logs do repositório.
- Limpeza de interface/injeção:
  - removido `ApiService` do construtor do `SupabaseSchedulingRepository`;
  - ajustados os pontos de instância para `SupabaseSchedulingRepository()` em:
    - `provider_schedule_settings_screen.dart`
    - `provider_home_fixed.dart`
    - `home_prestador_fixo.dart`

### Arquivos Impactados

- `lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- `lib/features/provider/provider_schedule_settings_screen.dart`
- `lib/features/provider/provider_home_fixed.dart`
- `lib/features/client/home_prestador_fixo.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart lib/features/provider/provider_schedule_settings_screen.dart lib/features/provider/provider_home_fixed.dart lib/features/client/home_prestador_fixo.dart`
  - `dart analyze lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart lib/features/provider/provider_schedule_settings_screen.dart lib/features/provider/provider_home_fixed.dart lib/features/client/home_prestador_fixo.dart lib/domains/scheduling`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado.

## 2026-04-30 - Revisão e correção dos riscos da Etapa 7

### Alterações Realizadas

- Revisados e corrigidos os pontos altos e médios encontrados na auditoria da Etapa 7.
- No `backend-api`:
  - adicionada validação de ownership/admin para rotas privadas de provider;
  - protegidas leitura/gravação de schedule, exceptions, slots e comandos de appointment contra acesso a `providerId` de terceiros;
  - `DELETE /api/v1/providers/appointments/:appointmentId` agora valida que o appointment pertence ao prestador autenticado antes de excluir;
  - confirmação de booking fixo passou a checar erros nas atualizações de intent/hold/appointment;
  - confirmação de booking fixo ganhou rollback best effort caso alguma etapa pós-criação do `agendamento_servico` falhe;
  - atualização do snapshot legado `providers.schedule_configs` deixou de derrubar o save quando a tabela/coluna legada falhar após o upsert canônico em `provider_schedules`.
- No app Flutter:
  - `BackendSchedulingApi` ganhou `confirmBookingIntent()`;
  - `SchedulingRepository` ganhou contrato para confirmar intent fixa pendente;
  - criado `ConfirmFixedBookingIntentUseCase`;
  - `SupabaseSchedulingRepository` passou a chamar `POST /api/v1/bookings/confirm`;
  - `PixPaymentScreen` passou a acionar a confirmação canônica quando o PIX fixo já está pago mas ainda não recebeu `created_service_id`;
  - removido o fallback direto Supabase de `getProviderAvailableSlots()` dentro do repositório de scheduling;
  - `getProvidersAvailableSlotsBatch()` passou a montar lote usando chamadas backend-first por provider/data, sem delegar ao batch legado do `ApiService`.

### Arquivos Impactados

- `../backend-api/src/modules/providers/providers.service.ts`
- `../backend-api/src/modules/providers/providers.controller.ts`
- `../backend-api/src/modules/home/home.service.ts`
- `lib/core/scheduling/backend_scheduling_api.dart`
- `lib/domains/scheduling/data/scheduling_repository.dart`
- `lib/domains/scheduling/domain/scheduling_usecases.dart`
- `lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- `lib/features/payment/screens/pix_payment_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/payment/screens/pix_payment_screen.dart lib/core/scheduling/backend_scheduling_api.dart lib/domains/scheduling/data/scheduling_repository.dart lib/domains/scheduling/domain/scheduling_usecases.dart lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
  - `npm run typecheck` em `backend-api`
  - `dart analyze lib/features/payment/screens/pix_payment_screen.dart lib/core/scheduling/backend_scheduling_api.dart lib/domains/scheduling lib/integrations/supabase/scheduling`
- Resultado:
  - `backend-api`: `typecheck` concluído com sucesso
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado.

## 2026-04-30 - Fechamento da Etapa 7 Scheduling e Fixed Booking

### Alterações Realizadas

- Completado o contrato explícito da Etapa 7 do roadmap.
- No `backend-api`:
  - adicionado `POST /api/v1/bookings/confirm`;
  - adicionado `POST /api/v1/bookings/intents/:intentId/confirm`;
  - a confirmação server-side de intent paga:
    - valida o `cliente_uid` autenticado;
    - retorna idempotentemente se `created_service_id` já existir;
    - cria `agendamento_servico`;
    - marca `fixed_booking_pix_intents.created_service_id`;
    - marca o slot hold como `paid`;
    - sincroniza `appointments` para ocupar a agenda do prestador.
- Também foi consolidada a cobertura backend-first dos comandos operacionais de agenda:
  - bloquear horário;
  - reservar slot;
  - criar appointment manual;
  - deletar appointment.
- Com isso, a Etapa 7 agora cobre:
  - schedule config;
  - schedule exceptions;
  - availability;
  - next available slot;
  - provider slots;
  - booking intents;
  - cancelamento de intent;
  - confirmação de booking;
  - comandos operacionais de appointment.

### Arquivos Impactados

- `../backend-api/src/modules/home/home.service.ts`
- `../backend-api/src/modules/bookings/bookings.controller.ts`
- `../backend-api/src/modules/bookings/bookings.routes.ts`
- `../backend-api/src/modules/providers/providers.service.ts`
- `../backend-api/src/modules/providers/providers.controller.ts`
- `../backend-api/src/modules/providers/providers.routes.ts`
- `lib/core/network/backend_api_client.dart`
- `lib/core/scheduling/backend_scheduling_api.dart`
- `lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/network/backend_api_client.dart lib/core/scheduling/backend_scheduling_api.dart lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
  - `npm run typecheck` em `backend-api`
  - `dart analyze lib/core/network/backend_api_client.dart lib/core/scheduling/backend_scheduling_api.dart lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- Resultado:
  - `backend-api`: `typecheck` concluído com sucesso
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado

## 2026-04-30 - Comandos de slots e appointments backend-first

### Alterações Realizadas

- Fechada a lacuna operacional principal restante da Etapa 7 no domínio de agenda do prestador.
- No `backend-api`:
  - adicionado `POST /api/v1/providers/:providerId/slots/busy`;
  - adicionado `POST /api/v1/providers/:providerId/slots/book`;
  - adicionado `POST /api/v1/providers/:providerId/appointments/manual`;
  - adicionado `DELETE /api/v1/providers/appointments/:appointmentId`;
  - `providers.service.ts` passou a assumir:
    - bloqueio manual de horário;
    - reserva de slot;
    - criação de appointment manual;
    - exclusão de appointment.
- No app Flutter:
  - `BackendApiClient` ganhou `deleteJson()`;
  - `BackendSchedulingApi` passou a suportar os comandos de slot/appointment;
  - `SupabaseSchedulingRepository.markSlotBusy()` tenta primeiro o backend novo;
  - `SupabaseSchedulingRepository.bookSlot()` tenta primeiro o backend novo;
  - `SupabaseSchedulingRepository.createManualAppointment()` tenta primeiro o backend novo;
  - `SupabaseSchedulingRepository.deleteAppointment()` tenta primeiro o backend novo;
  - fallback via `ApiService` foi preservado.
- Estratégia aplicada:
  - completar a cobertura backend-first da agenda operacional;
  - manter compatibilidade com o painel do prestador;
  - preservar fallback durante a transição.

### Arquivos Impactados

- `../backend-api/src/modules/providers/providers.service.ts`
- `../backend-api/src/modules/providers/providers.controller.ts`
- `../backend-api/src/modules/providers/providers.routes.ts`
- `lib/core/network/backend_api_client.dart`
- `lib/core/scheduling/backend_scheduling_api.dart`
- `lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/network/backend_api_client.dart lib/core/scheduling/backend_scheduling_api.dart lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
  - `npm run typecheck` em `backend-api`
  - `dart analyze lib/core/network/backend_api_client.dart lib/core/scheduling/backend_scheduling_api.dart lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- Resultado:
  - `backend-api`: `typecheck` concluído com sucesso
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado

## 2026-04-30 - Tela de configuração de agenda usando SchedulingRepository

### Alterações Realizadas

- Avançada a migração da UI de agenda do prestador para consumir o domínio `scheduling`.
- Em `provider_schedule_settings_screen.dart`:
  - removidas as chamadas diretas a `ApiService.getScheduleConfig()`;
  - removidas as chamadas diretas a `ApiService.saveScheduleConfig()`;
  - removidas as chamadas diretas a `ApiService.getScheduleExceptions()`;
  - removidas as chamadas diretas a `ApiService.saveScheduleExceptions()`;
  - adicionada instância de `SupabaseSchedulingRepository`;
  - a tela agora usa:
    - `SchedulingRepository.getScheduleConfigResult()`;
    - `SchedulingRepository.getScheduleExceptions()`;
    - `SchedulingRepository.saveScheduleConfig()`;
    - `SchedulingRepository.saveScheduleExceptions()`.
- `ApiService` ficou apenas como compatibilidade temporária para resolver a identidade do prestador atual quando o cache local ainda não está hidratado.
- Estratégia aplicada:
  - preservar a UI e o payload visual atual;
  - trocar a origem das operações para o repositório de domínio;
  - aproveitar os endpoints backend-first adicionados nas fatias anteriores.

### Arquivos Impactados

- `lib/features/provider/provider_schedule_settings_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/provider/provider_schedule_settings_screen.dart`
  - `dart analyze lib/features/provider/provider_schedule_settings_screen.dart lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart lib/core/scheduling/backend_scheduling_api.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado

## 2026-04-30 - Schedule exceptions e provider slots via backend

### Alterações Realizadas

- Avançada mais uma fatia da Etapa 7 para reduzir leituras/mutações diretas de agenda no app.
- No `backend-api`:
  - adicionado `GET /api/v1/providers/:providerId/schedule/exceptions`;
  - adicionado `PUT /api/v1/providers/:providerId/schedule/exceptions`;
  - adicionado `GET /api/v1/providers/:providerId/slots`;
  - `providers.service.ts` passou a montar os slots enriquecidos do painel do prestador com:
    - `appointments`;
    - `agendamento_servico`;
    - `fixed_booking_slot_holds`;
    - `fixed_booking_pix_intents`;
    - dados básicos do cliente.
  - a gravação de exceptions mantém rollback best effort em caso de falha.
- No app Flutter:
  - `BackendSchedulingApi` passou a suportar exceptions e slots do prestador;
  - `SupabaseSchedulingRepository.getScheduleExceptions()` tenta primeiro o backend novo;
  - `SupabaseSchedulingRepository.saveScheduleExceptions()` tenta primeiro o backend novo;
  - `SupabaseSchedulingRepository.getProviderSlots()` tenta primeiro o backend novo;
  - fallback via `ApiService` mantido enquanto as telas terminam a migração.
- Estratégia aplicada:
  - manter o contrato de mapas já usado pelo painel do prestador;
  - mover a montagem enriquecida dos slots para o backend;
  - deixar o repository como ponte de transição.

### Arquivos Impactados

- `../backend-api/src/modules/providers/providers.service.ts`
- `../backend-api/src/modules/providers/providers.controller.ts`
- `../backend-api/src/modules/providers/providers.routes.ts`
- `lib/core/scheduling/backend_scheduling_api.dart`
- `lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/scheduling/backend_scheduling_api.dart lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
  - `npm run typecheck` em `backend-api`
  - `dart analyze lib/core/scheduling/backend_scheduling_api.dart lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- Resultado:
  - `backend-api`: `typecheck` concluído com sucesso
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado

## 2026-04-30 - Schedule config via backend providers

### Alterações Realizadas

- Avançada a fatia de configuração de agenda da Etapa 7.
- No `backend-api`:
  - adicionado `GET /api/v1/providers/:providerId/schedule`;
  - adicionado `PUT /api/v1/providers/:providerId/schedule`;
  - a leitura de agenda agora consolida:
    - `provider_schedules` por `provider_id`;
    - `provider_schedules` por `provider_uid`;
    - fallback legado de `providers.schedule_configs`;
    - flags `usedLegacyFallback` e `foundProviderSchedules`.
  - a gravação server-side faz `upsert` em `provider_schedules` e mantém o snapshot legado em `providers.schedule_configs`.
- No app Flutter:
  - `BackendApiClient` ganhou `putJson()`;
  - `BackendSchedulingApi` passou a suportar leitura e gravação de agenda;
  - `SupabaseSchedulingRepository.getScheduleConfigResult()` tenta primeiro o backend novo;
  - `SupabaseSchedulingRepository.saveScheduleConfig()` tenta primeiro o backend novo;
  - o fallback via `ApiService` foi mantido durante a transição.
- Estratégia aplicada:
  - reduzir o caminho direto via Supabase/`ApiService`;
  - preservar o contrato tipado de `ScheduleConfigResult`;
  - manter compatibilidade com telas que ainda dependem do snapshot legado.

### Arquivos Impactados

- `../backend-api/src/modules/providers/providers.service.ts`
- `../backend-api/src/modules/providers/providers.controller.ts`
- `../backend-api/src/modules/providers/providers.routes.ts`
- `lib/core/network/backend_api_client.dart`
- `lib/core/scheduling/backend_scheduling_api.dart`
- `lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/network/backend_api_client.dart lib/core/scheduling/backend_scheduling_api.dart lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
  - `npm run typecheck` em `backend-api`
  - `dart analyze lib/core/network/backend_api_client.dart lib/core/scheduling/backend_scheduling_api.dart lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- Resultado:
  - `backend-api`: `typecheck` concluído com sucesso
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado

## 2026-04-30 - Availability e próximo slot via backend providers

### Alterações Realizadas

- Avançada mais uma fatia da Etapa 7 do roadmap para tirar disponibilidade de agenda do acesso direto prioritário no app.
- No `backend-api`:
  - criado o módulo `providers`;
  - adicionado `GET /api/v1/providers/:providerId/availability`;
  - adicionado `GET /api/v1/providers/:providerId/next-available-slot`;
  - o backend passou a montar disponibilidade considerando:
    - `provider_schedules`;
    - fallback legado de `providers.schedule_configs`;
    - `appointments` bloqueantes;
    - `fixed_booking_slot_holds` ativos;
    - snapshots de `fixed_booking_pix_intents` para decidir bloqueio de hold;
    - `requiredDurationMinutes` para marcar slot selecionável.
- No app Flutter:
  - `BackendSchedulingApi` passou a buscar disponibilidade e próximo slot pelos novos endpoints;
  - `SupabaseSchedulingRepository.getProviderAvailableSlots()` tenta primeiro o backend novo;
  - `SupabaseSchedulingRepository.getProviderNextAvailableSlot()` tenta primeiro o backend novo;
  - o fallback Supabase/`ApiService` foi preservado durante a transição.
- Estratégia aplicada:
  - manter a tela consumindo o mesmo contrato de slots;
  - mover a fonte prioritária da regra para o backend;
  - deixar a implementação local como contingência até a cobertura do backend amadurecer.

### Arquivos Impactados

- `../backend-api/src/app.ts`
- `../backend-api/src/modules/providers/providers.service.ts`
- `../backend-api/src/modules/providers/providers.controller.ts`
- `../backend-api/src/modules/providers/providers.routes.ts`
- `lib/core/scheduling/backend_scheduling_api.dart`
- `lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/scheduling/backend_scheduling_api.dart lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
  - `npm run typecheck` em `backend-api`
  - `dart analyze lib/core/scheduling/backend_scheduling_api.dart lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- Resultado:
  - `backend-api`: `typecheck` concluído com sucesso
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado

## 2026-04-30 - Bookings canônico para intents de agendamento fixo

### Alterações Realizadas

- Iniciada a consolidação da Etapa 7 do roadmap, separando booking/scheduling do módulo `home`.
- No `backend-api`:
  - criado o módulo `bookings`;
  - adicionado `POST /api/v1/bookings/intents`;
  - adicionado `GET /api/v1/bookings/intents/latest`;
  - adicionado `GET /api/v1/bookings/intents/:intentId`;
  - adicionado `POST /api/v1/bookings/intents/:intentId/cancel`;
  - os novos endpoints reutilizam a regra server-side já criada para:
    - criação de `fixed_booking_pix_intents`;
    - criação de `fixed_booking_slot_holds`;
    - consulta de intent pendente com `slot_hold`;
    - cancelamento validado pelo `cliente_uid` autenticado.
- No app Flutter:
  - criado `BackendSchedulingApi`;
  - `SupabaseSchedulingRepository.createPendingFixedBookingIntent()` agora tenta primeiro `POST /api/v1/bookings/intents`;
  - `SupabaseSchedulingRepository.getPendingFixedBookingIntent()` agora tenta primeiro `GET /api/v1/bookings/intents/:intentId`;
  - `SupabaseSchedulingRepository.getLatestPendingIntentForClient()` agora tenta primeiro `GET /api/v1/bookings/intents/latest`;
  - `SupabaseSchedulingRepository.cancelPendingFixedBookingIntent()` agora tenta primeiro `POST /api/v1/bookings/intents/:intentId/cancel`;
  - o fallback legado via `ApiService` foi mantido para compatibilidade.
- Estratégia aplicada:
  - avançar por etapa curta e verificável;
  - preservar o endpoint antigo de `home` temporariamente;
  - começar a posicionar Fixed Booking no domínio canônico de `bookings`.

### Arquivos Impactados

- `../backend-api/src/app.ts`
- `../backend-api/src/modules/bookings/bookings.controller.ts`
- `../backend-api/src/modules/bookings/bookings.routes.ts`
- `lib/core/scheduling/backend_scheduling_api.dart`
- `lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/scheduling/backend_scheduling_api.dart lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
  - `npm run typecheck` em `backend-api`
  - `dart analyze lib/core/scheduling/backend_scheduling_api.dart lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- Resultado:
  - `backend-api`: `typecheck` concluído com sucesso
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado

## 2026-04-30 - Criação de PIX pendente fixo backend-first

### Alterações Realizadas

- Avançada a próxima mutação crítica da `home` para o backend novo.
- No `backend-api`:
  - criado `POST /api/v1/home/pending-fixed`;
  - `home.service.ts` passou a criar server-side:
    - `fixed_booking_pix_intents`
    - `fixed_booking_slot_holds`
  - o cancelamento de pendência fixa passou a validar o `cliente_uid` autenticado antes de cancelar.
- No app Flutter:
  - `BackendHomeApi` passou a suportar `createPendingFixedBookingIntent()`;
  - `ApiService.createPendingFixedBookingIntent()` agora tenta primeiro o backend novo e só depois cai no fluxo legado direto no Supabase.
- Estratégia aplicada:
  - manter fallback legado durante a transição
  - reduzir criação direta de intenção/hold pelo cliente
  - concentrar a autoridade do PIX pendente fixo no backend

### Arquivos Impactados

- `../backend-api/src/modules/home/home.service.ts`
- `../backend-api/src/modules/home/home.controller.ts`
- `../backend-api/src/modules/home/home.routes.ts`
- `lib/core/home/backend_home_api.dart`
- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/home/backend_home_api.dart lib/services/api_service.dart`
  - `npm run typecheck` em `backend-api`
  - `dart analyze lib/core/home/backend_home_api.dart lib/services/api_service.dart`
- Resultado:
  - `backend-api`: `typecheck` concluído com sucesso
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado

## 2026-04-30 - Home pendente fixa e update de status entrando em backend-first

### Alterações Realizadas

- Avançada automaticamente a próxima etapa sugerida para mutações críticas da `home` e das telas de serviço.
- No `backend-api`:
  - `home` ganhou comando server-side para cancelamento de pendência fixa:
    - `POST /api/v1/home/pending-fixed/:intentId/cancel`
  - `tracking` ganhou comando server-side para atualização simples de status:
    - `POST /api/v1/tracking/services/:serviceId/status`
  - o backend passou a assumir:
    - cancelamento de `fixed_booking_pix_intents`
    - cancelamento de `fixed_booking_slot_holds`
    - atualização de status básico para fluxos fixo e móvel
- No app Flutter:
  - `BackendHomeApi` passou a suportar `cancelPendingFixedBookingIntent()`;
  - `BackendTrackingApi` passou a suportar `updateServiceStatus()`;
  - `ApiService.cancelPendingFixedBookingIntent()` agora tenta primeiro o backend novo;
  - `ApiService.updateServiceStatus()` agora tenta primeiro o backend novo.
- Estratégia aplicada:
  - começar a tirar mutações críticas da `home` do caminho direto do cliente
  - reduzir updates sensíveis direto em tabela
  - manter fallback legado para preservar compatibilidade durante a transição

### Arquivos Impactados

- `../backend-api/src/modules/home/home.service.ts`
- `../backend-api/src/modules/home/home.controller.ts`
- `../backend-api/src/modules/home/home.routes.ts`
- `../backend-api/src/modules/tracking/tracking.service.ts`
- `../backend-api/src/modules/tracking/tracking.controller.ts`
- `../backend-api/src/modules/tracking/tracking.routes.ts`
- `lib/core/home/backend_home_api.dart`
- `lib/core/tracking/backend_tracking_api.dart`
- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/home/backend_home_api.dart lib/core/tracking/backend_tracking_api.dart lib/services/api_service.dart`
  - `npm run typecheck` em `backend-api`
  - `dart analyze lib/core/home/backend_home_api.dart lib/core/tracking/backend_tracking_api.dart lib/services/api_service.dart lib/features/home/home_screen.dart lib/features/client/service_tracking_page.dart`
- Resultado:
  - `backend-api`: `typecheck` concluído com sucesso
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado

## 2026-04-30 - Negociação de agenda do tracking entrando em backend-first

### Alterações Realizadas

- Avançado automaticamente o próximo passo sugerido para o bloco de agenda/propostas do tracking.
- No `backend-api`:
  - criados novos comandos no módulo `tracking`:
    - `POST /api/v1/tracking/services/:serviceId/confirm-schedule`
    - `POST /api/v1/tracking/services/:serviceId/propose-schedule`
  - o backend passou a assumir diretamente a confirmação e a contraproposta de agendamento para o fluxo fixo;
  - para fluxos ainda não totalmente migrados, o frontend continua com fallback para o caminho legado.
- No app Flutter:
  - `BackendTrackingApi` passou a suportar:
    - `confirmSchedule()`
    - `proposeSchedule()`
  - `ApiService.confirmSchedule()` e `ApiService.proposeSchedule()` agora tentam primeiro essas mutações server-side e só depois usam o fluxo legado.
- Estratégia aplicada:
  - backend-first progressivo
  - mover primeiro a autoridade da mutação
  - manter fallback enquanto a negociação móvel ainda depende do legado/Edge Function atual

### Arquivos Impactados

- `../backend-api/src/modules/tracking/tracking.service.ts`
- `../backend-api/src/modules/tracking/tracking.controller.ts`
- `../backend-api/src/modules/tracking/tracking.routes.ts`
- `lib/core/tracking/backend_tracking_api.dart`
- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/tracking/backend_tracking_api.dart lib/services/api_service.dart`
  - `npm run typecheck` em `backend-api`
  - `dart analyze lib/core/tracking/backend_tracking_api.dart lib/services/api_service.dart lib/features/client/service_tracking_page.dart`
- Resultado:
  - `backend-api`: `typecheck` concluído com sucesso
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado

## 2026-04-30 - Mutações backend-first do tracking: confirmar, cancelar e reclamar

### Alterações Realizadas

- Avançada a migração backend-first do tracking além da leitura, começando a mover também mutações sensíveis para o `backend-api`.
- No `backend-api`:
  - criados novos comandos no módulo `tracking`:
    - `POST /api/v1/tracking/services/:serviceId/confirm-final`
    - `POST /api/v1/tracking/services/:serviceId/cancel`
    - `POST /api/v1/tracking/services/:serviceId/complaints`
  - a camada `tracking.service.ts` passou a concentrar:
    - confirmação final do serviço
    - cancelamento por escopo
    - abertura de reclamação/reembolso
  - o backend agora começa a assumir também a decisão operacional dessas ações em vez de deixar tudo no app.
- No app Flutter:
  - `BackendApiClient` ganhou `postJson()`;
  - `BackendTrackingApi` passou a suportar:
    - `confirmFinalService()`
    - `cancelService()`
    - `submitComplaint()`
  - `ApiService` agora tenta essas mutações server-side primeiro e só depois cai no caminho legado:
    - `confirmFinalService()`
    - `cancelService()`
    - `submitServiceComplaint()`
- Estratégia aplicada:
  - usar o `ApiService` como ponte de transição
  - trocar primeiro a autoridade da mutação
  - manter fallback local para evitar interrupção brusca enquanto a migração completa não termina

### Arquivos Impactados

- `../backend-api/src/modules/tracking/tracking.service.ts`
- `../backend-api/src/modules/tracking/tracking.controller.ts`
- `../backend-api/src/modules/tracking/tracking.routes.ts`
- `lib/core/network/backend_api_client.dart`
- `lib/core/tracking/backend_tracking_api.dart`
- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/network/backend_api_client.dart lib/core/tracking/backend_tracking_api.dart lib/services/api_service.dart`
  - `npm run typecheck` em `backend-api`
  - `dart analyze lib/core/network/backend_api_client.dart lib/core/tracking/backend_tracking_api.dart lib/services/api_service.dart lib/features/client/service_tracking_page.dart`
- Resultado:
  - `backend-api`: `typecheck` concluído com sucesso
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado

## 2026-04-30 - Resumo financeiro e ações finais no snapshot do tracking

### Alterações Realizadas

- Avançada automaticamente a etapa seguinte do tracking para mover mais regra de negócio visual para o backend.
- No `backend-api`:
  - o snapshot `GET /api/v1/tracking/services/:serviceId/snapshot?scope=...` passou a devolver também:
    - `paymentSummary`
    - `finalActions`
  - `paymentSummary` agora consolida no backend:
    - `entryPaid`
    - `remainingPaid`
    - `providerArrived`
    - `showPayDeposit`
    - `showPayRemaining`
    - `inSecurePaymentPhase`
    - `securePaymentAmount`
    - `depositPaymentAmount`
    - `pixDisplayAmount`
    - `pixDisplayLabel`
    - `providerDistanceMeters`
    - `cancelBlockedByProximity`
  - `finalActions` agora consolida no backend:
    - `showConfirm`
    - `showCompletedMessage`
    - `canCancel`
- No app Flutter:
  - `BackendTrackingSnapshotState` passou a suportar `paymentSummary` e `finalActions`;
  - `ServiceTrackingPage` passou a guardar o último snapshot backend-first carregado;
  - a tela agora prioriza esses resumos server-side para decisões de:
    - pagamento restante
    - pagamento de entrada
    - fase de pagamento seguro
    - valor/label do PIX exibido
    - bloqueio de cancelamento por proximidade
    - confirmação final
    - mensagem de conclusão
    - disponibilidade de cancelamento
- Estratégia aplicada:
  - reduzir regra condicional espalhada na `ServiceTrackingPage`
  - aproximar o tracking do modelo “backend decide, frontend renderiza”
  - manter fallback local enquanto a transição ainda convive com lógica derivada na tela

### Arquivos Impactados

- `../backend-api/src/modules/tracking/tracking.service.ts`
- `lib/core/tracking/backend_tracking_snapshot_state.dart`
- `lib/features/client/service_tracking_page.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `sleep 10`
  - `npm run typecheck` em `backend-api`
  - `dart format lib/core/tracking/backend_tracking_snapshot_state.dart lib/features/client/service_tracking_page.dart`
  - `dart analyze lib/core/tracking/backend_tracking_snapshot_state.dart lib/features/client/service_tracking_page.dart`
- Resultado:
  - `backend-api`: `typecheck` concluído com sucesso
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado

## 2026-04-30 - Provider location inicial incluída no snapshot do tracking

### Alterações Realizadas

- Evoluída a migração backend-first do tracking para incluir a localização inicial do prestador no snapshot principal.
- No `backend-api`:
  - o snapshot `GET /api/v1/tracking/services/:serviceId/snapshot?scope=...` passou a devolver também:
    - `providerLocation`
  - o backend agora consulta `provider_locations` e entrega o último ponto conhecido do prestador junto com o restante do estado da tela.
- No app Flutter:
  - `BackendTrackingSnapshotState` passou a suportar `providerLocation`;
  - `ServiceTrackingPage` agora aplica a localização do prestador vinda do snapshot backend-first logo em:
    - `_loadOnce()`
    - `_refreshNow()`
  - com isso, a tela não depende apenas do polling inicial do `DataGateway` para exibir o primeiro ponto conhecido do prestador no tracking.
- Estratégia aplicada:
  - enriquecer progressivamente o snapshot do tracking
  - reduzir dependência de leituras paralelas locais
  - manter streams/realtime como complemento, não como única fonte inicial

### Arquivos Impactados

- `../backend-api/src/modules/tracking/tracking.service.ts`
- `lib/core/tracking/backend_tracking_snapshot_state.dart`
- `lib/features/client/service_tracking_page.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `npm run typecheck` em `backend-api`
  - `dart format lib/core/tracking/backend_tracking_snapshot_state.dart lib/features/client/service_tracking_page.dart`
  - `dart analyze lib/core/tracking/backend_tracking_snapshot_state.dart lib/features/client/service_tracking_page.dart`
- Resultado:
  - `backend-api`: `typecheck` concluído com sucesso
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado

## 2026-04-30 - Snapshot backend-first de disputa para a ServiceTrackingPage

### Alterações Realizadas

- Continuada a migração backend-first do tracking, agora atacando a leitura paralela de disputa/reembolso.
- No `backend-api`:
  - expandido o módulo `tracking` com `GET /api/v1/tracking/services/:serviceId/snapshot?scope=...`;
  - o novo snapshot devolve em uma única resposta:
    - `service`
    - `openDispute`
    - `latestPrimaryDispute`
  - o backend passou a centralizar também a leitura de `service_disputes` usada pelo tracking do cliente.
- No app Flutter:
  - criado `BackendTrackingSnapshotState`;
  - `BackendTrackingApi` passou a suportar `fetchTrackingSnapshot()`;
  - `ServiceTrackingPage` agora tenta buscar o snapshot backend-first antes de cair nas leituras legadas para:
    - `_loadOnce()`
    - `_refreshNow()`
  - com isso, a tela começou a consumir em um único payload:
    - detalhes do serviço
    - disputa aberta
    - disputa principal mais recente
- Estratégia aplicada:
  - reduzir recomposição local de estado
  - aproximar o tracking do modelo “screen snapshot” vindo do backend
  - manter fallback legado enquanto a migração ainda convive com DataGateway e outras leituras pontuais

### Arquivos Impactados

- `../backend-api/src/modules/tracking/tracking.service.ts`
- `../backend-api/src/modules/tracking/tracking.controller.ts`
- `../backend-api/src/modules/tracking/tracking.routes.ts`
- `lib/core/tracking/backend_tracking_api.dart`
- `lib/core/tracking/backend_tracking_snapshot_state.dart`
- `lib/features/client/service_tracking_page.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `npm run typecheck` em `backend-api`
  - `dart format lib/core/tracking/backend_tracking_api.dart lib/core/tracking/backend_tracking_snapshot_state.dart lib/features/client/service_tracking_page.dart`
  - `dart analyze lib/core/tracking/backend_tracking_api.dart lib/core/tracking/backend_tracking_snapshot_state.dart lib/features/client/service_tracking_page.dart`
- Resultado:
  - `backend-api`: `typecheck` concluído com sucesso
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado

## 2026-04-30 - Snapshot backend-first de service details para tracking

### Alterações Realizadas

- Avançada a Etapa 3 com foco em desmontar a leitura detalhada de serviço concentrada no `ApiService`.
- No `backend-api`:
  - expandido o módulo `tracking` para também servir detalhes completos de serviço;
  - criado `GET /api/v1/tracking/services/:serviceId?scope=...`;
  - o endpoint suporta os escopos:
    - `auto`
    - `fixedOnly`
    - `mobileOnly`
    - `tripOnly`
  - o backend agora monta snapshot detalhado para:
    - serviço fixo (`agendamento_servico`) com enriquecimento e `client_locations` em best effort
    - serviço móvel (`service_requests_new`) com flatten de cliente, prestador, categoria e valores derivados
  - quando o serviço não existe no escopo solicitado, o backend devolve snapshot canônico de `not_found/deleted`.
- No app Flutter:
  - `BackendTrackingApi` passou a suportar `fetchServiceDetails()`;
  - `ApiService.getServiceDetails()` agora tenta primeiro o snapshot detalhado vindo do backend novo;
  - quando o backend novo não responder, o método continua usando a montagem legada local como fallback.
- Estratégia aplicada:
  - corte backend-first pela API de detalhe
  - sem quebrar telas consumidoras existentes
  - aproveitando o próprio `ApiService` como ponte de transição para reduzir retrabalho imediato em múltiplas telas

### Arquivos Impactados

- `../backend-api/src/modules/tracking/tracking.service.ts`
- `../backend-api/src/modules/tracking/tracking.controller.ts`
- `../backend-api/src/modules/tracking/tracking.routes.ts`
- `lib/core/tracking/backend_tracking_api.dart`
- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `npm run typecheck` em `backend-api`
  - `dart format lib/core/tracking/backend_tracking_api.dart lib/services/api_service.dart`
  - `dart analyze lib/core/tracking/backend_tracking_api.dart lib/services/api_service.dart lib/features/client/service_tracking_page.dart`
- Resultado:
  - `backend-api`: `typecheck` concluído com sucesso
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado

## 2026-04-30 - Provider Home backend-first e snapshot canônico de serviço ativo

### Alterações Realizadas

- Dada continuidade à Etapa 3 com foco em reduzir mais peso de bootstrap e tracking dentro do `ApiService`.
- No `backend-api`:
  - `GET /api/v1/home/provider` passou a devolver snapshot real de bootstrap do prestador;
  - o snapshot de `home/provider` agora inclui `profile` com:
    - `userId`
    - `role`
    - `isFixedLocation`
    - `isMedical`
    - `subRole`
  - criado o novo módulo `tracking`;
  - adicionado `GET /api/v1/tracking/active-service`;
  - o endpoint novo devolve:
    - `user`
    - `service`
    - `statusView`
  - o serviço de tracking backend-first agora resolve serviço ativo para:
    - cliente
    - prestador/driver
    - fluxo móvel
    - fluxo fixo
  - incluída normalização mínima de serviço fixo para manter compatibilidade com navegação e leitura de status do app.
- No app Flutter:
  - criado `BackendProviderHomeState` para formalizar `GET /api/v1/home/provider`;
  - `BackendHomeApi` passou a suportar `fetchProviderHome()`;
  - `ProviderHomeScreen` agora tenta bootstrapar fixed/mobile pelo backend novo antes de cair em `getMyProfile()`;
  - criado `BackendTrackingApi` e `BackendActiveServiceState` para formalizar `GET /api/v1/tracking/active-service`;
  - `ApiService.findActiveService()` agora tenta primeiro o snapshot ativo vindo do backend novo e só depois cai no resolvedor legado.
- Estratégia aplicada:
  - backend-first com fallback local
  - mantendo aparência e fluxo atuais
  - reduzindo a autoridade operacional do `ApiService` em bootstrap e estado ativo

### Arquivos Impactados

- `../backend-api/src/modules/home/home.service.ts`
- `../backend-api/src/modules/tracking/tracking.service.ts`
- `../backend-api/src/modules/tracking/tracking.controller.ts`
- `../backend-api/src/modules/tracking/tracking.routes.ts`
- `../backend-api/src/app.ts`
- `lib/core/home/backend_home_api.dart`
- `lib/core/home/backend_provider_home_state.dart`
- `lib/core/tracking/backend_active_service_state.dart`
- `lib/core/tracking/backend_tracking_api.dart`
- `lib/features/provider/provider_home_screen.dart`
- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `npm run typecheck` em `backend-api`
  - `dart format lib/core/home/backend_home_api.dart lib/core/home/backend_provider_home_state.dart lib/core/tracking/backend_active_service_state.dart lib/core/tracking/backend_tracking_api.dart lib/features/provider/provider_home_screen.dart lib/services/api_service.dart`
  - `dart analyze lib/core/home/backend_home_api.dart lib/core/home/backend_provider_home_state.dart lib/core/tracking/backend_active_service_state.dart lib/core/tracking/backend_tracking_api.dart lib/features/provider/provider_home_screen.dart lib/services/api_service.dart`
- Resultado:
  - `backend-api`: `typecheck` concluído com sucesso
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro do código validado

## 2026-04-30 - Primeiro snapshot backend-first da Home do cliente

### Alterações Realizadas

- Iniciado o corte backend-first da `HomeScreen` do cliente, mantendo a aparência atual e introduzindo snapshot server-side como fonte prioritária.
- No `backend-api`:
  - `GET /api/v1/home/client` deixou de ser contrato vazio e passou a montar snapshot real da home;
  - o snapshot agora devolve:
    - `services`
    - `activeService`
    - `pendingFixedPayment`
    - `upcomingAppointment`
  - a montagem do snapshot consulta o Supabase Admin para:
    - lista de serviços do cliente
    - serviço ativo não terminal mais recente
    - última pendência de PIX de agendamento fixo com `slot_hold`
    - próximo agendamento confirmado do cliente com resumo do prestador
- No app Flutter:
  - criado `BackendHomeApi` para consumir `GET /api/v1/home/client`;
  - criado `BackendClientHomeState` como modelo local do snapshot da home;
  - `HomeScreen` passou a tentar o snapshot backend-first antes de cair na lógica legada para:
    - `_loadServices()`
    - `_loadPendingFixedPaymentBanner()`
    - `_loadUpcomingAppointment()`
    - `_recoverActiveService()`
  - adicionado cache curto em memória do snapshot da home para evitar múltiplas chamadas redundantes durante o bootstrap da tela.
- Estratégia aplicada:
  - preservar UI e comportamento visual atuais
  - mover primeiro a composição dos dados
  - manter fallback local enquanto a Etapa 3 ganha cobertura

### Arquivos Impactados

- `../backend-api/src/modules/home/home.service.ts`
- `lib/core/home/backend_home_api.dart`
- `lib/core/home/backend_client_home_state.dart`
- `lib/features/home/home_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `npm run typecheck` em `backend-api`
  - `dart format lib/core/home/backend_client_home_state.dart lib/core/home/backend_home_api.dart lib/features/home/home_screen.dart`
  - `dart analyze lib/core/home/backend_client_home_state.dart lib/core/home/backend_home_api.dart lib/features/home/home_screen.dart`
- Resultado:
  - `backend-api`: `typecheck` concluído com sucesso
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a falhar ao gravar telemetria em área somente leitura; o aviso ocorreu depois da análise e não representa erro no código validado

## 2026-04-30 - Primeiro corte real do frontend no bootstrap backend-first

### Alterações Realizadas

- Implementado o primeiro acoplamento real entre o app Flutter e o novo `backend-api` no fluxo de bootstrap.
- No backend:
  - `auth/bootstrap` passou a aceitar autenticação opcional em vez de exigir sessão obrigatória;
  - criado `hydrateAuthContext` para hidratar contexto JWT quando houver `Bearer token`;
  - `auth/bootstrap` agora devolve:
    - `authenticated`
    - `userId`
    - `role`
    - `isMedical`
    - `isFixedLocation`
    - `registerStep`
    - `nextRoute`
  - `AuthService` passou a consultar a linha do usuário no Supabase quando houver `supabase_uid`, para começar a montar bootstrap com dados reais.
- No app Flutter:
  - criado `BackendBootstrapApi` para chamar `GET /api/v1/auth/bootstrap`;
  - criado `BackendBootstrapState` como modelo local do payload de bootstrap;
  - o `AppBootstrapCoordinator` agora tenta buscar a decisão inicial de rota no backend novo antes de cair no resolver local legado;
  - adicionado `persistBootstrapIdentity()` em `ApiService` para hidratar `role`, `isMedical`, `isFixedLocation` e `register_step` a partir do bootstrap server-side.
- Em evolução da Etapa 2:
  - criado `BackendApiClient` como client HTTP reutilizável para o `backend-api`;
  - criado `BackendProfileApi` e `BackendProfileState` para formalizar `GET /api/v1/profile/me` no app;
  - `StartupService` agora prioriza `profile/me` da nova API para hidratar o perfil local antes de cair em `ApiService.getMyProfile()`;
  - `ApiService` passou a aceitar `applyBackendProfileSnapshot()` para absorver snapshot de perfil vindo do backend novo;
  - `profile.service.ts` no `backend-api` foi expandido para incluir `sub_role` e saldo efetivo derivado de `providers.wallet_balance`.
- Estratégia aplicada:
  - `backend-first` com fallback local
  - sem desligar o caminho legado abruptamente
  - priorizando resposta do backend quando disponível

### Arquivos Impactados

- `../backend-api/src/middleware/auth.ts`
- `../backend-api/src/modules/auth/auth.service.ts`
- `../backend-api/src/modules/auth/auth.routes.ts`
- `../backend-api/src/modules/profile/profile.service.ts`
- `../backend-api/src/app.ts`
- `lib/core/network/backend_api_client.dart`
- `lib/core/profile/backend_profile_api.dart`
- `lib/core/profile/backend_profile_state.dart`
- `lib/core/bootstrap/backend_bootstrap_api.dart`
- `lib/core/bootstrap/backend_bootstrap_state.dart`
- `lib/core/bootstrap/app_bootstrap_coordinator.dart`
- `lib/services/startup_service.dart`
- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `npm run typecheck` em `backend-api`
  - `dart analyze lib/core/bootstrap/app_bootstrap_coordinator.dart lib/core/bootstrap/backend_bootstrap_api.dart lib/core/bootstrap/backend_bootstrap_state.dart lib/services/api_service.dart`
- Resultado:
  - `backend-api`: `typecheck` concluído com sucesso
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart voltou a tentar gravar telemetria fora da área gravável e gerou `FileSystemException`, mas isso ocorreu depois da análise e não indica falha do código validado

## 2026-04-30 - Roadmap executivo por etapas para migração backend-first total

### Alterações Realizadas

- Criado o roadmap executivo por etapas da migração `backend-first total`.
- O novo documento transforma a estratégia arquitetural em projeto de execução com:
  - etapas numeradas
  - objetivo por fase
  - escopo de backend
  - escopo de frontend
  - critério de conclusão
  - resultado de negócio esperado
- O roadmap foi estruturado para que a etapa final seja explicitamente:
  - `app 100% funcional via API`

### Arquivos Impactados

- `docs/backend-first-execution-roadmap.md`
- `RELATORIO_DEV.md`

### Validação

- Validação documental/manual:
  - conferida aderência ao `backend-first-total-migration-plan.md`
  - conferida progressão lógica entre fundação, migração por domínio e etapa final
  - conferido que cada etapa tem critério de conclusão orientado a corte real do frontend

## 2026-04-30 - Fundação inicial do `backend-api` para migração backend-first total

### Alterações Realizadas

- Criada a fundação real do novo `backend-api` em `/home/servirce/Documentos/101/projeto-central-/backend-api`.
- Definido stack inicial com:
  - `Express`
  - `TypeScript`
  - `Zod`
  - `@supabase/supabase-js`
- Criados os arquivos-base do projeto:
  - `package.json`
  - `tsconfig.json`
  - `.env.example`
- Criada a fundação HTTP e de segurança:
  - `src/app.ts`
  - `src/server.ts`
  - `src/config/env.ts`
  - `src/config/supabase.ts`
  - `src/middleware/request-context.ts`
  - `src/middleware/auth.ts`
  - `src/middleware/error-handler.ts`
  - `src/shared/http/api-response.ts`
  - `src/shared/errors/app-error.ts`
- Criado suporte inicial para contexto autenticado por request:
  - `src/shared/security/jwt-payload.ts`
  - `src/shared/security/request-context.ts`
  - `src/types/express.d.ts`
- Criados os primeiros módulos `v1` da API para iniciar a migração do app:
  - `auth`
  - `profile`
  - `home`
- Endpoints iniciais já estruturados:
  - `GET /health`
  - `GET /api/v1/auth/bootstrap`
  - `GET /api/v1/profile/me`
  - `GET /api/v1/home/client`
  - `GET /api/v1/home/provider`
- O módulo `profile` já foi ligado ao Supabase Admin Client para leitura inicial da tabela `users` por `supabase_uid`.
- Os módulos `auth` e `home` foram criados inicialmente como contratos de bootstrap/snapshot, com payloads simples para acelerar a convergência backend-first.
- Instaladas as dependências iniciais do `backend-api` com `npm install`.
- Validada a base TypeScript com `npm run typecheck`.
- Durante a instalação, houve alerta de engine por dependências do ecossistema Supabase pedindo Node `>=20`, enquanto o ambiente atual está em Node `18.19.1`; apesar disso, a instalação concluiu e o `typecheck` passou nesta etapa.

### Arquivos Impactados

- `../backend-api/package.json`
- `../backend-api/tsconfig.json`
- `../backend-api/.env.example`
- `../backend-api/src/app.ts`
- `../backend-api/src/server.ts`
- `../backend-api/src/config/env.ts`
- `../backend-api/src/config/supabase.ts`
- `../backend-api/src/middleware/request-context.ts`
- `../backend-api/src/middleware/auth.ts`
- `../backend-api/src/middleware/error-handler.ts`
- `../backend-api/src/shared/http/api-response.ts`
- `../backend-api/src/shared/errors/app-error.ts`
- `../backend-api/src/shared/security/jwt-payload.ts`
- `../backend-api/src/shared/security/request-context.ts`
- `../backend-api/src/types/express.d.ts`
- `../backend-api/src/modules/auth/auth.service.ts`
- `../backend-api/src/modules/auth/auth.controller.ts`
- `../backend-api/src/modules/auth/auth.routes.ts`
- `../backend-api/src/modules/profile/profile.service.ts`
- `../backend-api/src/modules/profile/profile.controller.ts`
- `../backend-api/src/modules/profile/profile.routes.ts`
- `../backend-api/src/modules/home/home.service.ts`
- `../backend-api/src/modules/home/home.controller.ts`
- `../backend-api/src/modules/home/home.routes.ts`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `npm install`
  - `npm run typecheck`
- Resultado:
  - dependências instaladas com sucesso
  - `typecheck` concluído com sucesso
- Validação estrutural/manual:
  - conferida a criação dos arquivos centrais do `backend-api`
  - conferida a composição dos módulos `auth`, `profile` e `home`
  - conferida a presença do envelope JSON padronizado e do middleware de autenticação

## 2026-04-30 - Plano oficial de migração backend-first total

### Alterações Realizadas

- Criado o plano oficial de migração agressiva do app para arquitetura `backend-first total`.
- O novo documento define:
  - objetivo arquitetural
  - responsabilidades de frontend e backend
  - política de segurança com JWT, autorização, idempotência e auditoria
  - estrutura alvo de `backend-api`
  - contratos API `v1` por domínio
  - ondas de migração para remover a lógica crítica do frontend
- O plano assume explicitamente que o frontend deve convergir para casca de apresentação, mantendo aparência e fluxos visuais, enquanto o backend se torna dono total da regra crítica.

### Arquivos Impactados

- `docs/backend-first-total-migration-plan.md`
- `RELATORIO_DEV.md`

### Validação

- Validação documental/manual:
  - conferida coerência com `docs/master-implementation-plan.md`
  - conferida coerência com `docs/domain-architecture.md`
  - conferida coerência com os domínios já documentados em `dispatch`, `tracking`, `payments`, `notifications` e `presence-profile`

## 2026-04-29 - Correção do bloqueio ao acessar a home no web após callback OAuth

### Alterações Realizadas

- Endurecido o bootstrap crítico do app para evitar splash infinita quando dependências remotas demorarem no web.
- `ThemeService.loadTheme()` agora aplica `timeout` de 4 segundos em `RemoteThemeService.initialize()`.
- Quando o carregamento remoto do tema excede esse limite, o app segue com o tema local padrão em vez de permanecer preso na `SplashScreen`.
- Ajustado o `NotificationService` no web para não tentar registrar Web Push/FCM quando:
  - o host é `localhost`
  - a `VAPID_KEY` não foi fornecida no build
- Com isso, o app deixa de insistir no `FirebaseMessaging.getToken()` em cenários web incompletos, reduzindo o ruído de `401 Unauthorized` no endpoint `fcmregistrations.googleapis.com`.
- A correção foi pensada para o fluxo visto na URL com `?code=...`, em que o usuário retorna do OAuth e precisa sair da splash mesmo se integrações secundárias ainda não estiverem prontas.

### Arquivos Impactados

- `lib/services/theme_service.dart`
- `lib/services/notification_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/services/theme_service.dart`
  - `dart analyze lib/services/notification_service.dart`
- Resultado:
  - os comandos ficaram pendurados no ambiente atual e precisaram ser encerrados por `timeout`, então não houve confirmação automática completa via analyzer nesta sessão.
- Validação manual de código:
  - confirmado o import de `dart:async` para suportar `TimeoutException`
  - confirmada a nova guarda `_shouldSkipWebPush` aplicada aos pontos de `requestPermission`, `getToken` e `deleteToken`

## 2026-04-29 - Publicação remota da fundação backend-first e primeira superfície `provider_search`

### Alterações Realizadas

- Publicada no Supabase remoto a fundação backend-first criada localmente:
  - Edge Function `get_screen` atualizada
  - nova Edge Function `post_action`
  - migration `20260429190000_backend_first_remote_shell_foundation.sql`
- A migration foi aplicada com sucesso no projeto remoto `mroesvsmylnaxelrhqtl`.
- O banco remoto agora possui a fundação de operação remota:
  - `remote_screen_definitions`
  - `remote_screen_variants`
  - `remote_screen_publications`
  - `remote_action_policies`
  - `remote_content_blocks`
- Também foram publicados os seeds operacionais iniciais para:
  - `provider_search`
  - `service_payment`
- As flags remotas de rollout para as novas superfícies passaram a existir também em `app_configs`:
  - `flag.remote_ui.provider_search.enabled`
  - `kill_switch.remote_ui.provider_search`
  - `flag.remote_ui.service_payment.enabled`
  - `kill_switch.remote_ui.service_payment`

### Primeira Superfície Migrada

- A primeira superfície conectada ao modelo backend-first foi `provider_search`.
- A tela `MobileProviderSearchPage` agora envia contexto dinâmico para o backend remoto usando:
  - `service_id`
  - `status`
  - `payment_status`
  - `headline`
  - `subtitle`
  - `service_label`
  - `show_map`
- Foi criado o modelo `RemoteScreenQuery` para permitir requests remotos com `screenKey + context`.
- O `remoteScreenProvider` foi evoluído para usar esse contexto e repassá-lo ao `RemoteScreenRequest`.
- `RemoteScreenBody` agora aceita `context` por tela.
- O painel inferior da busca de prestador em `MobileProviderSearchPage` foi conectado à tela remota `provider_search`, com:
  - renderização remota por JSON quando disponível
  - fallback integral para o timeline e comportamento nativos atuais
- O app também foi atualizado para conhecer as novas flags locais/defaults de:
  - `provider_search`
  - `service_payment`

### Arquivos Impactados

- `lib/domains/remote_ui/models/remote_screen_query.dart`
- `lib/domains/remote_ui/presentation/remote_screen_providers.dart`
- `lib/core/remote_ui/remote_screen_body.dart`
- `lib/features/client/mobile_provider_search_page.dart`
- `lib/services/remote_config_service.dart`
- `../supabase/functions/get_screen/index.ts`
- `../supabase/functions/post_action/index.ts`
- `../supabase/migrations/20260429190000_backend_first_remote_shell_foundation.sql`
- `../supabase/config.toml`
- `RELATORIO_DEV.md`

### Publicação Executada

- Executado com sucesso:
  - `supabase db push --yes -p [database password]`
  - `supabase functions deploy get_screen`
  - `supabase functions deploy post_action`
- Resultado:
  - migration `20260429190000_backend_first_remote_shell_foundation.sql` aplicada no remoto
  - `get_screen` publicada no remoto
  - `post_action` publicada no remoto

### Validação

- Executado:
  - `dart analyze lib/features/client/mobile_provider_search_page.dart lib/core/remote_ui/remote_screen_body.dart lib/domains/remote_ui/presentation/remote_screen_providers.dart lib/domains/remote_ui/models/remote_screen_query.dart lib/services/remote_config_service.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - após a análise, o Dart tentou gravar telemetria fora da área gravável e exibiu `FileSystemException`, mas isso ocorreu depois da análise e não representa falha do código validado.
- Executado:
  - `flutter test test/domains/remote_ui/remote_screen_request_test.dart test/integrations/supabase/remote_ui/supabase_remote_screen_repository_test.dart test/core/remote_ui/action_registry_test.dart test/domains/remote_ui/remote_action_response_test.dart`
- Resultado:
  - `All tests passed!`

## 2026-04-29 - Fundação backend-first com `post_action`, schema remoto expandido e telas publicadas por banco

### Alterações Realizadas

- Implementada a primeira fundação concreta do modelo `backend-first` no app e no Supabase, mantendo a migração gradual sobre a base atual.
- O contrato de carregamento remoto de telas foi ampliado para aceitar `context` segmentado em `RemoteScreenRequest`, permitindo que o backend passe a decidir a UI com mais contexto de runtime.
- Criados os contratos de ação remota:
  - `RemoteActionRequest`
  - `RemoteActionResponse`
- Adicionada a integração `SupabaseRemoteActionApi`, que chama a nova Edge Function `post_action`.
- O executor remoto padrão agora:
  - envia comandos para o backend via `post_action`
  - aplica `message`, `next_screen`, `refresh_screen` e `effects`
  - preserva fallback local para comandos que ainda não migraram totalmente para backend
- Expandida a whitelist oficial de comandos para o modelo backend-first, incluindo:
  - `open_service_tracking`
  - `return_home`
  - `refresh_search_status`
  - `cancel_service_request`
  - `show_search_details`
  - `generate_platform_pix`
  - `open_pix_screen`
  - `retry_pix_generation`
  - `confirm_direct_payment_intent`
  - `open_chat`
  - `confirm_service_completion`
- Expandido o schema de `remote_ui` com novos tipos oficiais de componente:
  - `warning_card`
  - `info_card`
  - `amount_card`
  - `timeline_step`
  - `dialog`
  - `bottom_sheet`
- O renderer remoto agora suporta renderização inicial desses novos tipos para permitir migrar:
  - busca de prestador
  - pagamento
  - blocos operacionais guiados por backend
- O repositório remoto de telas passou a ter cliente Supabase lazy no fluxo de cache, evitando bootstrap obrigatório em testes e leituras offline.

### Backend / Supabase

- Atualizada a Edge Function `get_screen` para:
  - tentar carregar a tela publicada do banco primeiro
  - respeitar `screen_key`, `app_role` e `platform`
  - cair para os fallbacks hardcoded atuais quando ainda não houver publicação em banco
- Criada a nova Edge Function `post_action` com contrato JSON para:
  - `action_type`
  - `command_key`
  - `screen_key`
  - `component_id`
  - `arguments`
  - `entity_ids`
- A `post_action` já centraliza resposta backend-first para comandos como:
  - `open_provider_home`
  - `open_service_tracking`
  - `open_active_service`
  - `return_home`
  - `open_support`
  - `refresh_home`
  - `refresh_search_status`
  - `retry_pix_generation`
  - `show_search_details`
  - `confirm_direct_payment_intent`
  - `toggle_dispatch_availability`
  - `accept_ride`
  - `reject_ride`
- Criada a migration de fundação do shell remoto:
  - `../supabase/migrations/20260429190000_backend_first_remote_shell_foundation.sql`
- A migration cria as tabelas:
  - `remote_screen_definitions`
  - `remote_screen_variants`
  - `remote_screen_publications`
  - `remote_action_policies`
  - `remote_content_blocks`
- A migration também semeia a base inicial para:
  - `provider_search`
  - `service_payment`
- Atualizado `../supabase/config.toml` com:
  - `[functions.get_screen]`
  - `[functions.post_action]`

### Arquivos Impactados

- `lib/domains/remote_ui/models/remote_screen_request.dart`
- `lib/domains/remote_ui/models/remote_action_request.dart`
- `lib/domains/remote_ui/models/remote_action_response.dart`
- `lib/core/remote_ui/command_registry.dart`
- `lib/core/remote_ui/component_registry.dart`
- `lib/core/remote_ui/remote_component_renderer.dart`
- `lib/integrations/supabase/remote_ui/supabase_remote_action_api.dart`
- `lib/integrations/remote_ui/default_remote_action_executor.dart`
- `lib/integrations/supabase/remote_ui/supabase_remote_screen_repository.dart`
- `../supabase/functions/get_screen/index.ts`
- `../supabase/functions/post_action/index.ts`
- `../supabase/migrations/20260429190000_backend_first_remote_shell_foundation.sql`
- `../supabase/config.toml`
- `test/core/remote_ui/action_registry_test.dart`
- `test/domains/remote_ui/remote_action_response_test.dart`
- `test/domains/remote_ui/remote_screen_request_test.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/core/remote_ui lib/domains/remote_ui lib/integrations/remote_ui lib/integrations/supabase/remote_ui test/core/remote_ui/action_registry_test.dart test/domains/remote_ui/remote_action_response_test.dart test/domains/remote_ui/remote_screen_request_test.dart test/integrations/supabase/remote_ui/supabase_remote_screen_repository_test.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - após a análise, o Dart tentou gravar telemetria fora da área gravável e exibiu `FileSystemException`, mas isso ocorreu depois da análise e não representa falha do código validado.
- Executado:
  - `flutter test test/core/remote_ui/action_registry_test.dart test/domains/remote_ui/remote_action_response_test.dart test/domains/remote_ui/remote_screen_request_test.dart test/integrations/supabase/remote_ui/supabase_remote_screen_repository_test.dart`
- Resultado:
  - `All tests passed!`

## 2026-04-29 - Correção do erro ao gerar PIX em prestador móvel com pagamento direto

### Alterações Realizadas

- Corrigido o fluxo da tela `payment_screen` para não forçar mais `pix` quando o método recebido pelo fluxo é pagamento direto ao prestador.
- A tela agora normaliza e respeita `initialMethod`, com tratamento específico para:
  - `pix`
  - `pix_direct`
  - `cash`
  - `card_machine`
- Quando o método selecionado é direto ao prestador, o app:
  - não tenta chamar `mp-get-pix-data`
  - não tenta gerar QR da plataforma
  - exibe orientação de que o pagamento será combinado diretamente com o prestador
- Corrigido também o `service_tracking_page` para separar claramente:
  - `PIX da plataforma` com QR inline
  - `pagamento direto ao prestador` sem geração de QR do app
- O acompanhamento do serviço agora só tenta auto-carregar PIX inline quando o método do serviço suporta cobrança de plataforma.
- Para métodos diretos como `pix_direct`, `dinheiro` e `card_machine`, a tela mostra um card informativo em vez de disparar erro de geração de PIX.

### Arquivos Impactados

- `lib/features/client/payment_screen.dart`
- `lib/features/client/service_tracking_page.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/features/client/payment_screen.dart lib/features/client/service_tracking_page.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - após a análise, o Dart tentou gravar telemetria em arquivo fora da área gravável e exibiu `FileSystemException`, mas isso ocorreu depois da análise e não indica erro de compilação nos arquivos alterados.

## 2026-04-29 - Publicação parcial no Supabase remoto para remote_ui e driver_home

### Alterações Realizadas

- Preparada a migration de backend para o novo contrato remoto de `app_configs` em:
  - `../supabase/migrations/20260429153000_remote_ui_runtime_config_contract.sql`
- A migration adiciona/normaliza suporte a:
  - `category`
  - `platform_scope`
  - `is_active`
  - `revision`
- A migration também faz upsert das chaves operacionais do rollout remoto:
  - `flag.remote_ui.enabled`
  - `flag.remote_ui.help.enabled`
  - `flag.remote_ui.home_explore.enabled`
  - `flag.remote_ui.driver_home.enabled`
  - `kill_switch.remote_ui.global`
  - `kill_switch.remote_ui.help`
  - `kill_switch.remote_ui.home_explore`
  - `kill_switch.remote_ui.driver_home`
  - `flag.runtime_diagnostics.visible`
- Atualizada a Edge Function:
  - `../supabase/functions/get_screen/index.ts`
- A função agora suporta:
  - `patch_version`
  - `environment`
  - tela remota `driver_home`
  - payload com `commands_used`
  - componentes novos voltados para operação remota do prestador
- A função `get_screen` foi publicada com sucesso no projeto remoto:
  - project ref `mroesvsmylnaxelrhqtl`
- Para alinhar o histórico local com o remoto e permitir futuros `db push`, foram copiados para `../supabase/migrations/` os arquivos históricos ausentes que existiam apenas em `../supabase/migrations_legacy/`.
- Também foram criados placeholders locais para versões remotas históricas que já existiam no banco, mas não tinham arquivo correspondente no diretório `../supabase/migrations/`.
- Após alinhar o histórico local e usar a senha do banco remoto, a migration abaixo foi aplicada com sucesso no projeto remoto:
  - `20260429153000_remote_ui_runtime_config_contract.sql`

### Publicação Executada

- Executado com sucesso:
  - `supabase functions deploy get_screen`
- Executado com sucesso:
  - `supabase db push --yes -p [database password]`
- Resultado:
  - função `get_screen` publicada no remoto
  - migration `20260429153000_remote_ui_runtime_config_contract.sql` aplicada no banco remoto

### Arquivos Impactados

- `../supabase/functions/get_screen/index.ts`
- `../supabase/migrations/20260429153000_remote_ui_runtime_config_contract.sql`
- `../supabase/migrations/` com cópia local das migrations históricas ausentes
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `supabase functions deploy get_screen`
- Resultado:
  - `Deployed Functions on project mroesvsmylnaxelrhqtl: get_screen`
- Executado:
  - `supabase migration list`
- Resultado:
  - histórico local e remoto ficou alinhado
  - `20260429153000_remote_ui_runtime_config_contract.sql` aparece aplicada local e remotamente

## 2026-04-29 - Driver Home remota com comandos whitelistados e engine expandida

### Alterações Realizadas

- Evoluída a engine `remote_ui` para suportar um modelo de app quase todo remoto sem aceitar endpoint arbitrário vindo do JSON.
- Implementado suporte oficial ao novo modelo de ação semântica:
  - `action.type = command`
  - `command_key`
  - `arguments`
- Criado o registry seguro de comandos em `lib/core/remote_ui/command_registry.dart` com whitelist inicial para:
  - `accept_ride`
  - `reject_ride`
  - `open_offer`
  - `open_support`
  - `start_navigation`
  - `refresh_home`
  - `toggle_dispatch_availability`
  - `open_provider_home`
  - `open_active_service`
  - `show_command_feedback`
- O `ActionRegistry` agora valida comandos remotos explicitamente e continua rejeitando ações fora da allowlist.
- O executor remoto foi expandido para mapear comandos a rotinas locais conhecidas e auditáveis, sem permitir:
  - endpoint livre
  - método HTTP livre
  - execução arbitrária de backend no cliente
- Implementadas execuções reais de comandos remotos para:
  - aceitar oferta/corrida
  - recusar oferta/corrida
  - abrir modal de oferta
  - abrir suporte
  - iniciar navegação nativa
  - alternar disponibilidade operacional do prestador
  - abrir tela ativa do serviço
- Criada a primeira superfície operacional forte com fallback:
  - `driver_home`
- A tela do prestador agora entra por `DriverHomeRemoteScreen`, que:
  - tenta renderizar `driver_home` via `RemoteScreenBody`
  - cai para a `ProviderHomeMobile` atual quando o payload remoto falha, está desabilitado ou não existe
- A `ProviderHomeScreen` mantém o fluxo para prestador fixo local, mas o fluxo mobile agora pode ser guiado remotamente.
- Expandido o `RemoteConfigService` com flags e kill switches para a nova superfície:
  - `flag.remote_ui.driver_home.enabled`
  - `kill_switch.remote_ui.driver_home`
- O `feature_set` enviado ao backend agora inclui `driver_home_v1`.
- Expandido o contrato de componente remoto com novos tipos úteis para home operacional e formulários:
  - `badge`
  - `status_block`
  - `form`
  - `field_group`
  - `input`
- Implementado `RemoteFormWidget` para formulários remotos básicos com:
  - campos renderizados por schema
  - validação mínima local
  - merge dos valores em `action.arguments.form_values`
- O renderer remoto agora injeta contexto operacional nas ações:
  - `component_id`
  - `screen_key`
- A observabilidade dos comandos remotos foi ampliada com logging de:
  - `command_key`
  - `screen_key`
  - `component_id`
  - `service_id`
  - `revision`
  - `store_version`
  - `patch_version`
- Adicionado suporte de allowlist para novos destinos de configuração remota:
  - rota `provider_home`
  - link `support_email`
- O contrato de `RemoteAction` foi ampliado para parsear `command_key`.
- Adicionados testes cobrindo:
  - componente remoto com `status_block` e `command`
  - support do registry para componentes remotos novos
  - aceitação e rejeição de comandos whitelistados

### Arquivos Impactados

- `lib/domains/remote_ui/models/remote_action.dart`
- `lib/core/remote_ui/action_registry.dart`
- `lib/core/remote_ui/command_registry.dart`
- `lib/core/remote_ui/component_registry.dart`
- `lib/core/remote_ui/remote_component_renderer.dart`
- `lib/core/remote_ui/remote_form_widget.dart`
- `lib/core/remote_ui/route_key_registry.dart`
- `lib/core/remote_ui/link_key_registry.dart`
- `lib/core/remote_ui/remote_screen_body.dart`
- `lib/integrations/remote_ui/default_remote_action_executor.dart`
- `lib/services/remote_config_service.dart`
- `lib/domains/remote_ui/presentation/remote_screen_providers.dart`
- `lib/features/provider/provider_home_screen.dart`
- `lib/features/provider/driver_home_remote_screen.dart`
- `lib/features/provider/widgets/driver_home_remote_fallback.dart`
- `test/core/remote_ui/action_registry_test.dart`
- `test/core/remote_ui/component_registry_test.dart`
- `test/domains/remote_ui/remote_screen_model_test.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `env HOME=/tmp dart analyze lib/core/remote_ui lib/domains/remote_ui lib/integrations/remote_ui lib/features/provider/provider_home_screen.dart lib/features/provider/driver_home_remote_screen.dart lib/features/provider/widgets/driver_home_remote_fallback.dart lib/services/remote_config_service.dart test/core/remote_ui/action_registry_test.dart test/core/remote_ui/component_registry_test.dart test/domains/remote_ui/remote_screen_model_test.dart`
- Resultado:
  - `No issues found!`
- Tentado:
  - `env HOME=/tmp flutter test test/core/remote_ui/action_registry_test.dart test/core/remote_ui/component_registry_test.dart test/domains/remote_ui/remote_screen_model_test.dart test/services/remote_config_service_test.dart test/domains/remote_ui/remote_screen_request_test.dart test/integrations/supabase/remote_ui/supabase_remote_screen_repository_test.dart`
- Resultado:
  - bloqueado pelo ambiente local com erro `snap-confine has elevated permissions and is not confined`
  - sem evidência de erro Dart nessas suítes; bloqueio de runtime da ferramenta

## 2026-04-29 - Blindagem de release com OTA, runtime snapshot e controle remoto versionado

### Alterações Realizadas

- Implementada a base operacional da estrategia de atualizacao continua em 3 camadas:
  - OTA orientado a patch Dart
  - remote config e kill switch via Supabase
  - remote UI restrita a superficies nao criticas
- Criada a nova fundacao de runtime em `lib/core/runtime/` com:
  - `AppRuntimeSnapshot`
  - `AppRuntimeService`
- O app agora expõe internamente um snapshot de execucao com:
  - `store version`
  - `patch version`
  - `environment`
  - flags ativas
  - origem das telas remotas carregadas
- O runtime passou a registrar contexto operacional em logs e no Crashlytics:
  - versao da build da loja
  - versao de patch OTA via `SHOREBIRD_PATCH_NUMBER`
  - ambiente
  - flags carregadas
  - source das telas remotas
- Criado o contrato tipado de configuracao remota `AppConfigEntry` em `lib/core/config/app_config_entry.dart`.
- Evoluido `RemoteConfigService` para um contrato remoto versionavel com suporte a:
  - `key`
  - `value`
  - `category`
  - `platform_scope`
  - `is_active`
  - `revision`
- O `RemoteConfigService` agora separa semanticamente:
  - feature flags
  - kill switches
  - configuracao operacional
- Definidos defaults e convencoes para o rollout inicial:
  - `flag.remote_ui.enabled`
  - `flag.remote_ui.help.enabled`
  - `flag.remote_ui.home_explore.enabled`
  - `kill_switch.remote_ui.global`
  - `kill_switch.remote_ui.help`
  - `kill_switch.remote_ui.home_explore`
- O `remote_ui` agora respeita kill switch local antes mesmo de chamar o backend.
- `RemoteScreenRequest` passou a enviar contexto adicional para segmentacao:
  - `patch_version`
  - `environment`
  - conjunto de flags ativas
- `RemoteScreenBody` foi endurecido para:
  - cair imediatamente no fallback nativo quando a tela remota estiver desabilitada por flag
  - registrar a origem `local`, `cache` ou `remote`
  - reportar falhas operacionais do carregamento remoto
- `SupabaseRemoteScreenRepository` passou a reportar falhas de fetch/cache para a camada de runtime observavel.
- Adicionado banner diagnostico reutilizavel `AppRuntimeDiagnosticBanner` para exibir:
  - store version
  - patch version
  - environment
- O banner foi integrado inicialmente apenas nas superficies nao criticas:
  - `help`
  - `home_explore`
- Criado o playbook operacional `docs/ota-release-playbook.md` com:
  - politica de uso de patch OTA
  - criterio para exigir nova versao de loja
  - fluxo de aprovacao
  - convencoes de chaves remotas
  - limites de uso do `remote_ui`
- Adicionados testes cobrindo:
  - serializacao do contexto de runtime no request remoto
  - restauracao de flags tipadas do cache remoto
  - kill switch desligando `remote_ui` imediatamente

### Arquivos Impactados

- `lib/core/config/app_config_entry.dart`
- `lib/core/runtime/app_runtime_snapshot.dart`
- `lib/core/runtime/app_runtime_service.dart`
- `lib/services/remote_config_service.dart`
- `lib/core/bootstrap/app_environment.dart`
- `lib/core/bootstrap/app_bootstrap_coordinator.dart`
- `lib/services/startup_service.dart`
- `lib/core/remote_ui/remote_screen_body.dart`
- `lib/domains/remote_ui/presentation/remote_screen_providers.dart`
- `lib/domains/remote_ui/models/remote_screen_request.dart`
- `lib/integrations/supabase/remote_ui/supabase_remote_screen_repository.dart`
- `lib/widgets/app_runtime_diagnostic_banner.dart`
- `lib/features/shared/help_screen.dart`
- `lib/features/home/home_explore_screen.dart`
- `test/services/remote_config_service_test.dart`
- `test/domains/remote_ui/remote_screen_request_test.dart`
- `docs/ota-release-playbook.md`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `env HOME=/tmp dart analyze lib/core/config/app_config_entry.dart lib/core/runtime/app_runtime_snapshot.dart lib/core/runtime/app_runtime_service.dart lib/services/remote_config_service.dart lib/core/bootstrap/app_environment.dart lib/core/bootstrap/app_bootstrap_coordinator.dart lib/services/startup_service.dart lib/core/remote_ui/remote_screen_body.dart lib/domains/remote_ui/presentation/remote_screen_providers.dart lib/domains/remote_ui/models/remote_screen_request.dart lib/integrations/supabase/remote_ui/supabase_remote_screen_repository.dart lib/widgets/app_runtime_diagnostic_banner.dart lib/features/shared/help_screen.dart lib/features/home/home_explore_screen.dart test/services/remote_config_service_test.dart test/domains/remote_ui/remote_screen_request_test.dart test/integrations/supabase/remote_ui/supabase_remote_screen_repository_test.dart`
- Resultado:
  - `No issues found!`
- Tentado:
  - `env HOME=/tmp flutter test test/services/remote_config_service_test.dart test/domains/remote_ui/remote_screen_request_test.dart test/integrations/supabase/remote_ui/supabase_remote_screen_repository_test.dart`
- Resultado:
  - execucao bloqueada pelo ambiente local com erro `snap-confine has elevated permissions and is not confined`
  - nao houve indicio de falha de codigo Dart nessa etapa; o bloqueio foi de runtime da ferramenta


## 2026-04-29 - Engine Server-Driven UI com kernel nativo para Help e Explore

### Alterações Realizadas

- Implementada a fundacao da engine de UI remota no app em uma estrutura modular nova, separando:
  - contratos de tela remota
  - caso de uso de carregamento
  - caso de uso de execucao de acao
  - registries nativos de componentes, acoes, links e rotas
  - renderer recursivo tipado
  - repositório Supabase com cache local
- Criado o novo dominio `remote_ui` com:
  - `RemoteScreen`
  - `RemoteComponent`
  - `RemoteAction`
  - `RemoteFeatureSet`
  - `RemoteFallbackPolicy`
  - `RemoteScreenRequest`
  - `LoadedRemoteScreen`
- Criados os contratos e casos de uso:
  - `lib/domains/remote_ui/data/remote_screen_repository.dart`
  - `lib/domains/remote_ui/domain/load_remote_screen_usecase.dart`
  - `lib/domains/remote_ui/domain/execute_remote_action_usecase.dart`
  - `lib/domains/remote_ui/domain/remote_action_executor.dart`
- Criada a camada nativa de governanca da engine em `lib/core/remote_ui/`:
  - `ComponentRegistry`
  - `ActionRegistry`
  - `RouteKeyRegistry`
  - `LinkKeyRegistry`
  - `NavigationActionResolver`
  - `IconKeyResolver`
  - `RemoteComponentRenderer`
  - `RemoteScreenBody`
- Implementado o repositório concreto `SupabaseRemoteScreenRepository` usando:
  - `Supabase Functions.invoke('get_screen')`
  - cache local via `SharedPreferences`
  - fallback para cache quando a chamada remota falha
  - validacao local de tipos de componente e acoes permitidas
- Implementado o executor padrao `DefaultRemoteActionExecutor` com whitelist local para:
  - `navigate_internal`
  - `open_external_url`
  - `show_snackbar`
  - `open_chat`
  - `open_help`
  - `open_profile`
  - `trigger_native_flow`
  - `refresh_screen`
- Integradas as telas:
  - `lib/features/shared/help_screen.dart`
  - `lib/features/home/home_explore_screen.dart`
- As duas telas agora tentam renderizar o payload remoto primeiro e mantem fallback nativo local quando:
  - a Edge Function falha
  - o cache nao existe
  - o payload e invalido
  - a screen vier desabilitada
- Criada a Edge Function `../supabase/functions/get_screen/index.ts` com contrato JSON versionado para:
  - `help`
  - `home_explore`
- O backend foi implementado com:
  - `screen_key`
  - `feature_set`
  - `revision`
  - `ttl_seconds`
  - `features`
  - `layout`
  - `fallback_policy`
  - `components`
- A implementacao segue a diretriz de compliance definida no plano:
  - sem rotas livres
  - sem endpoints livres
  - sem execucao arbitraria vinda do backend
  - apenas componentes e acoes embarcados no binario
- Adicionados testes iniciais cobrindo:
  - parse do contrato remoto
  - validacao do registry de componentes
  - leitura de cache local do repositorio remoto

### Arquivos Impactados

- `lib/domains/remote_ui/models/remote_action.dart`
- `lib/domains/remote_ui/models/remote_component.dart`
- `lib/domains/remote_ui/models/remote_feature_set.dart`
- `lib/domains/remote_ui/models/remote_fallback_policy.dart`
- `lib/domains/remote_ui/models/remote_screen.dart`
- `lib/domains/remote_ui/models/remote_screen_request.dart`
- `lib/domains/remote_ui/models/loaded_remote_screen.dart`
- `lib/domains/remote_ui/data/remote_screen_repository.dart`
- `lib/domains/remote_ui/domain/load_remote_screen_usecase.dart`
- `lib/domains/remote_ui/domain/execute_remote_action_usecase.dart`
- `lib/domains/remote_ui/domain/remote_action_executor.dart`
- `lib/domains/remote_ui/presentation/remote_screen_providers.dart`
- `lib/core/remote_ui/route_key_registry.dart`
- `lib/core/remote_ui/link_key_registry.dart`
- `lib/core/remote_ui/action_registry.dart`
- `lib/core/remote_ui/component_registry.dart`
- `lib/core/remote_ui/icon_key_resolver.dart`
- `lib/core/remote_ui/navigation_action_resolver.dart`
- `lib/core/remote_ui/remote_component_renderer.dart`
- `lib/core/remote_ui/remote_screen_body.dart`
- `lib/integrations/supabase/remote_ui/supabase_remote_screen_repository.dart`
- `lib/integrations/remote_ui/default_remote_action_executor.dart`
- `lib/features/shared/help_screen.dart`
- `lib/features/home/home_explore_screen.dart`
- `test/domains/remote_ui/remote_screen_model_test.dart`
- `test/core/remote_ui/component_registry_test.dart`
- `test/integrations/supabase/remote_ui/supabase_remote_screen_repository_test.dart`
- `../supabase/functions/get_screen/index.ts`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `env HOME=/tmp dart analyze lib/core/remote_ui lib/domains/remote_ui lib/integrations/remote_ui lib/integrations/supabase/remote_ui lib/features/shared/help_screen.dart lib/features/home/home_explore_screen.dart`
- Resultado:
  - `No issues found!`
- Executado:
  - `env HOME=/tmp dart analyze lib/core/remote_ui lib/domains/remote_ui lib/integrations/remote_ui lib/integrations/supabase/remote_ui lib/features/shared/help_screen.dart lib/features/home/home_explore_screen.dart test/domains/remote_ui test/core/remote_ui test/integrations/supabase/remote_ui`
- Resultado:
  - `No issues found!`
- Tentado:
  - `env HOME=/tmp flutter test test/domains/remote_ui/remote_screen_model_test.dart test/core/remote_ui/component_registry_test.dart test/integrations/supabase/remote_ui/supabase_remote_screen_repository_test.dart`
- Resultado:
  - o ambiente falhou antes da execucao dos testes com erro do runtime Snap/AppArmor:
  - `snap-confine has elevated permissions and is not confined but should be`
- Observacao:
  - o app side e o contrato remoto ficaram implementados e validados por analise estatica
  - a publicacao/deploy da Edge Function ainda depende do fluxo normal de deploy do Supabase neste repositório
  - a fase de expansao para `Home` principal, tracking, pagamentos e demais areas sensiveis nao foi executada nesta entrega
  - esta entrega cobre a fundacao da engine e a producao inicial em `Help + Explore`

## 2026-04-29 - Fundacao modular inicial para auth, service, payment e storage

### Alterações Realizadas

- Criada uma fundacao modular nova alinhada a direcao oficial `features -> domains -> integrations`, sem acoplar regras novas aos arquivos legados gigantes.
- Adicionado o ponto unico de acesso ao cliente Supabase em `lib/core/supabase/supabase_client.dart`.
- Adicionado o estado compartilhado de acoes assicronas em `lib/core/presentation/async_action_state.dart` para controllers Riverpod.
- Criados contratos e casos de uso para autenticacao:
  - `lib/domains/auth/data/auth_repository.dart`
  - `lib/domains/auth/domain/login_usecase.dart`
  - `lib/domains/auth/presentation/auth_controller.dart`
- Criados contratos, estado e caso de uso para servicos:
  - `lib/domains/service/data/service_repository.dart`
  - `lib/domains/service/models/service_state.dart`
  - `lib/domains/service/domain/change_service_status_usecase.dart`
  - `lib/domains/service/presentation/service_controller.dart`
- Criados contratos e caso de uso para pagamentos:
  - `lib/domains/payment/data/payment_repository.dart`
  - `lib/domains/payment/domain/process_payment_usecase.dart`
  - `lib/domains/payment/presentation/payment_controller.dart`
- Criados contrato e enum de storage:
  - `lib/domains/storage/storage_repository.dart`
  - `lib/domains/storage/storage_bucket.dart`
- Criadas implementacoes concretas de Supabase em `lib/integrations/supabase/` para:
  - auth
  - service
  - payment
  - storage
- Ajustados os controllers para o padrao compativel com `flutter_riverpod 3`, usando `NotifierProvider` em vez de `StateNotifierProvider`.
- A fundacao nova ja nasce com separacao entre:
  - contrato de dominio
  - caso de uso
  - implementacao concreta do Supabase
  - controller de apresentacao
- Integrado o fluxo de login por email/senha da tela `lib/features/auth/login_screen.dart` a essa nova fundacao:
  - a tela foi migrada para `ConsumerStatefulWidget`
  - o submit de login agora usa `authControllerProvider.notifier`
  - a autenticacao direta com `Supabase.instance.client.auth.signInWithPassword(...)` saiu da UI
  - a orquestracao pos-login existente foi preservada de forma incremental:
    - `syncUserProfile(...)`
    - `getMyProfile()`
    - redirecionamento por role
- O loading do botao de login agora considera o estado do controller Riverpod, enquanto o loading local continua atendendo o fluxo de Google login.

### Arquivos Impactados

- `lib/core/supabase/supabase_client.dart`
- `lib/core/presentation/async_action_state.dart`
- `lib/domains/auth/data/auth_repository.dart`
- `lib/domains/auth/domain/login_usecase.dart`
- `lib/domains/auth/presentation/auth_controller.dart`
- `lib/domains/service/data/service_repository.dart`
- `lib/domains/service/models/service_state.dart`
- `lib/domains/service/domain/change_service_status_usecase.dart`
- `lib/domains/service/presentation/service_controller.dart`
- `lib/domains/payment/data/payment_repository.dart`
- `lib/domains/payment/domain/process_payment_usecase.dart`
- `lib/domains/payment/presentation/payment_controller.dart`
- `lib/domains/storage/storage_bucket.dart`
- `lib/domains/storage/storage_repository.dart`
- `lib/integrations/supabase/auth/supabase_auth_repository.dart`
- `lib/integrations/supabase/service/supabase_service_repository.dart`
- `lib/integrations/supabase/payment/supabase_payment_repository.dart`
- `lib/integrations/supabase/storage/supabase_storage_repository.dart`
- `lib/features/auth/login_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `env HOME=/tmp dart analyze lib/core/presentation/async_action_state.dart lib/core/supabase/supabase_client.dart lib/domains/auth lib/domains/service lib/domains/payment lib/domains/storage lib/integrations/supabase`
- Executado:
  - `env HOME=/tmp dart analyze lib/features/auth/login_screen.dart lib/domains/auth lib/integrations/supabase/auth lib/core/presentation/async_action_state.dart lib/core/supabase/supabase_client.dart`
- Resultado:
  - `No issues found!`
- Nao foram integradas telas existentes a essa fundacao ainda; esta entrega estabelece a base arquitetural pronta para acoplamento incremental das features reais.

## 2026-04-28 - Reorientacao do plano para projeto novo do zero

### Alterações Realizadas

- Atualizado `docs/master-implementation-plan.md` para refletir a diretriz obrigatoria de que o novo Projeto 101 Modular deve ser construido do zero.
- O plano deixou de tratar o repositorio atual como base de migracao tecnica.
- O legado passou a ser tratado apenas como:
  - inspiracao funcional
  - fonte de requisitos
  - catalogo de fluxos reais
  - referencia de homologacao
- O documento foi reescrito para priorizar:
  - novo workspace
  - novo app Flutter
  - novo backend Supabase
  - contratos canonicos novos
  - validacao funcional contra o produto antigo sem adaptacao estrutural
- O plano foi refinado adicionalmente para ficar mais profissional, seguro e escalavel:
  - regra de camadas `features -> domains -> integrations`
  - backend explicitado como autoridade total das decisoes criticas
  - nova `Fase S` dedicada a seguranca e threat model
  - criacao do dominio `orders` separado de `dispatch`
  - expansao do schema canonico com trilhas de eventos, auditoria, documentos e verificacoes
  - endurecimento do DoD com `dart analyze`, `flutter test`, `supabase db reset`, testes RLS, testes de Edge Functions e contratos JSON
  - reforco de observabilidade com ids canonicos de correlacao e regras de log para Edge Functions
  - elevacao do plano para plataforma multiapp com `apps/` e `packages/`
  - adicao de camada de contratos/BFF em `backend/contracts` e `contracts/v1`
  - inclusao de fase dedicada a decisao de arquitetura multiapp
  - inclusao de fase dedicada a contratos JSON versionados
  - inclusao de fase DevOps/CI-CD com pipeline minima obrigatoria
  - reforco de seguranca mobile e protecao contra Broken Object Level Authorization
  - exigencia de ADRs em `docs/adr/` para decisoes arquiteturais
  - formalizacao do backend como API JSON oficial com envelopes padronizados de request e response
  - reforco de que HTTPS/TLS + JWT + RLS + validacao + autorizacao forte sao o padrao base
  - inclusao de fase dedicada a contratos JSON seguros com `request_id`, erros padronizados e idempotencia

### Arquivos Impactados

- `docs/master-implementation-plan.md`
- `RELATORIO_DEV.md`

### Validação

- Validacao documental/manual:
  - revisao de coerencia entre a diretriz do usuario e o plano mestre
  - confirmacao de que o legado ficou posicionado apenas como referencia funcional
- Nao houve execucao de testes automatizados por se tratar de ajuste de documentacao e direcao arquitetural.

## 2026-04-28 - Plano mestre de modularizacao incremental alinhado ao estado real do repositorio

### Alterações Realizadas

- Criado `docs/master-implementation-plan.md` com um plano de execucao tecnica detalhado para a modularizacao do Projeto 101.
- O novo plano corrige a premissa anterior de "projeto do zero" e passa a tratar o repositorio como migracao incremental, que e o estado tecnico real atual.
- O documento foi alinhado aos artefatos ja existentes no repositorio:
  - `docs/domain-architecture.md`
  - `docs/dispatch-flow.md`
  - `docs/tracking-domain.md`
  - `docs/payments-domain.md`
  - `docs/notifications-domain.md`
  - `docs/presence-profile-domain.md`
- O plano novo inclui:
  - estrutura alvo por ownership (`core`, `domains`, `integrations`, `features`, `services`)
  - fases de backend local, schema, edge functions, auth, presence, dispatch, tracking, payments e notifications
  - criterios de aceite por fase
  - backlog priorizado
  - definition of done
  - anti-padroes proibidos
  - prompt operacional pronto para reutilizar no Codex

### Arquivos Impactados

- `docs/master-implementation-plan.md`
- `RELATORIO_DEV.md`

### Validação

- Validacao documental/manual:
  - leitura do `RELATORIO_DEV.md` antes da edicao
  - leitura da documentacao existente de arquitetura e dominios para garantir consistencia
- Nao houve execucao de build, analyze ou testes automatizados porque esta entrega foi exclusivamente de documentacao e planejamento tecnico.

## 2026-04-18

- Revisada e endurecida a migration de disputa em [20260418043000_service_dispute_resolution_workflow.sql](/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260418043000_service_dispute_resolution_workflow.sql:6).
- Adicionado bloqueio de redecisao: a disputa agora so pode sair de `open` uma vez.
- Corrigido o caminho `dismissed` para validar o retorno da RPC `rpc_auto_confirm_service_after_grace(...)` e falhar se a confirmacao nao for aplicada.
- Corrigido o caminho `resolved` para impedir reembolso se ja existir credito `credit` do prestador para o mesmo servico.
- Ajustado o fechamento do servico reembolsado para alinhar `status = refunded`, `finished_at` e `provider_amount = 0`.
- Corrigido o calculo de reembolso para fazer cast explicito de `price_estimated` para `numeric` antes do `ROUND(..., 2)`, evitando erro com `double precision`.
- Criado script de teste ponta a ponta em [e2e_service_dispute_resolution.sql](/home/servirce/Documentos/101/projeto-central-/supabase/scripts/e2e_service_dispute_resolution.sql:1) cobrindo:
  - `open -> dismissed`
  - `open -> resolved`
  - tentativa de redecisao tardia
- Criada migration corretiva [20260418103000_add_completed_at_to_service_requests_new.sql](/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260418103000_add_completed_at_to_service_requests_new.sql:1) para alinhar o schema remoto com as RPCs/triggers que usam `completed_at`.
- Criada migration corretiva [20260418104500_fix_dispute_refund_round_numeric.sql](/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260418104500_fix_dispute_refund_round_numeric.sql:1) para recriar a função `handle_service_dispute_resolution()` com cast explicito para `numeric` no calculo do reembolso.
- Extraida a logica de reclamacao do app para [service_complaint_logic.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/service_complaint_logic.dart:1), cobrindo:
  - resolucao do `claimType`
  - classificacao do tipo de anexo
  - montagem do texto final enviado na reclamacao
- Atualizada a tela [refund_request_screen.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/refund_request_screen.dart:1) para reutilizar essa logica extraida.
- Criados testes unitarios em [service_complaint_logic_test.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/test/features/client/service_complaint_logic_test.dart:1).
- Ajustado o fluxo de UX em [service_tracking_page.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/service_tracking_page.dart:1): o botao `ABRIR RECLAMAÇÃO` agora abre o formulario em um painel modal dentro da propria pagina, evitando falha/intermitencia de navegação web.
- Refatorada [refund_request_screen.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/refund_request_screen.dart:1) para expor `RefundRequestForm`, permitindo uso tanto como tela completa quanto como card/modal embutido.

## Como validar

- Rodar o script SQL:
  - `supabase db query < supabase/scripts/e2e_service_dispute_resolution.sql`
- Conferir os `NOTICE`s com os `service_id`s gerados.
- Executar as queries comentadas no final do script para validar:
  - credito ao prestador no caso `dismissed`
  - reembolso ao cliente no caso `resolved`
  - falha ao tentar trocar o status depois que a disputa sai de `open`

## 2026-04-18 - Bloqueio de novos serviços durante contestação

### Alterações Realizadas

- Ajustada a lógica de disputa no app para que abrir reclamação/contestação também force o serviço para `status = contested` em [api_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/api_service.dart:5268).
- Adicionados os métodos `getOpenDisputeForService(...)` e `getBlockingDisputeForCurrentClient()` em [api_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/api_service.dart:5337), permitindo:
  - consultar a disputa aberta de um serviço específico;
  - bloquear nova contratação do cliente enquanto houver disputa `open`.
- Incluído o status `contested` como serviço ativo em [central_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/central_service.dart:1769), mantendo o cliente preso ao fluxo de acompanhamento enquanto a análise estiver pendente.
- Atualizada a Home em [home_screen.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/home/home_screen.dart:825) para:
  - impedir criação de novo serviço quando existir contestação aberta;
  - exibir aviso contextual com ação `Ver detalhes`;
  - tratar `contested` como estado que redireciona para `service-tracking`;
  - mostrar banner `Serviço sob contestação`.
- Finalizada a UX da tela [service_tracking_page.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/service_tracking_page.dart:1) para:
  - carregar a disputa aberta do serviço junto do refresh/polling;
  - trocar o bloco `CONFIRMAR SERVIÇO` / `ABRIR RECLAMAÇÃO` por um card de análise;
  - informar que o usuário não pode contratar outro serviço enquanto a análise não for resolvida;
  - oferecer `CONSULTAR DETALHES` em modal interno;
  - exibir ação `ACEITAR PROPOSTA DA PLATAFORMA` com fallback seguro enquanto ainda não existe backend real para proposta.

### Arquivos Impactados

- [mobile_app/lib/services/api_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/api_service.dart:5268)
- [mobile_app/lib/services/central_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/central_service.dart:1769)
- [mobile_app/lib/features/home/home_screen.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/home/home_screen.dart:825)
- [mobile_app/lib/features/client/service_tracking_page.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/service_tracking_page.dart:1)

### Validação

- `dart format -o none --set-exit-if-changed mobile_app/lib/features/client/service_tracking_page.dart`
  - resultado: formatou o arquivo com sucesso.
- `flutter analyze --no-pub lib/features/client/service_tracking_page.dart`
  - resultado: o comando iniciou, mas não retornou diagnóstico dentro da janela observada deste ambiente.

## 2026-04-18 - Campo de decisão administrativa da contestação

### Alterações Realizadas

- Criada a migration [20260418112000_add_platform_decision_to_service_disputes.sql](/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260418112000_add_platform_decision_to_service_disputes.sql:1) para adicionar o campo `platform_decision` em `public.service_disputes`.
- O novo campo foi definido com:
  - default `pending`
  - `NOT NULL`
  - constraint para aceitar apenas `pending`, `accepted` ou `rejected`
- Incluído backfill para alinhar registros antigos com o fluxo já existente:
  - `status = resolved` -> `platform_decision = accepted`
  - `status = dismissed` -> `platform_decision = rejected`
  - demais casos -> `platform_decision = pending`

### Arquivos Impactados

- [supabase/migrations/20260418112000_add_platform_decision_to_service_disputes.sql](/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260418112000_add_platform_decision_to_service_disputes.sql:1)

### Validação

- Validação estrutural feita por revisão da migration e compatibilidade com os status atuais `open`, `dismissed` e `resolved`.
- Ainda falta aplicar no remoto com `supabase db push` para o campo existir de fato no banco remoto.

## 2026-04-18 - Sincronização entre platform_decision e status da disputa

### Alterações Realizadas

- Criada a migration [20260418113000_sync_service_dispute_platform_decision_and_status.sql](/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260418113000_sync_service_dispute_platform_decision_and_status.sql:1) para tornar `platform_decision` a interface administrativa do fluxo.
- Implementado trigger `BEFORE UPDATE` em `service_disputes` com as regras:
  - `platform_decision = accepted` -> `status = resolved`
  - `platform_decision = rejected` -> `status = dismissed`
  - `platform_decision = pending` -> `status = open`
- Mantida compatibilidade com o fluxo legado:
  - se algum processo ainda atualizar `status` diretamente, o trigger preenche `platform_decision` automaticamente.
- Adicionadas validações para impedir combinações incoerentes entre `status` e `platform_decision` no mesmo `UPDATE`.
- Atualizado o script [e2e_service_dispute_resolution.sql](/home/servirce/Documentos/101/projeto-central-/supabase/scripts/e2e_service_dispute_resolution.sql:1) para testar a decisão administrativa pelo novo campo:
  - `platform_decision = rejected`
  - `platform_decision = accepted`

### Arquivos Impactados

- [supabase/migrations/20260418113000_sync_service_dispute_platform_decision_and_status.sql](/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260418113000_sync_service_dispute_platform_decision_and_status.sql:1)
- [supabase/scripts/e2e_service_dispute_resolution.sql](/home/servirce/Documentos/101/projeto-central-/supabase/scripts/e2e_service_dispute_resolution.sql:1)

### Validação

- Revisão lógica da automação para garantir que o trigger `BEFORE UPDATE` alimente o trigger já existente `AFTER UPDATE OF status`.
- Para validar no remoto:
  - `supabase db push`
  - `supabase db query < supabase/scripts/e2e_service_dispute_resolution.sql`

## 2026-04-18 - Contestação principal separada de anexos na mesma tabela

### Alterações Realizadas

- Criada a migration [20260418114500_restrict_dispute_resolution_to_primary_complaint.sql](/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260418114500_restrict_dispute_resolution_to_primary_complaint.sql:1) para restringir a automação da disputa apenas à linha principal `type = 'complaint'`.
- O trigger de sincronização entre `platform_decision` e `status` agora ignora registros de evidência (`photo`, `video`, `audio`) e preserva esses anexos fora do fluxo administrativo.
- O trigger de resolução financeira também passou a ignorar evidências e processar apenas a contestação principal, evitando que múltiplas linhas do mesmo `service_id` sejam tratadas como casos independentes.
- Atualizado [api_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/api_service.dart:5341) para que:
  - `getOpenDisputeForService(...)` consulte apenas `type = 'complaint'`
  - `getBlockingDisputeForCurrentClient()` consulte apenas `type = 'complaint'`

### Arquivos Impactados

- [supabase/migrations/20260418114500_restrict_dispute_resolution_to_primary_complaint.sql](/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260418114500_restrict_dispute_resolution_to_primary_complaint.sql:1)
- [mobile_app/lib/services/api_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/api_service.dart:5341)

### Validação

- Revisão estrutural do fluxo com base no cenário real em que um único `service_id` possui várias linhas em `service_disputes`.
- O comportamento esperado após `supabase db push` é:
  - 1 linha `complaint` controla decisão/status
  - linhas `photo`, `video` e `audio` permanecem apenas como evidência

## 2026-04-18 - Visão administrativa consolidada das contestações

### Alterações Realizadas

- Criada a migration [20260418115500_create_service_disputes_admin_view.sql](/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260418115500_create_service_disputes_admin_view.sql:1) para expor a view `public.service_disputes_admin_vw`.
- A view consolida:
  - 1 linha por contestação principal (`type = 'complaint'`)
  - dados do serviço
  - dados do cliente
  - dados do prestador
  - `status`
  - `platform_decision`
  - lista de evidências agrupadas em `jsonb`
  - contagem de anexos em `evidence_count`
- Criado o script [query_service_disputes_admin_view.sql](/home/servirce/Documentos/101/projeto-central-/supabase/scripts/query_service_disputes_admin_view.sql:1) com consultas prontas para:
  - listar contestações recentes
  - buscar por `service_id`
  - filtrar apenas pendentes de decisão

### Arquivos Impactados

- [supabase/migrations/20260418115500_create_service_disputes_admin_view.sql](/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260418115500_create_service_disputes_admin_view.sql:1)
- [supabase/scripts/query_service_disputes_admin_view.sql](/home/servirce/Documentos/101/projeto-central-/supabase/scripts/query_service_disputes_admin_view.sql:1)

### Validação

- Revisão estrutural da view para garantir:
  - somente `complaint` como linha principal
  - anexos agrupados via `jsonb_agg`
  - compatibilidade com a tabela atual `service_disputes`
- Para validar no remoto:
  - `supabase db push`
  - rodar `supabase/scripts/query_service_disputes_admin_view.sql` no SQL Editor ou via CLI

## 2026-04-18 - Feedback visual da decisão da plataforma na service-tracking

### Alterações Realizadas

- Atualizada [service_tracking_page.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/service_tracking_page.dart:1) para consultar também a última contestação principal do serviço, e não apenas a disputa `open`.
- Adicionado em [api_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/api_service.dart:5352) o método `getLatestPrimaryDisputeForService(...)`.
- O card da contestação agora diferencia os estados:
  - em análise
  - rejeitada pela plataforma
  - aceita pela plataforma
- Quando a reclamação é rejeitada, a tela passa a exibir mensagem explícita:
  - `Sua reclamação foi rejeitada pela plataforma`
- O botão secundário passa a atuar como encerramento de UX do caso:
  - `ACEITAR DECISÃO DA PLATAFORMA`
  - ao tocar, o app mostra confirmação e retorna para a Home

### Arquivos Impactados

- [mobile_app/lib/services/api_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/api_service.dart:5352)
- [mobile_app/lib/features/client/service_tracking_page.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/service_tracking_page.dart:1)

### Validação

- Revisão do fluxo visual considerando o cenário mostrado no banco:
  - disputa principal `complaint` com `status = dismissed`
  - `platform_decision = rejected`
- Com essa mudança, a tela deixa de depender apenas da disputa `open` para mostrar o desfecho ao cliente.

## 2026-04-18 - Aceite do cliente encerra a decisão da plataforma

### Alterações Realizadas

- Criada a migration [20260418120500_add_client_acknowledged_at_to_service_disputes.sql](/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260418120500_add_client_acknowledged_at_to_service_disputes.sql:1) para persistir quando o cliente aceita a decisão final da plataforma.
- Adicionado em [api_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/api_service.dart:5366) o método `acceptPlatformDisputeDecision(serviceId)`.
- Esse método agora:
  - grava `client_acknowledged_at` na contestação principal;
  - se a reclamação foi rejeitada e o serviço ainda está `contested`, converte o serviço para `completed` para que ele deixe de ser tratado como ativo.
- Atualizada [service_tracking_page.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/service_tracking_page.dart:1) para:
  - não exibir novamente o card de decisão quando `client_acknowledged_at` já estiver preenchido;
  - usar o método novo ao tocar em `ACEITAR DECISÃO DA PLATAFORMA`;
  - redirecionar para a Home somente após persistir o encerramento.

### Arquivos Impactados

- [supabase/migrations/20260418120500_add_client_acknowledged_at_to_service_disputes.sql](/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260418120500_add_client_acknowledged_at_to_service_disputes.sql:1)
- [mobile_app/lib/services/api_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/api_service.dart:5366)
- [mobile_app/lib/features/client/service_tracking_page.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/service_tracking_page.dart:1)

### Validação

- Revisão do fluxo para evitar retorno automático ao tracking após o cliente aceitar a decisão da plataforma.
- Para validar no remoto:
  - `supabase db push`
  - rejeitar uma contestação principal
  - tocar em `ACEITAR DECISÃO DA PLATAFORMA`
  - confirmar que o serviço deixa de reaparecer como ativo

## 2026-04-18 - Fluxo de agendamento para salões de beleza

### Alterações Realizadas

- Atualizada a tela [hme_prestador_movel.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/hme_prestador_movel.dart:1), que alimenta a rota `/beauty-booking`, para o novo fluxo de salão:
  - o serviço inicial agora chega pré-preenchido via `extra`;
  - a busca considera apenas prestadores `at_provider`;
  - os salões são ranqueados por distância e próximo horário disponível;
  - a lista principal já exclui salões sem slot livre no horizonte de busca;
  - o resumo financeiro foi trocado de `30%/70%` para `10%` de taxa no app e `90%` pagos no local;
  - o payload do pagamento agora usa `entityType = service_fixed` e `isFixed = true`.
- Ajustada [provider_profile_screen.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/profile/provider_profile_screen.dart:1021) para que o botão `Agendar` não abra mais modal de slot; agora ele navega direto para `/beauty-booking` com o serviço e o salão já selecionados.
- Atualizada [payment_screen.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/payment_screen.dart:1) para que, ao confirmar o PIX de entrada de um serviço fixo, o cliente volte para a Home em vez de cair no `service-tracking` móvel.
- Atualizada a Home em [home_screen.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/home/home_screen.dart:1206) para o card de próximo agendamento:
  - agora carrega `service_request_id`, nome do serviço e coordenadas do salão;
  - usa o `service_request_id` como destino da rota `/scheduled-service/:serviceId`;
  - estima distância e tempo de deslocamento;
  - calcula “hora de sair” com `tempo de deslocamento + 15 min`.
- Atualizada [notification_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/notification_service.dart:2563) para alinhar a mensagem de saída com a nova regra de `15 min de antecedência`.
- Atualizada [scheduled_service_screen.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/scheduled_service_screen.dart:1) para o pós-reserva do salão:
  - botão `Ir com GPS`;
  - `Cheguei no local` liberado apenas por proximidade;
  - aviso visual quando o cliente ainda está longe;
  - remoção do pagamento final no app, com orientação explícita de que os `90%` restantes são pagos diretamente no salão;
  - ajuste do bloco “hora de sair” para usar `deslocamento + 15 min`.

### Arquivos Impactados

- [mobile_app/lib/features/client/hme_prestador_movel.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/hme_prestador_movel.dart:1)
- [mobile_app/lib/features/profile/provider_profile_screen.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/profile/provider_profile_screen.dart:1)
- [mobile_app/lib/features/client/payment_screen.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/payment_screen.dart:1)
- [mobile_app/lib/features/home/home_screen.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/home/home_screen.dart:1)
- [mobile_app/lib/features/client/scheduled_service_screen.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/scheduled_service_screen.dart:1)
- [mobile_app/lib/services/notification_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/notification_service.dart:2563)

### Validação

- `dart format mobile_app/lib/features/client/hme_prestador_movel.dart mobile_app/lib/features/home/home_screen.dart mobile_app/lib/features/client/payment_screen.dart mobile_app/lib/features/client/scheduled_service_screen.dart mobile_app/lib/features/profile/provider_profile_screen.dart mobile_app/lib/services/notification_service.dart`
  - resultado: arquivos formatados com sucesso.
- `flutter analyze --no-pub lib/features/client/hme_prestador_movel.dart lib/features/home/home_screen.dart lib/features/client/payment_screen.dart lib/features/client/scheduled_service_screen.dart lib/features/profile/provider_profile_screen.dart lib/services/notification_service.dart`
  - resultado: sem erros de compilação; retornou apenas warnings/info de código não utilizado em áreas legadas e auxiliares já existentes.

## 2026-04-18 - Compatibilidade temporária do aceite da decisão da plataforma

### Alterações Realizadas

- Ajustado [api_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/api_service.dart:5370) no método `acceptPlatformDisputeDecision(serviceId)` para não quebrar quando o banco remoto ainda não tiver a coluna `client_acknowledged_at`.
- O método agora:
  - tenta persistir `client_acknowledged_at` quando a migration já existe;
  - detecta especificamente o erro `PGRST204` de coluna ausente;
  - segue com fallback compatível, sem interromper o encerramento do caso no app.

### Arquivos Impactados

- [mobile_app/lib/services/api_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/api_service.dart:5370)

### Validação

- `dart format mobile_app/lib/services/api_service.dart`
  - resultado: formatado com sucesso.
- `flutter analyze --no-pub lib/services/api_service.dart lib/features/client/service_tracking_page.dart`
  - resultado: sem erro de compilação; apenas 1 warning pré-existente em `service_tracking_page.dart` sobre variável local não usada.

## 2026-04-18 - Restauração da âncora do prestador fixo

### Alterações Realizadas

- Ajustada a rota `/servicos` em [main.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/main.dart:825) para voltar a encaminhar corretamente para `/beauty-booking` quando o fluxo móvel identificar um serviço `at_provider`.
- Restaurada a função da tela fixa em [hme_prestador_movel.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/hme_prestador_movel.dart:1):
  - deixou de agir como landing/hero confusa;
  - voltou a abrir como página-âncora de busca;
  - input de serviço permanece no topo;
  - ao digitar/classificar, a tela busca prestadores fixos próximos;
  - a lista considera apenas salões com agenda livre;
  - a ordenação continua por distância e próximo horário disponível;
  - tocar no salão já leva para a etapa de agenda com o primeiro horário encontrado pré-selecionado.
- Corrigido o estado inicial da tela fixa para que, ao receber `initialData` sem salão pré-selecionado, ela abra na própria listagem âncora em vez de pular para um passo intermediário incorreto.

### Arquivos Impactados

- [mobile_app/lib/main.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/main.dart:825)
- [mobile_app/lib/features/client/hme_prestador_movel.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/hme_prestador_movel.dart:1)

### Validação

- `dart format mobile_app/lib/main.dart mobile_app/lib/features/client/hme_prestador_movel.dart`
  - resultado: formatado com sucesso.
- `flutter analyze --no-pub lib/main.dart lib/features/client/hme_prestador_movel.dart lib/features/client/home_prestador_fixo.dart`
  - resultado: sem erros de compilação; apenas warnings antigos de código não utilizado em arquivos legados.

## 2026-04-26 - Ajuste visual do campo de busca da home

### Alterações Realizadas

- Atualizado [mobile_app/lib/features/home/widgets/home_search_bar.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/home/widgets/home_search_bar.dart:1) para deixar o input de busca com aparência mais próxima do layout solicitado:
  - fundo cinza claro;
  - campo mais alto e com mais área interna;
  - cantos mais arredondados;
  - borda azul ao receber foco/clique;
  - borda neutra clara quando não está em foco.
- Removidas explicitamente as bordas internas do `TextField` em todos os estados (`enabled`, `focused`, `disabled`, `error`) para eliminar a linha destacada dentro do input.
- Adicionado `FocusNode` ao `TextField` para reagir visualmente ao foco sem alterar o comportamento da busca e das sugestões.
- Mantido o fluxo já existente de autocomplete, loading e seleção de sugestões.
- Limitada a altura máxima da lista de sugestões e habilitada rolagem interna para evitar `RenderFlex overflow` quando o teclado estiver aberto na tela `Buscar serviços`.

## 2026-04-26 - PIX do agendamento fixo exibido no mesmo card

### Alterações Realizadas

- Ajustado [mobile_app/lib/features/client/home_prestador_fixo.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/home_prestador_fixo.dart:1618) para que, após confirmar o horário, o fluxo não abra automaticamente a rota `/pix-payment`.
- O PIX pendente agora permanece exibido no mesmo card expandido do prestador/horário, usando o bloco inline já existente em [fixed_booking_expanded_schedule_card.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/widgets/fixed_booking_expanded_schedule_card.dart:1).
- Mantido o watcher do PIX pendente e armado o auto-scroll para trazer o card expandido de volta à área visível após gerar o QR.

### Arquivos Impactados

- [mobile_app/lib/features/client/home_prestador_fixo.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/client/home_prestador_fixo.dart:1618)

### Validação

- Validação lógica por revisão do fluxo:
  - confirmar horário;
  - manter `pendingPixState.visible = true`;
  - exibir QR/copia e cola no mesmo card expandido;
  - evitar navegação automática para tela dedicada de PIX.

## 2026-04-26 - Correção de overflow nos slots do painel do prestador fixo

### Alterações Realizadas

- Ajustado [mobile_app/lib/features/provider/provider_home_fixed.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/provider/provider_home_fixed.dart:2695) para evitar `BOTTOM OVERFLOWED` nos cards de horário do painel do prestador.
- A grade dos slots ficou um pouco mais alta com `childAspectRatio` reduzido, dando mais espaço vertical aos estados com mais texto.
- Compactado o conteúdo textual interno dos slots, principalmente no estado `waiting_payment`:
  - subtítulo do slot de PIX pendente agora ocupa apenas 1 linha;
  - fontes e espaçamentos internos foram reduzidos levemente;
  - padding vertical do tile foi equilibrado para caber sem cortar.

### Arquivos Impactados

- [mobile_app/lib/features/provider/provider_home_fixed.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/provider/provider_home_fixed.dart:2695)

### Validação

- `dart format mobile_app/lib/features/provider/provider_home_fixed.dart`
  - resultado: formatado com sucesso.

## 2026-04-26 - Amarelo global do app ajustado para tom mais vivo

### Alterações Realizadas

- Atualizado o amarelo principal do tema em [mobile_app/lib/core/theme/app_theme.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/core/theme/app_theme.dart:11) de `#FFD700` para `#FFC107`, deixando o amarelo do app mais vivo e menos apagado.
- Alinhado o fallback global do tema em [mobile_app/lib/services/theme_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/theme_service.dart:46) para usar o mesmo amarelo novo tanto no tema do cliente quanto no do prestador.
- Substituídos alguns fundos amarelados hardcoded mais lavados por um amarelo mais presente nas telas onde esse destaque aparecia sem vida:
  - [mobile_app/lib/features/home/home_search_screen.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/home/home_search_screen.dart:1051)
  - [mobile_app/lib/features/home/mobile_service_request_review_screen.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/home/mobile_service_request_review_screen.dart:339)
  - [mobile_app/lib/features/provider/provider_home_fixed.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/provider/provider_home_fixed.dart:999)

### Arquivos Impactados

- [mobile_app/lib/core/theme/app_theme.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/core/theme/app_theme.dart:11)
- [mobile_app/lib/services/theme_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/theme_service.dart:46)
- [mobile_app/lib/features/home/home_search_screen.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/home/home_search_screen.dart:1051)
- [mobile_app/lib/features/home/mobile_service_request_review_screen.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/home/mobile_service_request_review_screen.dart:339)
- [mobile_app/lib/features/provider/provider_home_fixed.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/provider/provider_home_fixed.dart:999)

### Validação

- `dart format mobile_app/lib/core/theme/app_theme.dart mobile_app/lib/services/theme_service.dart mobile_app/lib/features/home/home_search_screen.dart mobile_app/lib/features/home/mobile_service_request_review_screen.dart mobile_app/lib/features/provider/provider_home_fixed.dart`
  - resultado: formatado com sucesso.

## 2026-04-26 - Correção de cache do avatar do prestador e ajuste extra no slot Pix

### Alterações Realizadas

- Ajustado [mobile_app/lib/features/provider/provider_home_fixed.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/provider/provider_home_fixed.dart:586) para recarregar o avatar de forma mais confiável após upload:
  - `_loadAvatar()` agora também limpa o avatar local quando a releitura falha ou retorna vazio;
  - criado refresh pós-upload com pequena espera e nova leitura;
  - invalidado o cache de bytes antes de reler a imagem.
- Adicionado método de invalidação de cache de mídia em:
  - [mobile_app/lib/services/support/api_media_storage.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/support/api_media_storage.dart:176)
  - [mobile_app/lib/services/api_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/api_service.dart:8606)
- Ajustado novamente o texto do estado `waiting_payment` no painel do prestador em [mobile_app/lib/features/provider/provider_home_fixed.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/provider/provider_home_fixed.dart:995), removendo o subtítulo mais longo `• aguardando Pix` para reduzir o risco de novo overflow.

### Arquivos Impactados

- [mobile_app/lib/features/provider/provider_home_fixed.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/provider/provider_home_fixed.dart:586)
- [mobile_app/lib/services/support/api_media_storage.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/support/api_media_storage.dart:176)
- [mobile_app/lib/services/api_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/api_service.dart:8606)

### Validação

- `dart format mobile_app/lib/services/support/api_media_storage.dart mobile_app/lib/services/api_service.dart mobile_app/lib/features/provider/provider_home_fixed.dart`
  - resultado: formatado com sucesso.

## 2026-04-26 - Botão "Ir para o card" corrigido no banner de Pix pendente

### Alterações Realizadas

- Ajustado [mobile_app/lib/features/home/widgets/home_pending_fixed_payment_banner.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/home/widgets/home_pending_fixed_payment_banner.dart:1) para separar o comportamento dos dois botões do banner:
  - `Abrir pagamento` continua abrindo o fluxo do Pix;
  - `Ir para o card` agora rola até o `FixedServiceCard` logo abaixo.
- O widget foi convertido para `StatefulWidget` e passou a usar `Scrollable.ensureVisible(...)` com `GlobalKey` para focar o card correto dentro da mesma tela.

### Arquivos Impactados

- [mobile_app/lib/features/home/widgets/home_pending_fixed_payment_banner.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/home/widgets/home_pending_fixed_payment_banner.dart:1)

### Validação

- `dart format mobile_app/lib/features/home/widgets/home_pending_fixed_payment_banner.dart`
  - resultado: formatado com sucesso.

## 2026-04-26 - Conversão de PNG para JPG antes do upload do avatar

### Alterações Realizadas

- Atualizado [mobile_app/lib/services/media_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/media_service.dart:1) para converter imagens PNG em JPG antes do upload do avatar.
- A normalização agora acontece no próprio `uploadAvatarBytes(...)`, então o comportamento vale tanto para mobile quanto para web.
- Com isso:
  - o upload deixa de depender de compressão ignorada pelo `image_picker` em arquivos PNG;
  - o arquivo enviado tende a ficar mais leve;
  - o backend/storage passa a receber `image/jpeg` quando a origem for PNG.

### Arquivos Impactados

- [mobile_app/lib/services/media_service.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/services/media_service.dart:1)

### Validação

- `dart format mobile_app/lib/services/media_service.dart`
  - resultado: formatado com sucesso.
- Correção de compilação aplicada no mesmo arquivo:
  - adicionada a importação de `dart:typed_data` para suportar `Uint8List` na conversão PNG -> JPG.

### Arquivos Impactados

- [mobile_app/lib/features/home/widgets/home_search_bar.dart](/home/servirce/Documentos/101/projeto-central-/mobile_app/lib/features/home/widgets/home_search_bar.dart:1)

### Validação

- `dart format mobile_app/lib/features/home/widgets/home_search_bar.dart`
  - resultado: formatado com sucesso.

## 2026-05-01 - Extração do domínio Scheduling do ApiService

### Contexto

Início da refatoração arquitetural do `api_service.dart` (9.629 linhas, 12 domínios misturados).
Primeira extração: domínio `scheduling`, o maior bloco isolado do arquivo (~1.700 linhas).

### Alterações Realizadas

Criado o domínio `lib/domains/scheduling/` com estrutura completa:

- `models/schedule_config.dart` — configuração de agenda por dia da semana
- `models/schedule_config_result.dart` — resultado tipado com metadados de origem (provider_schedules vs legado)
- `models/schedule_slot.dart` — slot de agenda com status canônico (`free`, `booked`, `lunch`)
- `models/fixed_booking_intent.dart` — intenção de agendamento PIX com estado completo
- `data/scheduling_repository.dart` — contrato puro do repositório (sem dependência de Supabase)
- `domain/scheduling_usecases.dart` — 6 use cases com responsabilidade única:
  - `GetScheduleConfigUseCase`
  - `SaveScheduleConfigUseCase`
  - `GetProviderAvailableSlotsUseCase`
  - `GetProviderNextAvailableSlotUseCase`
  - `CreateFixedBookingIntentUseCase`
  - `CancelFixedBookingIntentUseCase`
  - `ConfirmScheduleUseCase`
- `scheduling.dart` — barrel export do domínio

Criada a implementação concreta em `lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`:
- Delega para `ApiService` durante a migração gradual
- Contrato do domínio já isolado e testável via mock
- Quando um método for extraído do ApiService, basta atualizar a implementação aqui

### Arquivos Impactados

- `lib/domains/scheduling/models/schedule_config.dart`
- `lib/domains/scheduling/models/schedule_config_result.dart`
- `lib/domains/scheduling/models/schedule_slot.dart`
- `lib/domains/scheduling/models/fixed_booking_intent.dart`
- `lib/domains/scheduling/data/scheduling_repository.dart`
- `lib/domains/scheduling/domain/scheduling_usecases.dart`
- `lib/domains/scheduling/scheduling.dart`
- `lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`

### Validação

- `dart analyze lib/domains/scheduling/ lib/integrations/supabase/scheduling/`
  - resultado: `No issues found!`

### Próximos passos do domínio scheduling

1. Migrar `features/provider/provider_home_fixed.dart` para consumir `SchedulingRepository` em vez de `ApiService` diretamente
2. Migrar `features/client/home_prestador_fixo.dart` para consumir `CreateFixedBookingIntentUseCase`
3. Extrair a lógica de `_generateSlotsForDate` do `ApiService` para dentro da implementação do repositório
4. Adicionar testes unitários com mock de `SchedulingRepository`

## 2026-05-01 - Migração completa do domínio Scheduling (passos 1-4)

### Passo 1 — `provider_home_fixed.dart` migrado para `SchedulingRepository`

- Adicionado `SchedulingRepository _scheduling` instanciado via `SupabaseSchedulingRepository`.
- Substituídas todas as chamadas de scheduling diretas ao `_api`:
  - `_api.getProviderSlots(...)` → `_scheduling.getProviderSlots(...)`
  - `_api.getScheduleConfigForProvider(...)` → `_scheduling.getScheduleConfig(...)`
  - `_api.getScheduleConfigResultForProvider(...)` → `_scheduling.getScheduleConfigResult(...)`
  - `_api.markSlotBusy(...)` → `_scheduling.markSlotBusy(...)`
  - `_api.deleteAppointment(...)` → `_scheduling.deleteAppointment(...)`
  - `_api.createManualAppointment(...)` → `_scheduling.createManualAppointment(...)`

### Passo 2 — `home_prestador_fixo.dart` migrado para use cases

- Adicionados use cases instanciados via `SupabaseSchedulingRepository`:
  - `GetProviderNextAvailableSlotUseCase _getNextSlot`
  - `GetProviderAvailableSlotsUseCase _getAvailableSlots`
  - `CreateFixedBookingIntentUseCase _createIntent`
  - `CancelFixedBookingIntentUseCase _cancelIntent`
- `_api.getProviderNextAvailableSlot(...)` → `_getNextSlot(...)`
- `_api.getProviderAvailableSlots(...)` → `_getAvailableSlots(...)`
- `_api.createPendingFixedBookingIntent(...)` → `_createIntent(...)` retornando `FixedBookingIntent` tipado
- `_api.cancelPendingFixedBookingIntent(...)` → `_cancelIntent(...)`
- `ApiService.fixedBookingLeadTime` substituído por `Duration.zero` (constante local)

### Passo 3 — `_generateSlotsForDate` extraído para `SlotGenerator`

- Criado `lib/domains/scheduling/domain/slot_generator.dart` com lógica pura:
  - `SlotGenerator.generateSlotsForDate(...)` — geração de slots sem I/O
  - `SlotGenerator.parseDateKey(...)` — parse de chave de data
  - `SlotGenerator.isScheduleEnabled(...)` — avaliação de config habilitada
  - `SlotGenerator.mapScheduleRowToConfig(...)` — normalização de linha do banco
  - `SlotGenerator.normalizeLegacyConfigs(...)` — normalização de configs legadas
  - `SlotGenerator.extractIntentSnapshotFromHold(...)` — extração de snapshot de intent
  - `SlotGenerator.isActiveSlotHold(...)` — verificação de hold ativo
  - `SchedulingConstants` — constantes de domínio (statuses, projections)
- `SupabaseSchedulingRepository.getProviderAvailableSlots(...)` agora usa `SlotGenerator` diretamente, sem delegar para `ApiService`
- Adicionados helpers internos `_runSlotHoldsQuery` e `_attachIntentSnapshot` no repositório

### Passo 4 — Testes unitários

- Criado `test/domains/scheduling/slot_generator_test.dart` cobrindo:
  - `parseDateKey` — chave válida e inválida
  - `isScheduleEnabled` — com flag explícita e fallback por horários
  - `normalizeLegacyConfigs` — lista legada e inputs inválidos
  - `generateSlotsForDate` — slots livres, slot ocupado, dia sem config, `requiredDurationMinutes`, slot de almoço
  - Use case com mock de repositório

### Arquivos Impactados

- `lib/features/provider/provider_home_fixed.dart`
- `lib/features/client/home_prestador_fixo.dart`
- `lib/domains/scheduling/domain/slot_generator.dart`
- `lib/domains/scheduling/scheduling.dart`
- `lib/integrations/supabase/scheduling/supabase_scheduling_repository.dart`
- `test/domains/scheduling/slot_generator_test.dart`

### Validação

- `dart analyze test/domains/scheduling/slot_generator_test.dart lib/domains/scheduling/ lib/integrations/supabase/scheduling/ lib/features/provider/provider_home_fixed.dart lib/features/client/home_prestador_fixo.dart`
  - resultado: `No issues found!`

## 2026-04-30 - Etapa 10 (chat) fechamento do corte de conversas/participantes

### Ajustes realizados

- `lib/features/shared/chat_list_screen.dart`
  - removida dependência direta de `ApiService` para papel do usuário no fluxo de lista de conversas;
  - papel (`user_role`) passa a ser lido de `SharedPreferences` no carregamento inicial;
  - fluxo de listagem permanece canônico via `DataGateway.loadChatConversations()`.

- `lib/features/provider/medical_chat_list.dart`
  - removido uso de `_api.getMyServices()` para montar conversas;
  - lista migrada para `DataGateway.loadChatConversations()`, reduzindo acoplamento com `ApiService` neste fluxo.

### Resultado do corte

- Fluxo principal de listagem de conversas agora está canônico no `DataGateway` nas duas telas de lista (`ChatListScreen` e `MedicalChatList`).
- Permanece como pendência residual de etapa futura: campos enriquecidos de conversa (ex.: `unread_count`/preview em todos os cenários) e eventuais pontos secundários ainda dependentes de `ApiService` fora do core de listagem.

### Validação

- `dart format lib/features/shared/chat_list_screen.dart lib/features/provider/medical_chat_list.dart`
- `flutter analyze lib/features/shared/chat_list_screen.dart lib/features/provider/medical_chat_list.dart lib/services/data_gateway.dart`
  - resultado: `No issues found!`

## 2026-04-30 - Revisão final Etapa 10 (chat) e fechamento formal

### Status geral

- **Etapa 10: funcionalmente concluída no fluxo principal de chat** (lista de conversas + participantes + envio/leitura de mensagens no caminho principal).

### Evidências de fechamento

- Listagem de conversas canônica via `DataGateway.loadChatConversations()`:
  - `lib/features/shared/chat_list_screen.dart`
  - `lib/features/provider/medical_chat_list.dart`
- Participantes do chat centralizados em `DataGateway` (`snapshot`, remoto e sync):
  - `lib/services/data_gateway.dart`
- Envio de mensagem no fluxo principal via comando canônico `send-chat-message`:
  - `lib/services/data_gateway.dart` (`sendChatMessage`)
- Marcação de leitura via `mark-chat-message-read`:
  - `lib/services/data_gateway.dart` (`markChatMessageRead`)
- Tela de chat principal já consome `DataGateway` para stream e participantes:
  - `lib/features/shared/chat_screen.dart`

### Pendências residuais (baixo impacto, não bloqueiam fechamento da etapa)

- Ainda há usos de `getMyServices()` fora do core estrito do chat (ex.: telas amplas de home/atividade) que coexistem com o fluxo novo:
  - `lib/features/provider/provider_home_mobile.dart`
  - `lib/features/provider/medical_home_screen.dart`
  - `lib/features/client/my_services_screen.dart`
  - `lib/features/activity/activity_screen.dart`
- Contador global `unread_chat_count` permanece em `SharedPreferences` como estado de UI e pode divergir do servidor em cenários específicos de multitela.

### Conclusão formal da etapa

- **Etapa 10 encerrada** para o objetivo definido de canonização de conversas/participantes e redução de dependência direta do `ApiService` no fluxo principal do chat.
- Resíduos listados acima ficam como melhoria incremental para etapa posterior (hardening de consistência de unread e convergência total de telas secundárias).

## 2026-04-30 - Etapa 11 (início) - corte 1 concluído

### Objetivo do corte

- Reduzir dependência de `ApiService.getMyServices()` em telas secundárias críticas do ecossistema de chat/home provider.

### Mudanças aplicadas

- `lib/services/data_gateway.dart`
  - adicionado `loadMyServices()` canônico via `service_requests_new`:
    - resolve usuário atual com `getMyUserId()`;
    - busca serviços em que o usuário é `provider_id` ou `client_id`;
    - ordena por `updated_at desc`.

- `lib/features/provider/provider_home_mobile.dart`
  - `_api.getMyServices()` substituído por `DataGateway().loadMyServices()` no `_loadData()`.

- `lib/features/provider/medical_home_screen.dart`
  - `_api.getMyServices()` substituído por `DataGateway().loadMyServices()` no `_loadData()`.

### Checklist Etapa 11

- [x] Migrar telas secundárias de maior impacto (`provider_home_mobile` e `medical_home_screen`) para fonte canônica de serviços.
- [ ] Canonizar contador `unread` no servidor (reduzir acoplamento com `SharedPreferences`).
- [ ] Revisar/retirar resíduos legados secundários restantes no fluxo de chat.
- [ ] Fechamento formal da Etapa 11 com validação final integrada.

### Validação

- `dart format lib/services/data_gateway.dart lib/features/provider/medical_home_screen.dart lib/features/provider/provider_home_mobile.dart`
- `flutter analyze lib/services/data_gateway.dart lib/features/provider/medical_home_screen.dart lib/features/provider/provider_home_mobile.dart`
  - resultado: `No issues found!`

## 2026-04-30 - Etapa 11 - corte 2 (unread canônico no servidor)

### Objetivo do corte

- Canonizar contagem de mensagens não lidas de chat no servidor.
- Remover dependência residual de `SharedPreferences` para contador global de unread.

### Mudanças aplicadas

- `lib/services/data_gateway.dart`
  - adicionado `loadUnreadChatCount()`:
    - resolve usuário atual;
    - lista serviços do usuário em `service_chat_participants`;
    - conta mensagens não lidas em `chat_messages` (`read_at is null`) ignorando mensagens enviadas pelo próprio usuário.

- `lib/features/home/home_screen.dart`
  - `_bootstrapChatUiState()` agora usa `DataGateway().loadUnreadChatCount()` (sem leitura de `SharedPreferences`).
  - listener de preview (`_bindGlobalChatPreviewListener`) atualiza unread via `loadUnreadChatCount()` (sem fallback local).

- `lib/features/provider/medical_home_screen.dart`
  - remoção de leitura/escrita de `unread_chat_count` em `SharedPreferences`.
  - `_initRealtime()` e `_handleChatMessage()` passam a usar `DataGateway().loadUnreadChatCount()`.

- `lib/features/shared/chat_list_screen.dart`
  - removida escrita local `prefs.setInt('unread_chat_count', 0)` ao abrir lista de chat.

- `lib/features/shared/chat_screen.dart`
  - removida escrita local `prefs.setInt('unread_chat_count', 0)` ao abrir conversa.

### Checklist Etapa 11 (atualizado)

- [x] Migrar telas secundárias de maior impacto (`provider_home_mobile` e `medical_home_screen`) para fonte canônica de serviços.
- [x] Canonizar contador `unread` no servidor (redução de acoplamento com `SharedPreferences`).
- [ ] Revisar/retirar resíduos legados secundários restantes no fluxo de chat.
- [ ] Fechamento formal da Etapa 11 com validação final integrada.

### Validação

- `dart format lib/services/data_gateway.dart lib/features/home/home_screen.dart lib/features/provider/medical_home_screen.dart lib/features/shared/chat_list_screen.dart lib/features/shared/chat_screen.dart`
- `flutter analyze lib/services/data_gateway.dart lib/features/home/home_screen.dart lib/features/provider/medical_home_screen.dart lib/features/shared/chat_list_screen.dart lib/features/shared/chat_screen.dart`
  - resultado: `No issues found!`

## 2026-04-30 - Etapa 11 - corte 3 (limpeza de resíduos secundários) + fechamento formal

### Objetivo do corte

- Remover resíduos secundários ainda acoplados a `ApiService.getMyServices()` fora do core de chat.

### Mudanças aplicadas

- `lib/features/client/my_services_screen.dart`
  - substituído `_api.getMyServices()` por `DataGateway().loadMyServices()`;
  - removida dependência direta de `ApiService` nessa tela.

- `lib/features/activity/activity_screen.dart`
  - substituído `_api.getMyServices()` por `DataGateway().loadMyServices()`;
  - removida dependência direta de `ApiService` nessa tela.

### Verificação de resíduos

- Busca por `getMyServices(` no escopo `lib/features`:
  - **sem ocorrências**.
- Método legado permanece apenas em `lib/services/api_service.dart` para compatibilidade transitória:
  - `lib/services/api_service.dart:7227`.

### Checklist Etapa 11 (final)

- [x] Migrar telas secundárias de maior impacto (`provider_home_mobile` e `medical_home_screen`) para fonte canônica de serviços.
- [x] Canonizar contador `unread` no servidor (redução de acoplamento com `SharedPreferences`).
- [x] Revisar/retirar resíduos legados secundários restantes no fluxo de chat.
- [x] Fechamento formal da Etapa 11 com validação final integrada.

### Validação

- `dart format lib/features/client/my_services_screen.dart lib/features/activity/activity_screen.dart`
- `flutter analyze lib/features/client/my_services_screen.dart lib/features/activity/activity_screen.dart lib/services/data_gateway.dart`
  - resultado: `No issues found!`

### Conclusão formal

- **Etapa 11 concluída** no objetivo de consolidar o fluxo de chat/serviços secundários no caminho canônico (`DataGateway`) e reduzir acoplamentos legados no app.

## 2026-04-30 - Etapa 12 concluída: retirada operacional de `getMyServices` legado

### Objetivo da etapa

- Encerrar o uso operacional do agregador legado `ApiService.getMyServices()`.
- Consolidar leitura de “meus serviços” no caminho canônico (`DataGateway.loadMyServices()`).

### Mudanças aplicadas

- `lib/domains/dispatch/provider_mobile_service.dart`
  - `getMyServices()` migrou de `_api.getMyServices()` para `DataGateway().loadMyServices()`.

- `lib/services/api_service.dart`
  - `getMyServices()` foi desativado com `UnsupportedError`, evitando reintrodução silenciosa do caminho legado.

### Verificação de uso

- Busca global por `getMyServices(` em `lib/`:
  - não há mais consumidores de UI/fluxo principal usando `ApiService.getMyServices()`;
  - resta apenas:
    - definição desativada em `ApiService`;
    - método do `ProviderMobileService` já roteado para `DataGateway`.

### Validação

- `dart format lib/services/api_service.dart lib/domains/dispatch/provider_mobile_service.dart`
- `flutter analyze lib/services/api_service.dart lib/domains/dispatch/provider_mobile_service.dart lib/services/data_gateway.dart`
  - resultado: `No issues found!`

### Conclusão formal

- **Etapa 12 concluída** com desativação explícita do legado e consolidação operacional no caminho canônico de serviços.

## 2026-04-30 - Etapa 12 (completa) - limpeza total do legado de serviços

### Objetivo da etapa

- Concluir a retirada operacional de caminhos legados de serviços no app.
- Garantir consumo canônico via `DataGateway`/`DispatchApi` nos fluxos ativos.

### Ajustes adicionais aplicados

- `lib/integrations/remote_ui/default_remote_action_executor.dart`
  - `accept_ride`: `ApiService().acceptService(...)` -> `ApiService().dispatch.acceptService(...)`
  - `reject_ride`: `ApiService().rejectService(...)` -> `ApiService().dispatch.rejectService(...)`

- `lib/features/home/widgets/mobile_service_card.dart`
  - aceite de serviço em mudança de status:
    - `ApiService().acceptService(...)` -> `ApiService().dispatch.acceptService(...)`

- `lib/features/provider/provider_home_mobile.dart`
  - recusa de serviço:
    - `_api.rejectService(...)` -> `_api.dispatch.rejectService(...)`

### Consolidação da etapa

- `ApiService.getMyServices()` permanece apenas como método desativado (`UnsupportedError`) para evitar reintrodução do legado.
- `ProviderMobileService.getMyServices()` já está canônico via `DataGateway.loadMyServices()`.
- Não restam chamadas diretas no app para:
  - `ApiService().acceptService(...)`
  - `ApiService().rejectService(...)`
  - `ApiService().getMyServices(...)`
  - `ApiService().getWalletData(...)`
  - `ApiService().requestWithdrawal(...)`

### Validação

- `dart format lib/integrations/remote_ui/default_remote_action_executor.dart lib/features/home/widgets/mobile_service_card.dart lib/features/provider/provider_home_mobile.dart lib/services/api_service.dart lib/domains/dispatch/provider_mobile_service.dart`
- `flutter analyze lib/integrations/remote_ui/default_remote_action_executor.dart lib/features/home/widgets/mobile_service_card.dart lib/features/provider/provider_home_mobile.dart lib/services/api_service.dart lib/domains/dispatch/provider_mobile_service.dart`
  - resultado: `No issues found!`

### Fechamento formal

- **Etapa 12 concluída integralmente** no escopo de limpeza total do legado de serviços e convergência para os caminhos canônicos ativos.

## 2026-04-30 - Pós-Etapa 12: limpeza incremental de acesso direto Supabase (lote 1)

### Objetivo do lote

- Continuar a remoção de acesso direto ao Supabase no Flutter, arquivo por arquivo, priorizando telas com caminho canônico já disponível.

### Mudanças aplicadas

- `lib/features/provider/medical_chat_list.dart`
  - removidos `ApiService` e `SharedPreferences` não usados no fluxo atual;
  - tela permanece usando apenas `DataGateway.loadChatConversations()`.

- `lib/services/data_gateway.dart`
  - adicionado `loadProviderSchedules(providerId)` para leitura canônica de agenda do prestador;
  - adicionado `loadProviderScheduleExceptions(providerId)` para leitura canônica de exceções de agenda.

- `lib/features/provider/medical_home_screen.dart`
  - removidas leituras diretas de `provider_schedules` e `provider_schedule_exceptions` via `Supabase.instance.client`;
  - tela passa a consumir `DataGateway.loadProviderSchedules()` e `DataGateway.loadProviderScheduleExceptions()`.

- `lib/features/provider/schedule_edit_screen.dart`
  - removidas leituras diretas de agenda/exceções via `Supabase.instance.client` no carregamento;
  - carregamento passa a usar `DataGateway` canônico;
  - gravação mantém caminho do domínio atual via `ApiService.saveScheduleConfig(...)` e `ApiService.saveScheduleExceptions(...)`.

### Resultado do lote

- `medical_home_screen.dart` e `schedule_edit_screen.dart` sem `Supabase.instance.client` direto.
- limpeza de legado morto adicional em `medical_chat_list.dart`.

### Validação

- `dart format lib/features/provider/medical_chat_list.dart lib/services/data_gateway.dart lib/features/provider/medical_home_screen.dart lib/features/provider/schedule_edit_screen.dart`
- `flutter analyze lib/services/data_gateway.dart lib/features/provider/medical_home_screen.dart lib/features/provider/schedule_edit_screen.dart lib/features/provider/medical_chat_list.dart`
  - resultado: `No issues found!`

## 2026-04-30 - Limpeza da Home do cliente: remoção de fallback direto Supabase em agendamento

### Alterações Realizadas

- `lib/features/home/home_screen.dart`
  - removido fallback legado de `_loadUpcomingAppointment()` que consultava diretamente:
    - `agendamento_servico`
    - `providers`
    - `users`
  - removidos helpers legados associados:
    - `_loadUpcomingAppointmentRow(...)`
    - `_loadProviderForAppointment(...)`
  - fluxo de `upcoming appointment` passa a depender apenas do snapshot canônico de backend (`BackendHomeApi.fetchClientHome()`).
  - quando não houver `upcomingAppointment` no snapshot canônico, a home limpa estado local do card e cancela watcher.

### Limpeza adicional

- removido import não utilizado de `supabase_flutter` em `home_screen.dart`;
- removido campo não utilizado `_providerLiteCache`.

### Validação

- `dart format lib/features/home/home_screen.dart`
- `flutter analyze lib/features/home/home_screen.dart`
  - resultado: `No issues found!`

## 2026-04-30 - Home client/backend-first: remoção de acesso direto Supabase em widgets financeiros

### Alterações Realizadas

- `lib/features/home/widgets/payment_mode_selector.dart`
  - removido acesso direto a `Supabase.instance.client` para leitura/atualização de `driver_payment_mode`;
  - leitura agora usa `ApiService.getProfile()`;
  - atualização agora usa `ApiService.updateProfile(customFields: {...})`.

- `lib/features/home/widgets/driver_earnings_card.dart`
  - removido acesso direto a `Supabase.instance.client` para leitura de dados do usuário;
  - leitura agora usa `ApiService.getProfile()`;
  - atualização de modo de pagamento agora usa `ApiService.updateProfile(customFields: {...})`.

### Resultado

- Os dois widgets financeiros da Home deixaram de consultar/escrever `users` diretamente via Supabase no layer de UI.
- Fluxo permanece backend/gateway-orientado sem mudança de UX.

### Validação

- `dart format lib/features/home/widgets/payment_mode_selector.dart lib/features/home/widgets/driver_earnings_card.dart`
- `flutter analyze lib/features/home/widgets/payment_mode_selector.dart lib/features/home/widgets/driver_earnings_card.dart`
  - resultado: `No issues found!`

## 2026-04-30 - Home: mobile_service_card sem leitura direta de service_logs

### Alterações Realizadas

- `lib/services/data_gateway.dart`
  - adicionado `loadServiceLogs(serviceId, {limit})` para leitura canônica de `service_logs`.

- `lib/features/home/widgets/mobile_service_card.dart`
  - `_fetchTrackingHeadline()` deixou de consultar `Supabase.instance.client.from('service_logs')` diretamente;
  - método agora usa `DataGateway().loadServiceLogs(...)`.
  - removidos imports redundantes/não usados após a migração (`supabase_flutter` e import duplicado de `data_gateway`).

### Resultado

- O card de serviço móvel da Home não acessa mais `service_logs` diretamente via Supabase na camada de UI.
- Leitura passou para gateway centralizado.

### Validação

- `dart format lib/features/home/widgets/mobile_service_card.dart lib/services/data_gateway.dart`
- `flutter analyze lib/features/home/widgets/mobile_service_card.dart lib/services/data_gateway.dart`
  - resultado: `No issues found!`

## 2026-04-30 - Limpeza incremental (bloco 1-2): tracking_cubit + dispatch_tracking_timeline

### Alterações Realizadas

- `lib/features/tracking/cubit/tracking_cubit.dart`
  - removida leitura direta de `service_requests_new` via `Supabase.instance.client`;
  - carga inicial do serviço migrada para `ApiService.getServiceDetails(..., scope: ServiceDataScope.mobileOnly)`;
  - limpeza de código morto/constante não usada após migração.

- `lib/features/client/widgets/dispatch_tracking_timeline.dart`
  - removida leitura direta de `service_logs` via Supabase no `_loadLogs()`;
  - timeline passa a consumir `DataGateway.loadServiceLogs(...)`.
  - (canal realtime de `service_logs` foi mantido como transporte de atualização em tempo real nesta etapa).

### Validação

- `dart format lib/features/client/widgets/dispatch_tracking_timeline.dart lib/features/tracking/cubit/tracking_cubit.dart`
- `flutter analyze lib/features/client/widgets/dispatch_tracking_timeline.dart lib/features/tracking/cubit/tracking_cubit.dart lib/services/data_gateway.dart`
  - resultado: `No issues found!`

## 2026-04-30 - Limpeza incremental (bloco 3): provider_service_card sem consultas diretas de usuário/localização

### Alterações Realizadas

- `lib/services/data_gateway.dart`
  - adicionado `resolveUserIdByAuthUid(authUid)` para resolver `users.id` via `supabase_uid`;
  - adicionado `loadProviderStartLocation(providerUserId)` com fallback interno:
    - `provider_locations` (prioritário)
    - `providers` (fallback).

- `lib/features/provider/widgets/provider_service_card.dart`
  - `_resolveCurrentProviderId()` deixou de consultar `users` diretamente via `Supabase.instance.client`;
  - agora usa `DataGateway.resolveUserIdByAuthUid(...)`.
  - `_resolveProviderStartFromDatabase()` deixou de consultar diretamente:
    - `provider_locations`
    - `providers`
  - agora usa `DataGateway.loadProviderStartLocation(...)`.

### Resultado

- `provider_service_card.dart` não acessa mais diretamente essas tabelas de perfil/localização;
- leitura passou para gateway centralizado (camada de dados), reduzindo acoplamento da UI.

### Validação

- `dart format lib/services/data_gateway.dart lib/features/provider/widgets/provider_service_card.dart`
- `flutter analyze lib/services/data_gateway.dart lib/features/provider/widgets/provider_service_card.dart`
  - resultado: `No issues found!`

## 2026-04-30 - Limpeza incremental (bloco 4): service_offer_modal + provider_home_mobile

### Alterações Realizadas

- `lib/services/data_gateway.dart`
  - mantidos e utilizados os novos helpers canônicos para este corte:
    - `loadTaskNameById(taskId)`
    - `loadEmergencyOpenServices(limit)`
    - `loadRejectedServiceIdsForProvider(providerUserId)`
    - `resolveUserIdByAuthUid(authUid)`

- `lib/features/provider/widgets/service_offer_modal.dart`
  - `_ensureTaskName()` passou a resolver `task_name` via `DataGateway.loadTaskNameById(...)`;
  - removido import não usado de `supabase_flutter`;
  - adicionado import de `data_gateway`.

- `lib/features/provider/provider_home_mobile.dart`
  - `_ensureOfferListenerFromAuth()` deixou de consultar `users` direto (`from('users')`);
  - agora usa `DataGateway.resolveUserIdByAuthUid(...)`;
  - `_loadEmergencyOpenServices()` já consolidado com:
    - `DataGateway.loadEmergencyOpenServices(...)`
    - `DataGateway.loadRejectedServiceIdsForProvider(...)`
  - removida constante local não usada (`openStatuses`) após canonização no gateway.

### Resultado

- `service_offer_modal.dart` e `provider_home_mobile.dart` reduziram mais um bloco de acoplamento direto da UI com tabelas Supabase.
- Resolução de tarefa/usuário/ofertas abertas/rejeições ficou centralizada no `DataGateway`.

### Validação

- `dart format lib/features/provider/provider_home_mobile.dart lib/features/provider/widgets/service_offer_modal.dart lib/services/data_gateway.dart`
- `flutter analyze lib/features/provider/provider_home_mobile.dart lib/features/provider/widgets/service_offer_modal.dart lib/services/data_gateway.dart`
  - resultado: `No issues found!`

## 2026-04-30 - Análise de risco Supabase (rodada: 103 ocorrências / foco em serviços centrais)

### Escopo Analisado

- `lib/services/api_service.dart`
- `lib/services/central_service.dart`
- `lib/services/data_gateway.dart`

### Achados Prioritários (sem alteração de lógica nesta rodada)

- Exposição de dados por projeção ampla (`select()`/`select('*')`) em pontos de leitura de listas e serviços, aumentando risco de vazar colunas sensíveis e de quebrar contrato por mudança de schema.
  - Exemplos mapeados:
    - `lib/services/data_gateway.dart:253`
    - `lib/services/data_gateway.dart:314`
    - `lib/services/data_gateway.dart:334`
    - `lib/services/central_service.dart:274`
    - `lib/services/central_service.dart:1309`
    - `lib/services/central_service.dart:1322`
    - `lib/services/api_service.dart:1917`
    - `lib/services/api_service.dart:2197`
    - `lib/services/api_service.dart:2226`

- Joins com wildcard (`providers(*)`, `professions(*)`) em múltiplas consultas de perfil/agendamento, com risco de trazer campos desnecessários e ampliar superfície de autorização.
  - Exemplos:
    - `lib/services/api_service.dart:506`
    - `lib/services/api_service.dart:515`
    - `lib/services/api_service.dart:3170`
    - `lib/services/api_service.dart:6023`
    - `lib/services/api_service.dart:6229`

- Tratamento de exceção genérico (`catch (e)`) com retorno fallback em vários fluxos de leitura, podendo mascarar erro de RLS/permissão/coluna inexistente como “lista vazia”, dificultando observabilidade.
  - Concentração alta em:
    - `lib/services/data_gateway.dart`
    - `lib/services/central_service.dart`
    - `lib/services/api_service.dart`

### Plano técnico recomendado para próxima execução

- Fase 1 (baixo risco): substituir `select()`/`select('*')` por colunas explícitas nos fluxos mais sensíveis (`users`, `service_requests_new`, `user_payment_methods`).
- Fase 2 (médio risco): reduzir joins `(*)` para projeções mínimas necessárias por tela/use-case.
- Fase 3 (baixo/médio risco): padronizar tratamento de erro com distinção explícita para `PostgrestException` (`403/42501/42703`), mantendo fallback somente quando intencional e auditável.
- Fase 4 (segurança): revisar se cada acesso client-side tem política RLS correspondente e teste negativo (usuário sem permissão).

### Observação

- Esta rodada foi exclusivamente de análise estática e priorização; não houve mudança de comportamento em runtime.

## 2026-04-30 - Fase 1 aplicada: projeções explícitas em consultas Supabase (lote 1)

### Alterações Realizadas

- Aplicada Fase 1 nos serviços centrais de menor risco, removendo `select()`/`select('*')` em pontos críticos.
- `DataGateway`:
  - `loadMyServices()` agora usa projeção explícita em `service_requests_new`.
  - `loadProviderSchedules()` agora usa projeção explícita em `provider_schedules`.
  - `loadProviderScheduleExceptions()` agora usa projeção explícita em `provider_schedule_exceptions`.
- `CentralService`:
  - `resolvePaymentMethodDetails()` agora usa projeção explícita em `user_payment_methods`.
  - `getCurrentServiceRequest()` (consultas por `client_id` e `client_uid`) agora usa projeção explícita em `service_requests_new`.

### Arquivos Impactados

- `lib/services/data_gateway.dart`
- `lib/services/central_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/services/data_gateway.dart lib/services/central_service.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - o comando retornou exit code 1 por falha de telemetria do Dart ao gravar em filesystem somente leitura (`dart-flutter-telemetry-session.json`), após análise concluída; não indica erro de código nos arquivos alterados.

## 2026-04-30 - Fase 1 aplicada: projeções explícitas em consultas Supabase (lote 2 / api_service)

### Alterações Realizadas

- Continuidade da Fase 1 em `ApiService`, removendo `select()` aberto nos fluxos de intents PIX e configuração global.
- `fixed_booking_pix_intents`:
  - criação de intent (`insert(...).select(...)`) passou a usar projeção explícita.
  - leitura por id (`getPendingFixedBookingIntent`) passou a usar projeção explícita.
  - leitura da intent pendente mais recente (`getLatestPendingFixedBookingIntentForCurrentClient`) passou a usar projeção explícita.
- `app_configs`:
  - `getAppConfig()` passou de `select()` para `select('key,value')`.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - o comando retornou exit code 1 por falha de telemetria do Dart ao gravar em filesystem somente leitura (`dart-flutter-telemetry-session.json`), após análise concluída; não indica erro de código no arquivo alterado.

## 2026-04-30 - Fase 1 aplicada: projeções explícitas em consultas Supabase (lote 3 parcial / users em api_service)

### Alterações Realizadas

- Iniciado o lote 3 com foco na superfície de `users` em `ApiService`.
- Criada constante central de projeção explícita:
  - `_usersProfileProjection`
- Substituídos `select()` abertos por projeção explícita nos fluxos:
  - `registerWithSupabase()` (upsert + retorno do usuário)
  - `getUserData()`
  - `loginWithFirebase()` (busca por `supabase_uid`, fallback por `email`, upsert de novo usuário)
  - `updateProfile()` (update com `select` de retorno, inclusive fallback sem `document_type`)
  - `refreshUserData()`

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - o comando retornou exit code 1 por falha de telemetria do Dart ao gravar em filesystem somente leitura (`dart-flutter-telemetry-session.json`), após análise concluída; não indica erro de código no arquivo alterado.

## 2026-04-30 - Fase 1 aplicada: projeções explícitas em consultas Supabase (lote 3 complemento / service_requests_new)

### Alterações Realizadas

- Continuidade do lote 3 em `ApiService` para fluxo de criação de serviço móvel.
- Criada constante de projeção explícita:
  - `_serviceRequestProjection`
- Substituído `select()` aberto em `createServiceRequest(...)` após `insert` em `service_requests_new` por `select(_serviceRequestProjection)`.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - o comando retornou exit code 1 por falha de telemetria do Dart ao gravar em filesystem somente leitura (`dart-flutter-telemetry-session.json`), após análise concluída; não indica erro de código no arquivo alterado.

## 2026-04-30 - Fase 1 aplicada: remoção de wildcard em joins (lote 3 / passada atual)

### Alterações Realizadas

- Removidos `select('*, ...')` com wildcard nos fluxos principais de `agendamento_servico` e `service_requests_new` em `ApiService`.
- Criadas projeções explícitas:
  - `_fixedBookingWithTaskProjection`
  - `_mobileServiceDetailsProjection`
- Pontos atualizados:
  - criação de agendamento fixo (`insert(...).select(...)` em `agendamento_servico`)
  - `getAvailableServices()` (lista fixa pendente)
  - `getServiceDetails()` para escopo fixo (`agendamento_servico`)
  - `getServiceDetails()` para escopo móvel (`service_requests_new` com joins de cliente/prestador/categoria)

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - o comando retornou exit code 1 por falha de telemetria do Dart ao gravar em filesystem somente leitura (`dart-flutter-telemetry-session.json`), após análise concluída; não indica erro de código no arquivo alterado.

## 2026-04-30 - Limpeza profunda iniciada na Home do cliente (remoção de shims legados)

### Alterações Realizadas

- Removidos dois arquivos de compatibilidade sem lógica de negócio (apenas alias/reexport), reduzindo superfície de manutenção no fluxo da Home/pedido de serviço:
  - `lib/features/client/service_request_screen_fixed.dart` (reexport)
  - `lib/features/client/home_prestador_movel.dart` (reexport legado)
- Atualizados imports para apontar diretamente para o arquivo canônico:
  - `lib/main.dart`: `service_request_screen_fixed.dart` -> `home_prestador_fixo.dart`
  - `lib/features/client/service_request_screen.dart`: `service_request_screen_fixed.dart` -> `home_prestador_fixo.dart`
- Ajustada referência textual em documentação inline:
  - `lib/features/client/service_request_screen_mobile.dart`

### Arquivos Impactados

- `lib/main.dart`
- `lib/features/client/service_request_screen.dart`
- `lib/features/client/service_request_screen_mobile.dart`
- `lib/features/client/service_request_screen_fixed.dart` (removido)
- `lib/features/client/home_prestador_movel.dart` (removido)
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/main.dart lib/features/client/service_request_screen.dart lib/features/client/service_request_screen_mobile.dart lib/features/client/home_prestador_fixo.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - o comando retornou exit code 1 por falha de telemetria do Dart ao gravar em filesystem somente leitura (`dart-flutter-telemetry-session.json`), após análise concluída; não indica erro de código nos arquivos alterados.

## 2026-04-30 - Limpeza profunda Home do cliente (passada 2: remoção de métodos privados órfãos)

### Alterações Realizadas

- Varredura por referência interna em `home_screen.dart` e `home_prestador_fixo.dart`.
- Removidos métodos privados comprovadamente órfãos em `home_screen.dart` (sem chamadas no arquivo):
  - `_loadPersistedPendingFixedPix()`
  - `_buildPendingInfoChip(...)`
  - `_initRefreshTimer()`
- Não foram encontrados métodos privados órfãos adicionais em `home_prestador_fixo.dart` nesta passada.

### Arquivos Impactados

- `lib/features/home/home_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/features/home/home_screen.dart lib/features/client/home_prestador_fixo.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - o comando retornou exit code 1 por falha de telemetria do Dart ao gravar em filesystem somente leitura (`dart-flutter-telemetry-session.json`), após análise concluída; não indica erro de código nos arquivos alterados.

## 2026-04-30 - Limpeza profunda Home (passada 3: varredura de campos órfãos em widgets grandes)

### Escopo Analisado

- `lib/features/home/widgets/mobile_service_card.dart`
- `lib/features/home/widgets/fixed_service_card.dart`
- `lib/features/home/widgets/home_stage_panel_body.dart`

### Resultado

- Executada varredura de campos privados com heurística de contagem e validação via analyzer.
- `dart analyze` dos três arquivos retornou sem issues de código.
- Não foram aplicadas remoções nesta passada por segurança:
  - os candidatos apontados por contagem bruta não foram tratados como prova suficiente de código morto (podem estar conectados por callbacks/fluxo de estado), então a remoção automática poderia introduzir regressão comportamental.

### Validação

- Executado:
  - `dart analyze lib/features/home/widgets/mobile_service_card.dart lib/features/home/widgets/fixed_service_card.dart lib/features/home/widgets/home_stage_panel_body.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - o comando retornou exit code 1 por falha de telemetria do Dart ao gravar em filesystem somente leitura (`dart-flutter-telemetry-session.json`), após análise concluída; não indica erro de código nos arquivos analisados.

## 2026-04-30 - Limpeza semântica manual (arquivo único: fixed_service_card.dart)

### Escopo Analisado

- `lib/features/home/widgets/fixed_service_card.dart`

### Verificação Semântica (initState/dispose/build/callbacks)

- Campos privados revisados com rastreio de uso real:
  - `_expanded`: usado na resolução do estado expandido no `build`.
  - `_refreshTimer`: inicializado no polling, cancelado em `dispose` e reiniciado em `_startTravelPolling`.
  - `_lastScheduledAtForNotify`: usado para deduplicar agendamento de notificação.
  - `_alertTriggered`: usado para evitar múltiplos disparos de modal.
- Helpers privados relevantes também em uso:
  - `_toDate`, `_formatFriendlyDate`, `_isAwaitingFixedDeposit`.

### Resultado

- Nenhum campo privado órfão confirmado neste arquivo.
- Nenhuma remoção aplicada nesta passada (decisão de segurança para evitar regressão comportamental).

## 2026-04-30 - Migração Bloco 1 (api_service): agenda de prestador backend-first

### Alterações Realizadas

- Iniciada execução prática do Bloco 1 em `ApiService` para reduzir dependência de Supabase direto.
- `getProviderSlots(...)` foi atualizado para estratégia backend-first:
  - tenta `BackendSchedulingApi.fetchProviderSlots(...)` como fonte canônica JSON;
  - mantém fallback temporário para consulta Supabase quando backend indisponível.
- Import e dependência adicionados:
  - `lib/core/scheduling/backend_scheduling_api.dart`
  - `final BackendSchedulingApi _backendSchedulingApi = const BackendSchedulingApi();`

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - o comando retornou exit code 1 por falha de telemetria do Dart ao gravar em filesystem somente leitura (`dart-flutter-telemetry-session.json`), após análise concluída; não indica erro de código no arquivo alterado.

## 2026-04-30 - Migração Bloco 1 (api_service): perfil helper backend-first com fallback

### Alterações Realizadas

- Continuidade da execução prática do Bloco 1 em `ApiService` para reduzir leitura direta via Supabase.
- Helpers de perfil ajustados para backend-first com fallback temporário:
  - `_getUserRowById(int userId)`
  - `_getUserRowByAuthUid(String authUid)`
- Estratégia aplicada:
  - tenta resolver dados a partir do snapshot canônico (`BackendHomeApi.fetchClientHome()`);
  - mantém fallback Supabase (`users` com join `providers`) apenas para compatibilidade transitória.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - o comando retornou exit code 1 por falha de telemetria do Dart ao gravar em filesystem somente leitura (`dart-flutter-telemetry-session.json`), após análise concluída; não indica erro de código no arquivo alterado.

## 2026-04-30 - Execução em etapas (1 → 2 → 3) nos arquivos grandes

### Etapa 1 — `provider_home_fixed.dart`

- Corrigida quebra de compilação causada por mudança de assinatura de `SupabaseSchedulingRepository`:
  - antes: `SupabaseSchedulingRepository(_api)`
  - depois: `SupabaseSchedulingRepository()`
- Arquivo validado após ajuste.

### Etapa 2 — `service_tracking_page.dart`

- Varredura e validação estática executadas.
- Nenhuma inconsistência estrutural encontrada nesta passada.

### Etapa 3 — `notification_service.dart`

- Varredura e validação estática executadas.
- Nenhuma inconsistência estrutural encontrada nesta passada.

### Arquivos Impactados

- `lib/features/provider/provider_home_fixed.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/features/provider/provider_home_fixed.dart`
  - `dart analyze lib/features/client/service_tracking_page.dart`
  - `dart analyze lib/services/notification_service.dart`
- Resultado:
  - Flutter/Dart: `No issues found!` nos três arquivos
- Observação:
  - os comandos retornaram exit code 1 por falha de telemetria do Dart ao gravar em filesystem somente leitura (`dart-flutter-telemetry-session.json`) após a análise; não indica erro de código.

## 2026-04-30 - Execução automática em etapas (4 → 5 → 6)

### Etapa 4 — `home_prestador_fixo.dart`

- Varredura + validação estática executadas.
- Nenhuma inconsistência estrutural detectada nesta passada.

### Etapa 5 — `home_screen.dart`

- Varredura + validação estática executadas.
- Nenhuma inconsistência estrutural detectada nesta passada.

### Etapa 6 — `mobile_service_card.dart`

- Varredura + validação estática executadas.
- Nenhuma inconsistência estrutural detectada nesta passada.

### Arquivos Impactados

- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/features/client/home_prestador_fixo.dart`
  - `dart analyze lib/features/home/home_screen.dart`
  - `dart analyze lib/features/home/widgets/mobile_service_card.dart`
- Resultado:
  - Flutter/Dart: `No issues found!` nos três arquivos
- Observação:
  - os comandos retornaram exit code 1 por falha de telemetria do Dart ao gravar em filesystem somente leitura (`dart-flutter-telemetry-session.json`) após a análise; não indica erro de código.

## 2026-05-01 - Limpeza linha por linha do provider_home_fixed.dart

### Alterações Realizadas

- Removido `_isScheduleEnabled` — duplicata exata de `SlotGenerator.isScheduleEnabled` já extraído.
- `_generateSlotsFromSchedule` reduzido de ~180 para ~50 linhas: a geração de slots agora delega para `const SlotGenerator().generateSlotsForDate(...)`. A lógica de `spansNextDay`, loop de slots, almoço e ordenação foi eliminada da tela.
- Corrigido `SupabaseSchedulingRepository()` — construtor usa parâmetros nomeados opcionais (`BackendSchedulingApi`, `BackendTrackingApi`), não aceita `ApiService` posicional.
- Removida chamada desnecessária `await _api.getProviderServices()` no botão "Fechar" do modal de serviços — era um reload sem uso do resultado.
- `Stream.empty()` tipado explicitamente como `Stream<List<Map<String, dynamic>>>.empty()` para eliminar inferência ambígua no `StreamBuilder` de notificações.

### Usos legítimos restantes do `_api`

Os seguintes usos permanecem e serão extraídos quando os domínios correspondentes forem criados:

- `_api.loadToken()`, `_api.getMyProfile()`, `_api.userId`, `_api.role` → domínio `auth/identity`
- `_api.invalidateMediaBytesCache()` → domínio `media`
- `_api.getProviderServices()`, `_api.setProviderServiceActive()` → domínio `provider_profile`
- `_api.getServiceDetails()`, `_api.completeService()` → domínio `service`

### Resultado

- Antes: 3.623 linhas
- Depois: 3.437 linhas (-186 linhas)

### Arquivos Impactados

- `lib/features/provider/provider_home_fixed.dart`

### Validação

- `dart analyze lib/features/provider/provider_home_fixed.dart`
  - resultado: `No issues found!`

## 2026-04-30 - Execução automática em etapas (10 → 11 → 12)

### Etapa 10 — `provider_service_card.dart`
- Varredura + validação estática executadas.
- Nenhuma inconsistência estrutural detectada nesta passada.

### Etapa 11 — `service_offer_modal.dart`
- Varredura + validação estática executadas.
- Nenhuma inconsistência estrutural detectada nesta passada.

### Etapa 12 — `central_service.dart`
- Varredura + validação estática executadas.
- Nenhuma inconsistência estrutural detectada nesta passada.

### Validação
- `dart analyze lib/features/provider/widgets/provider_service_card.dart`
- `dart analyze lib/features/provider/widgets/service_offer_modal.dart`
- `dart analyze lib/services/central_service.dart`
- Resultado: `No issues found!`
- Observação: comandos encerram com erro de telemetria Dart em FS read-only após análise; não é erro de código.

## 2026-04-30 - Execução automática em etapas (16 → 17 → 18)

### Etapa 16 — `service_panel_content.dart`

- Detectado erro real no analyzer:
  - uso de `mounted` fora de classe `State`.
- Correção aplicada:
  - removida checagem `if (mounted)` no handler de copiar PIX;
  - mantido `ScaffoldMessenger.of(context).showSnackBar(...)` direto.

### Etapa 17 — `home_search_screen.dart`

- Varredura + validação estática executadas.
- Nenhuma inconsistência estrutural detectada nesta passada.

### Etapa 18 — `home_explore_screen.dart`

- Varredura + validação estática executadas.
- Nenhuma inconsistência estrutural detectada nesta passada.

### Arquivos Impactados

- `lib/features/tracking/widgets/service_panel_content.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/features/tracking/widgets/service_panel_content.dart`
  - `dart analyze lib/features/home/home_search_screen.dart`
  - `dart analyze lib/features/home/home_explore_screen.dart`
- Resultado:
  - Flutter/Dart: `No issues found!` nos três arquivos
- Observação:
  - os comandos retornaram exit code 1 por falha de telemetria do Dart ao gravar em filesystem somente leitura (`dart-flutter-telemetry-session.json`) após a análise; não indica erro de código.

## 2026-04-30 - Home cliente 100% backend (passada REST)

### Objetivo

- Reduzir acoplamento da Home com consultas diretas ao Supabase no app.
- Garantir que cards/estado da Home usem snapshot REST JSON como fonte principal.

### Alterações aplicadas

- `lib/features/home/home_screen.dart`
  - Adicionado uso de `BackendTrackingApi` para refresh do banner de serviço ativo.
  - Substituído refresh periódico de `_api.getServiceDetails(...)` por:
    - `_backendTrackingApi.fetchServiceDetails(activeId, scope: ServiceDataScope.mobileOnly.name)`.
  - Ajustado carregamento de catálogo da Home para usar snapshot backend:
    - `_loadServiceAutocompleteCatalog()` agora usa `await _fetchBackendHomeSnapshot(force: true)` e deriva itens de `snapshot.services`.
    - Removida dependência prática de `fetchActiveTaskCatalog()` (que consulta Supabase diretamente) no fluxo da Home.

### Resultado

- Home passa a depender de endpoints REST JSON já existentes para:
  - snapshot principal (`/api/v1/home/client`),
  - detalhe de serviço no refresh do banner (`/api/v1/tracking/services/:id`).
- Sem alterações visuais de layout nesta passada; foco foi fonte de dados e navegação/refresh.

### Validação

- Executado:
  - `dart analyze lib/features/home/home_screen.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - comando retorna erro de telemetria Dart por filesystem read-only (`dart-flutter-telemetry-session.json`) após análise; não é erro de código.

## 2026-04-30 - Busca da Home via REST JSON (clique + resultados)

### Objetivo

- Garantir que o fluxo de busca iniciado pela Home use dados vindos da API REST JSON.
- Evitar consulta direta ao Supabase no carregamento de catálogo/resultados da tela de busca.

### Alterações aplicadas

- `lib/features/home/home_search_screen.dart`
  - Adicionado `BackendHomeApi`.
  - `_loadServiceAutocompleteCatalog()` deixou de usar `ApiService.fetchActiveTaskCatalog()`.
  - Agora o catálogo base vem de `BackendHomeApi.fetchClientHome()` (endpoint `/api/v1/home/client`) via `snapshot.services`.

### Efeito prático

- Ao tocar na barra de busca da Home, a navegação para `/home-search` permanece.
- A tela de busca passa a montar seus resultados/sugestões em cima do payload REST da Home, sem depender do catálogo carregado diretamente do Supabase nesse fluxo.


## 2026-04-30 - Corte final REST: getServiceDetails + HomeSearchBar + delay de vazio

### Objetivo

- Remover fallbacks Supabase no fluxo de detalhes e busca da Home.
- Exibir mensagem de "nenhum resultado" somente após 10s sem retorno.

### Alterações aplicadas

- `lib/services/api_service.dart`
  - `getServiceDetails(...)` agora usa somente backend (`_backendTrackingApi.fetchServiceDetails`).
  - Removidos os blocos de fallback que consultavam direto:
    - `agendamento_servico`
    - `service_requests_new`
    - `client_locations`

- `lib/features/home/widgets/home_search_bar.dart`
  - Removidos `ApiService` e buscas diretas dependentes de Supabase.
  - Busca interna agora carrega catálogo via `BackendHomeApi.fetchClientHome()` e usa `snapshot.services`.
  - Sugestões passam a ser apenas do resultado semântico sobre payload REST.

- `lib/features/home/home_search_screen.dart`
  - Adicionado controle temporal da mensagem de vazio:
    - `_allowNoResultsMessage`
    - `_noResultDelayTimer`
    - `_armNoResultMessageDelay(...)`
  - Mensagem `Nenhum resultado...` só é renderizada quando:
    - há texto de busca,
    - lista de resultados está vazia,
    - e passaram 10 segundos sem resultado.


## 2026-04-30 - Confirmar serviço móvel: hidratação REST da UI

### Objetivo

- Garantir que os dados exibidos na tela `Confirmar servico` sejam obtidos do payload REST canônico.

### Alterações aplicadas

- `lib/features/home/mobile_service_request_review_screen.dart`
  - Adicionado `BackendHomeApi`.
  - Criado `_hydrateServiceDataFromRest()` para buscar `/api/v1/home/client` e hidratar dados do card por match de `task_id` (ou nome da tarefa).
  - UI passa a usar `_serviceData` priorizando `_restServiceData` (REST) e usando `suggestion` apenas como seed/fallback de bootstrap.

### Resultado

- Bloco exibido (nome do serviço, profissão e preço) passa a vir da API REST da Home quando disponível.

### Validação

- `dart analyze lib/features/home/mobile_service_request_review_screen.dart`
- Resultado: `No issues found!`
- Observação: erro de telemetria Dart em filesystem read-only após análise não afeta código.

## 2026-04-30 - Correção erro ao enviar PIX (createService)

### Sintoma

- Falha ao criar serviço móvel com erro de coluna inexistente no retorno do insert:
  - `column service_requests_new.category does not exist (42703)`.

### Causa

- Após o `insert`, o código fazia `select(_serviceRequestProjection)` com colunas rígidas legadas.
- No schema local atual, pelo menos uma dessas colunas não existe.

### Correção

- `lib/services/api_service.dart`
  - Em `createService(...)`, alterado retorno de:
    - `.select(_serviceRequestProjection)`
  - para:
    - `.select()`

### Resultado esperado

- Insert continua funcionando mesmo com variação de schema entre ambientes.
- Fluxo de criação/PIX deixa de quebrar por projeção de retorno incompatível.

## 2026-04-30 - Corte de consultas diretas (logs críticos)

### Ajustes aplicados

- `lib/services/api_service.dart`
  - `findActiveService()` agora é somente REST (`_backendTrackingApi.fetchActiveService`).
  - Removido fallback "Dual-Table" com `Supabase.instance`.

- `lib/services/data_gateway.dart`
  - `loadMyServices()` removido de consulta direta em `service_requests_new`; agora usa snapshot REST via `ApiService.getActiveServiceSnapshot(forceRefresh: true)`.
  - `loadUnreadChatCount()` sem consulta direta em `service_chat_participants/chat_messages` (retorno `0` temporário até endpoint REST de unread).

### Objetivo

- Eliminar chamadas diretas ao Supabase nos pontos que estavam quebrando com schema local divergente e seguir padrão REST-only.

## 2026-04-30 - Remoção real de código legado Supabase (passada de limpeza)

### Remoções feitas

- `lib/services/api_service.dart`
  - Removido import não utilizado:
    - `support/api_active_service_resolver.dart`
  - Removidas constantes de projeção legada que sustentavam caminho direto/antigo:
    - `_serviceRequestProjection`
    - `_mobileServiceDetailsProjection`

### Validação

- Executado: `dart analyze lib/services/api_service.dart lib/services/data_gateway.dart`
- Resultado: sem erros novos; restaram apenas warnings de métodos órfãos já mapeados.

## 2026-04-30 - Remoção de métodos órfãos (api_service)

### Removidos

- `lib/services/api_service.dart`
  - `_normalizeProviderAgendaAppointmentSlot(...)`
  - `_normalizeProviderAgendaHoldSlot(...)`
  - `_loadFixedBookingsForAgenda(...)`

### Validação

- Executado: `dart analyze lib/services/api_service.dart`
- Resultado: sem erro de compilação; restaram 2 warnings novos de helpers que ficaram órfãos após este corte:
  - `_normalizeProviderAgendaSlotStatus`
  - `_toLocalIsoString`

## 2026-04-30 - Remoção final de helpers órfãos (api_service)

### Removidos

- `lib/services/api_service.dart`
  - `_normalizeProviderAgendaSlotStatus(...)`
  - `_toLocalIsoString(...)`

### Validação

- Executado: `dart analyze lib/services/api_service.dart`
- Objetivo: eliminar sobras de código legado órfão após migração REST.

## 2026-04-30 - Correção schema users (updated_at ausente)

### Problema

- `PostgrestException 42703`: `column users.updated_at does not exist` durante auto-sync/login.

### Correção aplicada

- `lib/services/api_service.dart`
  - Ajustada projeção base de usuário (`_usersProfileProjection`) removendo `updated_at`.
  - Projeção passou de:
    - `..., preferred_payment_method,created_at,updated_at`
  - para:
    - `..., preferred_payment_method,created_at`

### Resultado esperado

- Fluxos de sincronização de usuário no login deixam de falhar por coluna inexistente no schema local.

## 2026-04-30 - Correção de crash por ciclo de vida (context/setState assíncrono)

### Problema

- Exceções em runtime:
  - `Looking up a deactivated widget's ancestor is unsafe`
  - `A TextEditingController was used after being disposed`
- Stack apontava para fluxo de localização da Home.

### Correções aplicadas

- `lib/features/home/mixins/home_location_mixin.dart`
  - Adicionado guard de ciclo de vida (`_isDisposed`) no mixin.
  - `checkLocationPermission()` agora aborta cedo se widget já não estiver ativo.
  - Todos os `setState`/`ScaffoldMessenger` passaram a validar `mounted && !_isDisposed`.
  - Em `updateCurrentAddress(...)`, escrita em `pickupController.text` protegida com `try/catch` para evitar exceção pós-dispose.
  - Adicionado `dispose()` no mixin para marcar `_isDisposed = true` antes de propagar `super.dispose()`.

### Validação

- Executado: `dart analyze lib/features/home/mixins/home_location_mixin.dart`
- Resultado: `No issues found!`

## 2026-04-30 - Hardening sync/login de usuário (fallback de projeção users)

### Problema recorrente

- Mesmo após remover `updated_at` da projeção principal, o web seguia emitindo requests com `users.updated_at` e falhando com `42703`.

### Correção aplicada

- `lib/services/api_service.dart`
  - Adicionado fallback explícito de projeções para `users`:
    - `_usersProfileProjection` (sem `updated_at`)
    - `_usersProfileProjectionLegacy` (com `updated_at`)
  - Adicionado helper resiliente:
    - `_selectUserRowMaybeSingleBy(field, value)`
    - tenta projeções em fallback e ignora schema mismatch (`42703`/`PGRST204`) sem quebrar o fluxo.
  - Fluxos de sync/login atualizados para usar helper/fallback:
    - `getUserData()`
    - `loginWithFirebase()`
    - `updateProfile()`
    - `refreshUserData()`
  - Removido acoplamento de `updateProfile()` ao `select(...).single()` imediato após update; agora recarrega via helper seguro.

### Validação

- Executado: `dart analyze lib/services/api_service.dart`
- Resultado: `No issues found!`

## 2026-04-30 - Tratamento de erro ao cancelar serviço (backend offline)

### Problema

- Cancelamento falhando com `ClientException: Failed to fetch` / `ERR_CONNECTION_REFUSED` quando API REST local (`localhost:4011`) está offline.

### Ajuste aplicado

- `lib/features/client/service_tracking_page.dart`
  - `_cancelService()` agora detecta erro de conectividade (`failed to fetch` / `connection refused`) e mostra mensagem amigável:
    - `Backend REST indisponível (localhost:4011). Inicie a API para cancelar o serviço.`
  - Mantido comportamento REST-only (sem fallback Supabase).

### Resultado

- Usuário recebe causa real do problema ao cancelar, em vez de erro técnico bruto.

## 2026-04-30 - Backend único via Supabase (sem localhost:4011 implícito)

### Objetivo

- Remover dependência automática de Node API local (`localhost:4011`).
- Manter backend API único via Supabase.

### Alterações aplicadas

- `lib/core/network/backend_api_client.dart`
  - `resolveBaseUrl()` agora prioriza:
    1. `BACKEND_API_URL` (compile-time),
    2. `SUPABASE_URL` (`SupabaseConfig.url`),
    3. `null`.
  - Removidos fallbacks implícitos para:
    - `http://localhost:4011`
    - `http://10.0.2.2:4011`

- `lib/features/client/service_tracking_page.dart`
  - Mensagem de erro de cancelamento atualizada para contexto Supabase:
    - `Backend API do Supabase indisponível. Verifique SUPABASE_URL/BACKEND_API_URL e tente novamente.`

### Resultado

- App não tenta mais conectar automaticamente em `localhost:4011`.
- Fluxos REST usam configuração Supabase como backend API padrão.

## 2026-04-30 - Cancelamento no tracking migrado para Supabase-only

### Problema

- A tela de tracking cancelava via `BackendTrackingApi` (`/api/v1/tracking/.../cancel`), que depende de roteamento HTTP externo.
- No cenário backend único via Supabase, isso gerava falha quando a rota REST não existia.

### Correção aplicada

- `lib/features/client/service_tracking_page.dart`
  - `_cancelService()` deixou de chamar `BackendTrackingApi.cancelService(...)`.
  - Agora chama `ApiService().cancelService(...)` com `ServiceDataScope`.

### Efeito

- O fluxo passa a usar caminho Supabase direto já implementado em `ApiService.cancelService` quando backend REST não responder.
- Mantém compatibilidade com cenário Supabase-only sem Node API separado.

## 2026-04-30 - Correção CORS Web no tracking com Supabase remoto

### Alterações Realizadas

- Ajustado `ApiService.getServiceDetails(...)` para evitar chamadas REST de tracking (`/api/v1/tracking/...`) no Flutter Web quando a base resolvida é domínio Supabase (`*.supabase.co`).
- Nova regra aplicada:
  - em Web + base Supabase: pula `_backendTrackingApi.fetchServiceDetails(...)`;
  - segue direto para leitura canônica via tabelas Supabase (`agendamento_servico`/`service_requests_new`).
- Objetivo: eliminar falha de preflight CORS no navegador (`No 'Access-Control-Allow-Origin' header`) sem quebrar o fluxo de tracking.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
- Resultado:
  - formatação aplicada com sucesso.

## 2026-04-30 - Migração backend-first (REST /api/v1) iniciada no núcleo de tracking

### Alterações Realizadas

- `BackendApiClient` endurecido para operação 100% REST canônica:
  - removido fallback implícito para `SupabaseConfig.url` em `resolveBaseUrl()`;
  - `BACKEND_API_URL` passa a ser obrigatório para tráfego de negócio via cliente REST.
- Padronização de headers no cliente REST:
  - mantido `authorization` com bearer token da sessão;
  - adicionado `apikey` (`SupabaseConfig.anonKey`) para compatibilidade com gateways Supabase.
- `ApiService.getServiceDetails(...)` migrado para backend-only:
  - removido fallback de leitura direta nas tabelas `agendamento_servico` / `service_requests_new`;
  - método agora exige backend configurado e usa somente `BackendTrackingApi.fetchServiceDetails(...)`.

### Arquivos Impactados

- `lib/core/network/backend_api_client.dart`
- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/network/backend_api_client.dart lib/services/api_service.dart`
  - `dart analyze lib/core/network/backend_api_client.dart lib/services/api_service.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - após o analyze, ocorreu aviso de telemetria do Dart em filesystem read-only (`dart-flutter-telemetry-session.json`), sem impacto no código validado.

## 2026-04-30 - Lote 2 (Home+Scheduling) avanço: disponibilidade via REST canônico

### Alterações Realizadas

- Continuidade da migração backend-first no domínio de agendamento/disponibilidade.
- `ApiService.getProviderAvailableSlots(...)`:
  - removida lógica de composição local com leituras diretas em `appointments` e `fixed_booking_slot_holds`;
  - método agora consome apenas `BackendSchedulingApi.fetchProviderAvailability(...)` (`/api/v1/providers/:id/availability`).
- `ApiService.getProvidersAvailableSlotsBatch(...)`:
  - removida a construção em lote baseada em múltiplas queries diretas (`provider_schedules`, `providers`, `appointments`, `fixed_booking_slot_holds`);
  - método passa a montar o resultado em lote chamando endpoint REST canônico de disponibilidade por `providerId|date`.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - após o analyze, ocorreu aviso de telemetria do Dart em filesystem read-only (`dart-flutter-telemetry-session.json`), sem impacto no código validado.

## 2026-04-30 - Lote 2 (Home+Scheduling) avanço: agenda do prestador 100% via REST

### Alterações Realizadas

- Migração de leitura/gravação de agenda do prestador para API canônica:
  - `getScheduleConfigResultForProvider(...)` agora usa `BackendSchedulingApi.fetchProviderSchedule(...)` (`/api/v1/providers/:id/schedule`).
  - removidos fallbacks legados diretos em `provider_schedules`/`providers.schedule_configs` nesse fluxo.
- Migração de persistência de agenda:
  - `saveScheduleConfig(...)` agora usa somente `BackendSchedulingApi.saveProviderSchedule(...)`.
- Migração de exceções da agenda:
  - `getScheduleExceptions()` agora usa `BackendSchedulingApi.fetchProviderScheduleExceptions(...)`.
  - `saveScheduleExceptions(...)` agora usa `BackendSchedulingApi.saveProviderScheduleExceptions(...)`.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - após o analyze, ocorreu aviso de telemetria do Dart em filesystem read-only (`dart-flutter-telemetry-session.json`), sem impacto no código validado.

## 2026-04-30 - Lote 2 (Home+Scheduling) avanço: limpeza de legado e warnings pós-migração

### Alterações Realizadas

- Após a migração de agenda para REST canônico, removidas estruturas locais legadas sem uso em `ApiService`:
  - `_scheduleExceptionsSelect`
  - `_normalizeLegacyScheduleConfigs(...)`
  - `_getProviderUidByUserId(...)`
  - `_buildProviderScheduleRowsFromConfigs(...)`
- Objetivo: reduzir dívida técnica e evitar reintrodução de fluxo direto em tabelas de agenda.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - após o analyze, ocorreu aviso de telemetria do Dart em filesystem read-only (`dart-flutter-telemetry-session.json`), sem impacto no código validado.

## 2026-04-30 - Lote 2 (Home+Scheduling) avanço: getProviderSchedules via REST

### Alterações Realizadas

- `ApiService.getProviderSchedules(...)` migrado para backend-first:
  - removida consulta direta em `provider_schedules`;
  - leitura agora usa `BackendSchedulingApi.fetchProviderSchedule(...)` por prestador;
  - retorno normalizado com `provider_id` preservado por item.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - após o analyze, ocorreu aviso de telemetria do Dart em filesystem read-only (`dart-flutter-telemetry-session.json`), sem impacto no código validado.

## 2026-04-30 - Lote 2 (Home+Scheduling) avanço: operações de appointments migradas para REST

### Alterações Realizadas

- Migração de operações de agenda direta (`appointments`) para endpoints canônicos de scheduling:
  - `markSlotBusy(...)` -> `BackendSchedulingApi.markProviderSlotBusy(...)`.
  - `bookSlot(...)` -> `BackendSchedulingApi.bookProviderSlot(...)`.
  - `createManualAppointment(...)` -> `BackendSchedulingApi.createManualAppointment(...)`.
  - `deleteAppointment(...)` -> `BackendSchedulingApi.deleteAppointment(...)`.
- Removidos inserts/deletes diretos em `appointments` nesses métodos.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - após o analyze, ocorreu aviso de telemetria do Dart em filesystem read-only (`dart-flutter-telemetry-session.json`), sem impacto no código validado.

## 2026-04-30 - Lote 2 (Home+Scheduling) avanço: status/execução sem fallback direto em tabelas

### Alterações Realizadas

- `updateServiceStatus(...)` endurecido para backend-only:
  - mantém chamada canônica `BackendTrackingApi.updateServiceStatus(...)`;
  - removidos fallbacks de update direto em `agendamento_servico` e `service_requests_new`.
- `startService(...)` simplificado para fluxo canônico móvel:
  - removido update direto prévio em `agendamento_servico`;
  - mantém execução via RPC canônica `provider_start_mobile_service`.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - após o analyze, ocorreu aviso de telemetria do Dart em filesystem read-only (`dart-flutter-telemetry-session.json`), sem impacto no código validado.

## 2026-04-30 - Lote 2 (Home+Scheduling) avanço: cancelamento/remarcação backend-only

### Alterações Realizadas

- `cancelService(...)` migrado para backend-only:
  - mantida chamada canônica `BackendTrackingApi.cancelService(...)`;
  - removido fallback local que fazia updates diretos em `agendamento_servico` e `service_requests_new`.
- `proposeSchedule(...)` migrado para backend-only:
  - mantida chamada canônica `BackendTrackingApi.proposeSchedule(...)`;
  - removidos fallbacks locais de remarcação em `agendamento_servico`/`appointments` e fluxo paralelo de negociação local.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - após o analyze, ocorreu aviso de telemetria do Dart em filesystem read-only (`dart-flutter-telemetry-session.json`), sem impacto no código validado.

## 2026-04-30 - Lote 2 (Home+Scheduling) avanço: confirmSchedule backend-only

### Alterações Realizadas

- `confirmSchedule(...)` migrado para backend-only:
  - mantida chamada canônica `BackendTrackingApi.confirmSchedule(...)`;
  - removido fallback local completo que atualizava `agendamento_servico` e sincronizava `appointments` no cliente.
- Efeito: confirmação de agenda passa a depender exclusivamente da orquestração backend `/api/v1/tracking/services/:id/confirm-schedule`.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - após o analyze, ocorreu aviso de telemetria do Dart em filesystem read-only (`dart-flutter-telemetry-session.json`), sem impacto no código validado.

## 2026-04-30 - Lote 2 (Home+Scheduling) avanço: limpeza de legados órfãos pós backend-only

### Alterações Realizadas

- Removidos métodos privados sem uso que sustentavam fallback local de agendamento/negociação já migrado para backend-only:
  - `_loadFixedBookingForScheduling(...)`
  - `_resolveFixedBookingDurationMinutes(...)`
  - `_ensureFixedBookingSlotAvailable(...)`
  - `_findExistingFixedBookingAppointment(...)`
  - `_insertNotificationSafely(...)`
  - `_resolveNegotiationRole(...)`
  - `_isActiveSlotHold(...)`
  - `_tryParseDateTime(...)`
  - `_attachIntentSnapshotToSlotHolds(...)`
- Resultado prático: reduzida dependência de lógica local acoplada a tabelas de domínio, mantendo o fluxo alinhado ao padrão REST `/api/v1`.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - após o analyze, ocorreu aviso de telemetria do Dart em filesystem read-only (`dart-flutter-telemetry-session.json`), sem impacto no código validado.

## 2026-04-30 - Lote 2 (Home+Scheduling) avanço: criação de appointment via API canônica

### Alterações Realizadas

- No fluxo de `createService(...)` (ramo móvel com `scheduledAt`), removida inserção direta em `appointments` via Supabase SDK.
- Substituído por chamada backend-only:
  - `BackendSchedulingApi.bookProviderSlot(...)`
  - endpoint canônico `/api/v1/providers/:id/slots/book`
- Mantido tratamento explícito de falha com `ApiException` quando a reserva do slot via API não retorna sucesso.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - após o analyze, ocorreu aviso de telemetria do Dart em filesystem read-only (`dart-flutter-telemetry-session.json`), sem impacto no código validado.

## 2026-04-30 - Lote 2 (Home+Scheduling) avanço: confirmFinalService backend-only

### Alterações Realizadas

- `confirmFinalService(...)` migrado para backend-only estrito.
- Mantida apenas a chamada canônica:
  - `BackendTrackingApi.confirmFinalService(...)`
  - endpoint `/api/v1/tracking/services/:id/confirm-final`
- Removidos fallbacks locais com acesso direto a tabelas de domínio:
  - leitura em `agendamento_servico`
  - leitura em `service_requests_new`
  - confirmação local por RPC/fallback de status
  - inserções locais de `reviews` nesse método
- Em falha da rota canônica, agora retorna `ApiException` 502 sem bypass local.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - após o analyze, ocorreu aviso de telemetria do Dart em filesystem read-only (`dart-flutter-telemetry-session.json`), sem impacto no código validado.

## 2026-04-30 - Lote 2 (Home+Scheduling) avanço: verifyServiceCode e submitReview sem leitura direta em service_requests_new

### Alterações Realizadas

- `verifyServiceCode(...)`:
  - removida leitura direta em `service_requests_new` (`completion_code`, `verification_code`);
  - passa a usar `BackendTrackingApi.fetchServiceDetails(...)` via `/api/v1/tracking/services/:id` para validar código no fluxo móvel.
- `submitReview(...)`:
  - removida leitura direta em `service_requests_new` para resolver `provider_id/client_id`;
  - passa a usar `BackendTrackingApi.fetchServiceDetails(...)` e mantém apenas o `upsert` da review.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - após o analyze, ocorreu aviso de telemetria do Dart em filesystem read-only (`dart-flutter-telemetry-session.json`), sem impacto no código validado.

## 2026-04-30 - Lote 2 (Home+Scheduling) avanço: getServices backend-first + logServiceEvent sem pre-check em service_requests_new

### Alterações Realizadas

- `getServices(...)` atualizado para backend-first no fluxo cliente:
  - cliente: usa `BackendHomeApi.fetchClientHome()` (snapshot canônico `/api/v1/home/client`) como fonte de serviços.
  - prestador: mantém fallback atual em `service_requests_new` até expor lista equivalente no `/api/v1/home/provider`.
- `logServiceEvent(...)`:
  - removido pre-check de existência em `service_requests_new` (consulta extra direta);
  - agora tenta inserir em `service_logs` diretamente e trata violação de FK (`23503`) como best-effort sem bloquear fluxo.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - após o analyze, ocorreu aviso de telemetria do Dart em filesystem read-only (`dart-flutter-telemetry-session.json`), sem impacto no código validado.

## 2026-04-30 - Lote 3 (Scheduling) avanço: getAvailableForSchedule backend-first com fallback

### Alterações Realizadas

- `getAvailableForSchedule(...)` migrado para estratégia backend-first:
  - tentativa primária via `BackendApiClient.getJson('/api/v1/providers/schedule/available')`;
  - leitura resiliente de payload em `data.services` ou `services`;
  - normalização mantendo `_mapServiceData(...)` para compatibilidade de UI.
- Fallback legado preservado:
  - se backend indisponível/sem dados, mantém consulta Supabase atual em `service_requests_new` com filtros por status aberto e `provider_id` nulo.
- Pipeline existente mantido sem regressão:
  - `_filterRejectedDispatchOffers(...)`
  - `_filterActiveDispatchOffers(...)`

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `flutter analyze lib/services/api_service.dart`
- Resultado:
  - `No issues found!`

## 2026-04-30 - Lote 4 (Cancelamento) correção: evitar falso sucesso no botão "CANCELAR (SEM CUSTO)"

### Problema

- Usuário clicava em cancelar, a tela navegava para Home, mas ao retornar o serviço continuava ativo.
- Causa provável: sucesso otimista no cliente sem confirmação efetiva de status cancelado no backend.

### Alterações Realizadas

- `lib/core/tracking/backend_tracking_api.dart`
  - `cancelService(...)` passou a validar o payload de resposta:
    - aceita `success` em raiz (`decoded['success']`);
    - aceita `data.success` (`decoded['data']['success']`);
    - só faz fallback para `true` quando não há flag explícita (compatibilidade).

- `lib/services/api_service.dart`
  - `cancelService(...)` reforçado com confirmação pós-cancelamento:
    - normaliza e valida `serviceId`;
    - executa cancelamento backend;
    - consulta `fetchServiceDetails(...)` e exige status final `cancelled/canceled`;
    - se status ainda não cancelado, lança erro amigável (`409`) e evita navegação com falso sucesso.

### Impacto

- O fluxo de UI não deve mais "voltar" para tracking após cancelar por falso positivo.
- Em caso de inconsistência temporária do backend, usuário recebe erro e permanece na tela para nova tentativa.

### Validação

- Executado:
  - `dart format lib/core/tracking/backend_tracking_api.dart lib/services/api_service.dart`
  - `flutter analyze lib/core/tracking/backend_tracking_api.dart lib/services/api_service.dart`
- Resultado:
  - `No issues found!`

## 2026-05-01 - Guarda de regressão: bloquear acesso direto ao Supabase em mudanças novas

### Alterações Realizadas

- Implementado checker automatizado `tool/check_no_direct_supabase.sh` para reforçar a regra "sempre via API REST".
- Modos suportados:
  - `--changed` (padrão): verifica apenas arquivos Dart alterados no `git diff` (ideal para CI incremental sem travar legado existente).
  - `--all`: varredura completa de `lib/**/*.dart` para mapear dívida técnica remanescente.
- O checker falha (`exit 1`) ao detectar padrões de acesso direto (`.from(...)`, `.rpc(...)`, `storage.from(...)`, `Supabase.instance.client.from/rpc`).

### Arquivos Impactados

- `tool/check_no_direct_supabase.sh`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `./tool/check_no_direct_supabase.sh --changed`
  - `./tool/check_no_direct_supabase.sh --all`
- Resultado:
  - `--changed`: `OK` (nenhuma regressão nova nos arquivos alterados)
  - `--all`: falhou com lista extensa de pontos legados (mapeamento completo gerado no terminal), confirmando que ainda existe dívida técnica histórica fora do escopo desta correção pontual.


## 2026-05-01 - Gate de CI preparado para bloquear regressão de acesso direto ao Supabase

### Alterações Realizadas

- Como o repositório não possui pipeline versionada (`.github/workflows` ausente), foi preparado um gate plugável para CI:
  - criado `tool/ci_quality_gate.sh`.
- O gate executa, em ordem:
  - `./tool/check_no_direct_supabase.sh --changed`
  - `flutter analyze`
- README atualizado com instruções de execução local e comando único para integração no provedor de CI.

### Arquivos Impactados

- `tool/ci_quality_gate.sh`
- `README.md`
- `RELATORIO_DEV.md`

### Validação

- Estrutura validada localmente (scripts criados e executáveis).
- Observação:
  - não foi possível validar em pipeline real porque não há workflow CI versionado neste repositório no momento.


## 2026-05-01 - Correção extra da busca: fallback de hints quando semântica/catalogo não retornam itens

### Alterações Realizadas

- Ajustado `HomeSearchScreen` para evitar lista vazia quando:
  - `tasks-semantic-search` retorna erro/`results: []`;
  - e o catálogo local não produz correspondência suficiente.
- Novo fallback final no fluxo `_fetchRemoteAutocompleteHints(...)`:
  - chamada de `ApiService.fetchServiceAutocompleteHints(query, limit: 8)`;
  - conversão dos nomes retornados em sugestões válidas para o `HomeSearchBar`.
- Efeito prático:
  - a busca deixa de depender exclusivamente da Edge semântica + catálogo para exibir sugestões;
  - reduz cenários de "Nenhum resultado" falso negativo.

### Arquivos Impactados

- `lib/features/home/home_search_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/home/home_search_screen.dart`
  - `dart analyze lib/features/home/home_search_screen.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - aviso conhecido de telemetria do Dart em filesystem read-only após analyze; não é erro do código.


## 2026-05-01 - Remoção de API externa no autocomplete (somente API do app)

### Alterações Realizadas

- Removido uso da URL externa `https://apotiguar-api.vercel.app/autocomplete` no fluxo de autocomplete.
- Em `ApiService.fetchServiceAutocompleteHints(...)`:
  - substituído HTTP externo por endpoint canônico do app: `GET /api/v1/tasks/autocomplete?q=...&limit=...` via `BackendApiClient`.
  - adicionado fallback local com `fetchActiveTaskCatalog()` + `TaskAutocomplete.suggestTasks(...)` quando o endpoint não retorna itens ou falha.
- Efeito prático:
  - busca/autocomplete agora usa exclusivamente APIs e dados do próprio app;
  - eliminado acoplamento com API de outro projeto.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart lib/features/home/home_search_screen.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - aviso conhecido de telemetria do Dart em filesystem read-only após analyze; não é erro do código.


## 2026-05-01 - Mitigação definitiva no app: desativada busca semântica remota instável

### Alterações Realizadas

- Identificado que a function remota `tasks-semantic-search` não está versionada neste workspace (não foi possível patch direto nela localmente).
- Para eliminar impacto em produção/app:
  - desativada dependência da Edge semântica em `TaskSemanticSearchService` via flag interna `_useEdgeSemanticSearch = false`.
  - fluxo passa a usar busca local (`TaskAutocomplete`) e demais fallbacks REST do próprio app já implementados.
- Efeito prático:
  - app deixa de depender do endpoint remoto que retorna `Cannot access 'name' before initialization`;
  - evita "Nenhum resultado" causado por falha da function externa/remota.

### Arquivos Impactados

- `lib/services/task_semantic_search_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/task_semantic_search_service.dart`
  - `dart analyze lib/services/task_semantic_search_service.dart lib/features/home/home_search_screen.dart lib/services/api_service.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - aviso conhecido de telemetria do Dart em filesystem read-only após analyze; não é erro do código.


## 2026-05-01 - Correção da busca por descrição de serviço no catálogo da Home

### Alterações Realizadas

- Ajustado matcher da tela `Buscar serviços` para considerar também `description` além de `task_name/name`.
- No fallback de composição das sugestões, quando `task_name/name` estiver vazio, a UI passa a usar `description` como rótulo da sugestão.
- Efeito prático:
  - consultas como "copia chave simples" passam a casar com itens retornados que tenham apenas descrição preenchida (como observado no payload de `service_requests_new`).

### Arquivos Impactados

- `lib/features/home/home_search_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/home/home_search_screen.dart`
  - `dart analyze lib/features/home/home_search_screen.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - aviso conhecido de telemetria do Dart em filesystem read-only após analyze; não é erro do código.


## 2026-05-01 - Correção de renderização do autocomplete na Home (fallback visual direto na tela)

### Alterações Realizadas

- Implementado fallback visual direto em `HomeSearchScreen` para exibir sugestões usando `_remoteAutocompleteHints` em lista própria abaixo da barra de busca.
- Com isso, mesmo que o dropdown interno do `HomeSearchBar` não renderize em algum estado, as sugestões continuam aparecendo na tela principal.
- Itens da lista acionam `_handleSuggestionSelected(...)` normalmente.

### Arquivos Impactados

- `lib/features/home/home_search_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/home/home_search_screen.dart`
  - `dart analyze lib/features/home/home_search_screen.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - aviso conhecido de telemetria do Dart em filesystem read-only após analyze; não é erro do código.


## 2026-05-01 - Correção estrutural do autocomplete Home (API -> estado -> render)

### Alterações Realizadas

- Refatorado `_fetchRemoteAutocompleteHints(...)` para pipeline determinístico com precedência fixa:
  1) `instantLocal` (catálogo local por `description/task/profession`)
  2) `semantic`
  3) `catalogScored` (`TaskAutocomplete.suggestTasks`)
  4) `fromServices` (snapshot de `home/client.services`)
  5) `tasks/autocomplete` do backend
  6) sugestão digitada.
- Corrigido fluxo de cache para evitar falso vazio:
  - leitura de cache agora ignora entrada vazia;
  - gravação de cache não salva listas vazias;
  - resultado local válido tem prioridade e já encerra o fluxo.
- Criada normalização única de sugestão (`task_name`, `profession_name`, `unit_price`) para todas as fontes.
- Instrumentação debug/dev adicionada com `traceId` por query e logs de tamanho/origem da lista final.
- Log de render no `build` adicionado com branch ativa (`loading`, `quick-access`, `suggestions`, `no-results`, `idle-search`).

### Arquivos Impactados

- `lib/features/home/home_search_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/home/home_search_screen.dart`
  - `dart analyze lib/features/home/home_search_screen.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - aviso conhecido de telemetria do Dart em filesystem read-only após analyze; não é erro do código.


## 2026-05-01 - Ajuste de roteamento da busca no /home (campo inline agora reage à digitação)

### Alterações Realizadas

- Identificada causa de "nada acontece ao digitar": no `/home`, o `HomeSearchBar` estava encapsulado por `AbsorbPointer`, com `onQueryChanged`/`onQuerySubmitted` nulos.
- Corrigido em `HomeScreen`:
  - removido `AbsorbPointer` do `home-inline-search-bar`;
  - ligado `onQueryChanged` e `onQuerySubmitted` para abrir `/home-search` com query ao digitar (>=2 chars);
  - adicionado guard `_openingHomeSearch` para evitar múltiplos pushes em sequência.
- Efeito prático:
  - no `/home`, ao digitar `cop`/`copia`, a navegação para a busca dedicada acontece automaticamente, destravando o fluxo de preload + lista.

### Arquivos Impactados

- `lib/features/home/home_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/features/home/home_screen.dart lib/features/home/widgets/home_search_bar.dart lib/features/home/home_search_screen.dart`
  - `dart format lib/features/home/home_screen.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - aviso conhecido de telemetria do Dart em filesystem read-only após analyze; não é erro do código.


## 2026-05-01 - Fallback de catálogo por serviços para autocomplete da HomeSearch

### Alterações Realizadas

- Adicionado fallback adicional de catálogo em `HomeSearchScreen` para quando `home/client.services` e `tasks` não retornarem itens:
  - `GET /api/v1/services?order=desc&limit=500`.
- Mapeamento desse fallback para shape do autocomplete:
  - `task_name <- task_name/name/description`
  - `profession_name <- profession_name/profession`
  - `unit_price <- unit_price/price/price_estimated`
- Efeito prático:
  - entradas oriundas de `service_requests_new` (como "Cópia de Chave Simples") passam a alimentar o catálogo de busca mesmo sem snapshot canônico da home.

### Arquivos Impactados

- `lib/features/home/home_search_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/features/home/home_search_screen.dart`
  - `dart format lib/features/home/home_search_screen.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - aviso conhecido de telemetria do Dart em filesystem read-only após analyze; não é erro do código.


## 2026-05-01 - Conexão do app para Supabase local (web + Android emulator)

### Alterações Realizadas

- Ajustado `assets/env/app.env` para ambiente local (antes estava remoto):
  - `SUPABASE_URL=http://127.0.0.1:64321`
  - `SUPABASE_ANON_KEY=<anon local>`
  - `BACKEND_API_URL=http://127.0.0.1:64321/functions/v1`
- Alinhado `.env` com `BACKEND_API_URL` local para manter consistência de execução local.
- Melhorado fallback do `BackendApiClient`:
  - quando `BACKEND_API_URL` não vier via `--dart-define`, ele passa a usar automaticamente `SUPABASE_URL/functions/v1`.
- Adicionada compatibilidade de URL para Android Emulator em `SupabaseConfig.initialize()`:
  - se rodar em Android e a URL tiver `127.0.0.1`/`localhost`, faz rewrite para `10.0.2.2`.
  - evita falha de conexão no emulador mantendo funcionamento no web.

### Arquivos Impactados

- `assets/env/app.env`
- `.env`
- `lib/core/network/backend_api_client.dart`
- `lib/core/config/supabase_config.dart`
- `RELATORIO_DEV.md`

### Resultado Esperado

- Web: app usa Supabase local diretamente.
- Android Emulator: app usa Supabase local via `10.0.2.2` sem trocar arquivo manualmente.
- APIs REST internas (`/functions/v1/api/v1/...`) passam a ter base local mesmo sem `BACKEND_API_URL` em compile-time.

### Ajuste complementar (Android Emulator)

- Identificado em runtime que `auth/bootstrap` ainda batia em `127.0.0.1` no emulador.
- Corrigido `BackendApiClient.resolveBaseUrl()` para aplicar rewrite automático `127.0.0.1/localhost -> 10.0.2.2` quando `TargetPlatform.android` e `!kIsWeb`.
- Com isso, tanto Supabase client quanto chamadas REST do backend usam host alcançável dentro do Android Emulator.

## 2026-05-01 - Correção de erro no cadastro local (checkUnique/register via REST)

### Problema

- No Android local, ao concluir cadastro, aparecia:
  - `PGRST205 Could not find table public.providers`
  - `PGRST205 Could not find table public.users`
- Causa: fluxo de cadastro ainda fazia consultas diretas legacy (`from('users')` / `from('providers')`) em schema que não existe no Supabase local atual.

### Alterações Realizadas

- Refatorado `ApiService.checkUnique(...)` para usar somente endpoint REST:
  - `POST /api/v1/auth/check-unique`
  - removido acesso direto a `users/providers` nesse método.
- Refatorado `ApiService.register(...)` para usar somente endpoint REST:
  - `POST /api/v1/auth/register`
  - hidratação pós-registro via `GET /api/v1/me` (fallback `GET /api/v1/users?supabase_uid_eq=...`).
- Persistência local (`user_id`, `role`, `is_medical`, `is_fixed_location`) mantida após resposta REST.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `flutter analyze lib/services/api_service.dart lib/features/auth/register_screen.dart lib/features/auth/steps/basic_info_step.dart lib/features/auth/steps/identification_step.dart`
- Resultado:
  - `No issues found!`

## 2026-05-01 - Sincronização remota -> local (schema + dados + auth)

### Objetivo

- Trazer os dados atualizados do ambiente remoto para o Supabase local.

### Execução realizada

1. Projeto remoto linkado com sucesso:
   - `supabase link --project-ref mroesvsmylnaxelrhqtl --yes`

2. Dump remoto gerado:
   - `supabase db dump --linked --schema public --file supabase/sync/remote_public_schema.sql --yes`
   - `supabase db dump --linked --data-only --schema public --file supabase/sync/remote_public_data.sql --yes`
   - `supabase db dump --linked --data-only --schema auth --file supabase/sync/remote_auth_data.sql --yes`

3. Restore no banco local (`127.0.0.1:64322/postgres`):
   - Recriação de `public` e extensões necessárias (`vector`, `postgis`, `btree_gist`) para compatibilidade do schema remoto.
   - Aplicação de schema remoto (`remote_public_schema.sql`).
   - Import de dados de `auth` (`remote_auth_data.sql`).
   - Truncate de tabelas `public` (exceto metadados do PostGIS) e import de dados `public` (`remote_public_data.sql`).

### Validação final

- Contagens no local após sync:
  - `auth.users = 298`
  - `public.users = 226`
  - `public.providers = 196`
  - `public.service_requests_new = 12`
  - `public.task_catalog = 569`

- Validação de usuário solicitado:
  - `passageiro2@gmail.com` encontrado em `auth.users` com id `e2db0879-b924-4775-8f4d-463410162d4c`.

### Observações

- O comando `supabase db pull` falhou por conflitos no histórico legado de migrations; para objetivo de sincronização de base foi usado fluxo robusto de dump/restore direto.
- Arquivos de sync gerados em `/home/servirce/Documentos/101/projeto-central-/supabase/sync/`.

## 2026-05-01 - Hardening de migrations legadas para destravar `supabase db pull`

### Contexto

- O comando `supabase db pull remote_schema_sync --yes` falhava em diferentes pontos da cadeia histórica de migrations.
- Foram aplicadas correções pontuais de compatibilidade/idempotência nas migrations legadas do repositório raiz (`../supabase/migrations`).

### Correções aplicadas

1. `20260326200000_seed_br_service_catalog_real_prices.sql`
- Adicionado bloco defensivo para garantir a constraint única usada no `ON CONFLICT`:
  - `task_catalog_profession_name_key UNIQUE (profession_id, name)`

2. `20260328090000_fix_trip_cancellation_fees_cancelled_trip_fk.sql`
- Adicionada guarda para ambientes sem tabela:
  - se `public.trip_cancellation_fees` ou `public.trips` não existir, a migration é ignorada com `NOTICE`.

3. `20260406000000_fix_rpc_critical_issues.sql`
- Evitado erro `42P13 cannot change return type of existing function`:
  - `DROP FUNCTION IF EXISTS public.rpc_confirm_completion(TEXT, TEXT, TEXT);`
  - `DROP FUNCTION IF EXISTS public.rpc_request_completion(TEXT);`
  - antes dos `CREATE OR REPLACE`.

4. `20260411193000_uuid_first_fixed_provider_unification.sql`
- Removido caractere inválido (`x`) que causava erro de sintaxe `42601`.

5. `20260501023457_mobile_frontend_schema_contract_no_fallback.sql`
- Criação de índices tornada condicional com `to_regclass(...)` para não falhar quando tabelas opcionais não existem.

### Resultado

- `supabase db pull remote_schema_sync --yes` concluiu com sucesso.
- Migration gerada automaticamente:
  - `supabase/migrations/20260501233226_remote_schema_sync.sql`
- Histórico remoto reparado/aplicado pelo próprio CLI ao final do pull.

### Arquivos impactados

- `/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260326200000_seed_br_service_catalog_real_prices.sql`
- `/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260328090000_fix_trip_cancellation_fees_cancelled_trip_fk.sql`
- `/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260406000000_fix_rpc_critical_issues.sql`
- `/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260411193000_uuid_first_fixed_provider_unification.sql`
- `/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260501023457_mobile_frontend_schema_contract_no_fallback.sql`
- `/home/servirce/Documentos/101/projeto-central-/supabase/migrations/20260501233226_remote_schema_sync.sql`
- `/home/servirce/Documentos/101/projeto-central-/mobile_app/RELATORIO_DEV.md`

### Ajuste final de alinhamento (histórico de migrations)

- Tentativa de `supabase db push --local --yes` encontrou conflito de objetos já existentes (`edge_logs_id_seq`) por conta do restore completo prévio.
- Para manter o histórico limpo e alinhado com o remoto:
  - removida migration de diff local gerada pelo pull (`20260501233226_remote_schema_sync.sql`);
  - validado `supabase migration list --local`: local e remote voltaram a ficar sincronizados até `20260501023457`.


## 2026-05-01 - Fase 1 do plano 100% REST no app (gate + desacoplamento inicial)

### Objetivo desta rodada

- Iniciar execução do plano final com entregas concretas de código:
  1. Criar gate anti-regressão para bloquear acesso direto ao Supabase no cliente Flutter.
  2. Remover acoplamento direto de sessão Supabase no serviço de presença.
  3. Remover leitura de token via `supabase_flutter` no `BackendApiClient`.

### Mudanças aplicadas

1. Gate anti-regressão criado
- Novo script: `scripts/check_no_direct_supabase.sh`
- O script agora detecta apenas padrões reais de acesso Supabase (evitando falsos positivos de `Map.from/List.from`), incluindo:
  - `Supabase.instance.client.from/rpc/channel/functions.invoke`
  - `supabase|_supa|client.from/rpc/channel/functions.invoke`
  - `storage.from(...)`
- Resultado atual do gate: **falha** (esperado nesta fase), listando os arquivos ainda pendentes de migração.

2. `ProviderPresenceService` desacoplado de sessão Supabase
- Arquivo: `lib/services/provider_presence/provider_presence_service.dart`
- Removidos:
  - import `supabase_flutter`
  - import `supabase_config`
  - persistência de `currentSession` em `SharedPreferences`
  - tentativa de `recoverSession` no background
- `ensureSupabaseReady()` mantido por compatibilidade de assinatura, mas agora apenas garante estado de rede local (`NetworkStatusService`), sem tocar em auth Supabase no cliente.

3. `BackendApiClient` sem token vindo de `supabase_flutter`
- Arquivo: `lib/core/network/backend_api_client.dart`
- Removido import `supabase_flutter`.
- `buildHeaders()` agora usa somente `ApiService().currentToken` para `Authorization`.
- Mantida compatibilidade de `apikey` (vinda de `SupabaseConfig.anonKey`) até remoção total do runtime legado.

### Validação

- `dart analyze lib/core/network/backend_api_client.dart lib/services/provider_presence/provider_presence_service.dart`
  - Resultado: **No issues found**.
- `./scripts/check_no_direct_supabase.sh`
  - Resultado: **falha intencional nesta fase**, com inventário dos pontos restantes para migração total.

### Próximos alvos obrigatórios (próxima fase)

1. `lib/services/realtime_service.dart`
- Remover `channel(...)` e migrar para relay backend (`/api/v1/realtime/...`).

2. `lib/services/data_gateway.dart`
- Substituir `.from(...)`/`.functions.invoke(...)` por chamadas REST via APIs de domínio.

3. `lib/services/api_service.dart`
- Eliminar blocos residuais diretos de `from/rpc/functions.invoke/storage`.


## 2026-05-01 - Execução em lote (continuação do plano 100% REST)

### Entregas aplicadas nesta rodada

1. Realtime sem canal Supabase no cliente
- Arquivo: `lib/services/realtime_service.dart`
- Removido `supabase_flutter` e toda assinatura de `channel()/broadcast/realtime.disconnect/removeChannel` no cliente.
- Mantida API pública da classe para compatibilidade.
- Fluxo agora opera em modo relay/eventos externos, com reconexão lógica preservada sem socket Supabase direto.

2. Analytics sem `functions.invoke` direto
- Arquivo: `lib/services/analytics_service.dart`
- Trocado `Supabase.instance.client.functions.invoke('analytics', ...)` por `ApiService().invokeEdgeFunction('analytics', {'events': batch})`.

3. Ajustes REST adicionais no `ApiService`
- Arquivo: `lib/services/api_service.dart`
- `unregisterDeviceToken`: migração para `_backendApiClient.putJson(...)`.
- `uploadContestEvidence`: persistência via endpoint REST (`/api/v1/service-disputes/evidence`).
- `fetchProfessionsByServiceType`: leitura via REST (`/api/v1/professions?...`).
- `deleteAccount`: remoção via REST (`DELETE /api/v1/users/{id}`).
- `calculateUberFare`: usa `invokeEdgeFunction('geo/calculate-fare', ...)` wrapper interno.
- `disconnectPassengerMercadoPago`: fallback de remoção migrou para endpoint REST.
- `callEdgeFunction`: agora delega para `invokeEdgeFunction(...)` (sem `client.functions.invoke` direto).

4. DataGateway
- Arquivo: `lib/services/data_gateway.dart`
- `markChatMessageRead` migrou de `Supabase.instance.client.functions.invoke` para `_api.invokeEdgeFunction(...)`.

5. Limpeza auxiliar
- Arquivo: `lib/core/constants/table_names.dart`
- Removido exemplo de comentário que induzia `supabase.from(...)`.

### Validação

- `dart analyze` (arquivos alterados principais): **No issues found**.
- Gate anti-regressão `./scripts/check_no_direct_supabase.sh`:
  - estado atual: ainda falha, porém agora concentrado em um bloco residual do `api_service.dart` (queries `.from` e `.rpc`).

### Pendências restantes (mapeadas pelo gate)

- Restam ocorrências diretas principalmente em:
  - `lib/services/api_service.dart` (inserts/updates em tabelas e RPCs legados).
- Próximo passo técnico: substituir cada bloco residual por endpoints `/api/v1/...` equivalentes e remover chamadas `rpc` via cliente Supabase do app.


## 2026-05-01 - Fechamento do bloco residual no ApiService (from/rpc -> REST)

### Objetivo

- Migrar as últimas ocorrências sinalizadas de `from/rpc` em `lib/services/api_service.dart` para endpoints REST/wrappers.
- Rodar `gate` e `analyze` para validar o fechamento técnico da fase.

### Principais substituições aplicadas em `ApiService`

1. Persistências diretas de tabelas -> REST
- `fixed_booking_slot_holds.insert` -> `POST /api/v1/bookings/slot-holds`
- `client_locations.upsert` -> `PUT /api/v1/client-locations/{serviceId}`
- `task_catalog.insert` -> `POST /api/v1/task-catalog`
- `provider_tasks.upsert` -> `PUT /api/v1/providers/{providerId}/tasks/{taskId}`
- `service_logs.insert` -> `POST /api/v1/services/{serviceId}/logs`
- `users.update/upsert` (sync de auth) -> `PUT /api/v1/users/{id}` e `POST /api/v1/auth/sync`
- `providers.update` -> `PUT /api/v1/providers/{id}/profile`
- `provider_professions.upsert` -> `POST /api/v1/providers/{id}/specialties`
- fallback de atualização dinâmica por tabela/id -> `PUT /api/v1/tables/{table}/{id}`

2. RPCs diretas -> REST/edge wrapper
- `provider_accept_service_offer` -> `POST /api/v1/dispatch/{serviceId}/accept`
- `provider_reject_service_offer` -> `POST /api/v1/dispatch/{serviceId}/reject`
- `provider_start_mobile_service` -> `POST /api/v1/services/{serviceId}/start`
- `provider_complete_mobile_service` -> `POST /api/v1/services/{serviceId}/complete`
- `rpc_confirm_completion` -> `POST /api/v1/services/{serviceId}/confirm-completion`
- `rpc_auto_confirm_service_after_grace` -> `POST /api/v1/services/{serviceId}/auto-confirm-after-grace`
- `ensure_mobile_completion_code` -> `POST /api/v1/services/{serviceId}/ensure-completion-code`
- `provider_mark_mobile_service_arrived` -> `POST /api/v1/services/{serviceId}/arrive`

3. Disputas/reviews via REST
- `reviews.upsert` -> `POST /api/v1/reviews`
- `service_disputes.insert` -> `POST /api/v1/service-disputes`

4. Limpezas de código
- Removido helper `_asRpcPayload` (ficou sem uso após migração).
- Removidos itens não utilizados (_import e constante de fallback de projeção de profissões).

### Validação

- `dart analyze lib/services/api_service.dart` -> **No issues found**.
- `./scripts/check_no_direct_supabase.sh` -> **✅ Apenas ocorrências em whitelist temporária (integrations/supabase)**.

### Observação de governança

- No estado atual, o gate já não reporta acessos diretos em `api_service.dart` no padrão monitorado.
- Restam apenas ocorrências na whitelist temporária de integração (`lib/integrations/supabase/...`), previstas para remoção por fase de desativação final.


## 2026-05-01 - Próxima etapa concluída (remoção de whitelist e zero uso direto no lib)

### Objetivo

- Eliminar a dependência da whitelist temporária no gate.
- Migrar adaptadores restantes em `lib/integrations/supabase/*` que ainda usavam SDK Supabase direto.
- Validar estado final com `gate` + `analyze`.

### Mudanças aplicadas

1. `lib/integrations/supabase/auth/supabase_auth_repository.dart`
- Removido uso de `supabaseClient.auth.signInWithPassword`.
- Login migrado para REST:
  - `POST /api/v1/auth/login` via `BackendApiClient`.
- Token persistido com `ApiService().saveToken(...)`.
- `getCurrentUserId()` agora usa `ApiService().currentUserId`.

2. `lib/integrations/supabase/storage/supabase_storage_repository.dart`
- Removido upload direto `storage.from(...).upload(...)`.
- Upload migrado para REST:
  - `POST /api/v1/media/upload` via `BackendApiClient`.
- Retorno de URL lido de `url/public_url` da resposta.

3. `lib/integrations/supabase/remote_ui/supabase_remote_screen_repository.dart`
- Removido `functions.invoke('get_screen')` direto.
- Migração para endpoint REST:
  - `POST /api/v1/remote-ui/get-screen`.

4. `lib/integrations/supabase/remote_ui/supabase_remote_action_api.dart`
- Removido `functions.invoke('post_action')` direto.
- Migração para endpoint REST:
  - `POST /api/v1/remote-ui/post-action`.

5. `scripts/check_no_direct_supabase.sh`
- Removida whitelist temporária de `lib/integrations/supabase`.
- Gate agora é estrito para todo `lib/`.

### Validação

- `dart analyze` nos arquivos alterados: **No issues found**.
- `./scripts/check_no_direct_supabase.sh`: **✅ Sem uso direto proibido de Supabase em lib**.

### Resultado da fase

- O cliente Flutter ficou com bloqueio efetivo de regressão para acesso direto proibido ao Supabase em `lib/`.
- Próximo passo natural: rodar smoke/E2E dos fluxos críticos para validar os novos endpoints REST de auth/remote-ui/media em ambiente local/staging.


## 2026-05-01 - Etapa contínua (novo lote de migração REST e gate estrito)

### Mudanças aplicadas neste lote

1. `lib/services/app_config_service.dart`
- Removido acesso direto `from('app_configs')`.
- Migração para `BackendApiClient`:
  - `GET /api/v1/app-configs`.

2. `lib/services/media_service.dart`
- Removido acesso direto `from('users')` para ler avatar de terceiro.
- Migração para `BackendApiClient`:
  - `GET /api/v1/users/{id}`.

3. `lib/services/id_resolver.dart`
- Removido lookup direto `from('users')`.
- Migração para `BackendApiClient`:
  - `GET /api/v1/users?supabase_uid_eq=...&limit=1`.

4. `lib/services/support/api_active_service_resolver.dart`
- Removidos acessos diretos a `users`, `agendamento_servico`, `service_requests_new`.
- Resolver agora consulta backend via `BackendApiClient`:
  - `GET /api/v1/users?...`
  - `GET /api/v1/bookings/fixed?...`
  - `GET /api/v1/services/active?...`

5. `lib/features/client/widgets/dispatch_tracking_timeline.dart`
- Removido canal realtime direto `.channel('service_logs:...')` no cliente.
- Substituído por polling curto (`Timer.periodic`) para recarregar logs.

6. `lib/features/auth/login_screen.dart`
- Removido `from('users')` no check pós-login de CPF.
- Leitura migrada para `_api.getUserData()`.

7. `lib/features/auth/cpf_completion_screen.dart`
- Removido update direto em `users` (`from(...).update(...)`).
- Persistência migrada para `_api.updateProfile(...)`.

### Validação

- `dart analyze` dos arquivos alterados: **No issues found**.
- `./scripts/check_no_direct_supabase.sh`: **continua falhando** por ocorrências residuais em blocos grandes (`api_service.dart`, `data_gateway.dart`, `central_service.dart`, etc.).

### Observação

- Este lote reduziu ocorrências em serviços auxiliares e auth UI.
- Próxima etapa recomendada: atacar em sequência `data_gateway.dart` e `central_service.dart` (alto volume), depois finalizar residual de `api_service.dart` para zerar o gate.

## 2026-05-01 - Gate anti-regressão Supabase reforçado (escopo REST-first)

### Alterações Realizadas

- Reforçado `tool/check_no_direct_supabase.sh` para bloquear os acessos diretos proibidos no app:
  - `.from(...)`
  - `.rpc(...)`
  - `.channel(...)`
  - `.functions.invoke(...)`
  - `.storage.from(...)`
- Adicionado suporte a whitelist explícita por arquivo em `tool/supabase_direct_access_whitelist.txt` para migração gradual controlada.
- Mantida execução em dois modos:
  - `--changed` para gate de PR (anti-regressão incremental)
  - `--all` para auditoria de convergência total do app

### Arquivos Impactados

- `tool/check_no_direct_supabase.sh`
- `tool/supabase_direct_access_whitelist.txt`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `bash tool/check_no_direct_supabase.sh --changed`
  - `bash tool/check_no_direct_supabase.sh --all`
- Resultado:
  - `--changed`: OK (nenhuma nova regressão nos arquivos alterados)
  - `--all`: falha esperada nesta fase, listando ocorrências legadas ainda não migradas (principalmente em `ApiService`, `DataGateway` e telas de auth/pagamento/provider/home)

### Observação

- Este gate endurecido atende a governança para impedir regressão enquanto a migração total para REST segue por fases.
- Próximo passo natural é reduzir a whitelist a zero e fazer `--all` passar sem exceções.

## 2026-05-01 - Etapas 1, 2 e 3 (avanço incremental REST-first no app)

### Alterações Realizadas

- Etapa 1 (núcleo de acesso):
  - iniciado corte de acesso direto no `DataGateway` para leituras críticas, migrando para `BackendApiClient` em vez de `Supabase.instance.client`.
- Etapa 2 (auth/sessão no app):
  - `CpfCompletionScreen` deixou de ler sessão pelo client Supabase direto (`auth.currentUser`) e passou a usar identidade já hidratada via `ApiService.currentUserId`.
- Etapa 3 (catálogo/cobertura de endpoints backend):
  - `DataGateway.loadChatParticipantsRemote(...)` agora consulta endpoint REST (`/api/v1/chat/participants`).
  - `DataGateway.loadChatConversations()` agora consulta endpoint REST (`/api/v1/chat/conversations`).
  - `DataGateway.loadProviderSchedules(...)` agora consulta endpoint REST (`/api/v1/providers/{id}/schedules`).
  - `DataGateway.loadProviderScheduleExceptions(...)` agora consulta endpoint REST (`/api/v1/providers/{id}/schedule-exceptions`).

### Arquivos Impactados

- `lib/features/auth/cpf_completion_screen.dart`
- `lib/services/data_gateway.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/auth/cpf_completion_screen.dart lib/services/data_gateway.dart`
  - `dart analyze lib/features/auth/cpf_completion_screen.dart lib/services/data_gateway.dart`
  - `bash tool/check_no_direct_supabase.sh --changed`
- Resultado:
  - `dart analyze`: sem issues de código
  - `check_no_direct_supabase --changed`: OK
- Observação:
  - o `dart analyze` exibiu o aviso já conhecido de telemetria em filesystem readonly após concluir a análise; não indica erro funcional no código alterado.

### Observação de escopo

- Este avanço removeu pontos diretos em arquivos-chave desta sprint, mas a convergência total (`--all`) ainda depende de migração adicional dos usos legados restantes em `ApiService` e demais módulos do app.

## 2026-05-01 - Check completo do ApiService + migração inicial auth/profile/media para backend REST

### Alterações Realizadas

- Auditoria completa em `lib/services/api_service.dart` (arquivo com ~8k linhas) para identificar pontos de uso direto de Supabase.
- Migração aplicada em métodos críticos de identidade/perfil/mídia:
  - `getUserData()`
    - removida dependência direta de `Supabase.instance.client.auth.currentUser`;
    - leitura primária via `GET /api/v1/me` e fallback por `id` local quando necessário.
  - `updateProfile(...)`
    - removido update direto em `users` via Supabase client;
    - update via backend `PUT /api/v1/users/{id}`.
  - `refreshUserData()`
    - agora reutiliza `getUserData()` (caminho backend-first).
  - `uploadAvatarImage(...)`
    - removido upload direto `storage.from('avatars').uploadBinary(...)` no app;
    - upload via `POST /api/v1/media/upload` com payload base64;
    - persistência de `avatar_url` via `PUT /api/v1/users/{id}`.
  - `uploadVerificationImage(...)`
    - removido upload direto `storage.from('id-verification')`;
    - upload via `POST /api/v1/media/upload`.
  - `saveDriverDocumentPaths(...)`
    - removido update direto em `users` via Supabase;
    - update via `PUT /api/v1/users/{id}`.
- Correção pontual de sintaxe em `CpfCompletionScreen` para restaurar compilação.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `lib/features/auth/cpf_completion_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart lib/features/auth/cpf_completion_screen.dart`
  - `bash tool/check_no_direct_supabase.sh --changed`
- Resultado:
  - `dart analyze`: sem issues
  - `check_no_direct_supabase --changed`: OK

### Observação

- O `api_service.dart` ainda contém vários pontos legados de Supabase direto fora deste recorte inicial; esta entrega reduz blocos críticos de auth/profile/media e prepara o próximo corte por domínio (services/dispatch/scheduling/notifications).

## 2026-05-01 - Continuidade da migração (services/dispatch) no ApiService

### Alterações Realizadas

- Avanço no bloco `services/dispatch` para reduzir acessos diretos no `ApiService`:
  - `getAvailableServices()`
    - removida leitura direta de `agendamento_servico` via Supabase client;
    - leitura via backend `GET /api/v1/services/available`.
  - `_resolveCurrentProviderUserId()`
    - removida dependência de `auth.currentUser` + query direta em `users`;
    - resolução via `GET /api/v1/me`.
  - `getActiveProviderOfferState(serviceId)`
    - removida query direta em `notificacao_de_servicos`;
    - leitura via backend `GET /api/v1/dispatch/{serviceId}/offer-state`.
  - `acceptService(serviceId)` e `rejectService(serviceId)`
    - removido uso direto de `Supabase.instance.client.auth.currentUser` nesses fluxos;
    - identidade derivada de estado local (`_currentAuthUid` / `_currentUserData`).

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
  - `bash tool/check_no_direct_supabase.sh --changed`
- Resultado:
  - `dart analyze`: sem issues
  - `check_no_direct_supabase --changed`: OK

### Observação

- A convergência total (`--all`) ainda depende de migração dos blocos legados restantes em `api_service.dart` (disputes, specialties, trechos de scheduling/catalog e alguns fluxos de service status).

## 2026-05-01 - Continuidade da migração (disputes + specialties) no ApiService

### Alterações Realizadas

- Migração do bloco de especialidades do prestador para backend REST:
  - `addProviderSpecialty(...)`
    - busca de profissão via endpoint backend (`/api/v1/professions?...`) em vez de query direta em `professions`;
    - mantém gravação via `/api/v1/providers/{id}/specialties`.
  - `removeProviderSpecialty(...)`
    - remoção via backend (`DELETE /api/v1/providers/{id}/specialties/{professionId}`), sem delete direto em `provider_professions`.
- Migração do bloco de disputas/reclamações para backend REST:
  - `contestService(...)` -> `POST /api/v1/services/{id}/contest`
  - `submitServiceComplaint(...)`
    - resolução de usuário via `/api/v1/me` (sem lookup direto em `users`);
    - marcação de contestação via endpoint backend.
  - `getOpenDisputeForService(...)` e `getLatestPrimaryDisputeForService(...)`
    - leitura via `/api/v1/service-disputes?...`
  - `acceptPlatformDisputeDecision(...)`
    - ack via `/api/v1/service-disputes/{id}`
    - atualização de serviço via `/api/v1/services/{id}`
  - `getBlockingDisputeForCurrentClient(...)`
    - leitura via `/api/v1/me` + `/api/v1/service-disputes?...`
- Limpeza de warnings pós-migração para manter análise sem issues.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
  - `bash tool/check_no_direct_supabase.sh --changed`
- Resultado:
  - `dart analyze`: sem issues
  - `check_no_direct_supabase --changed`: OK

### Observação

- Esta rodada reduz mais um bloco grande de `.from(...)` no `ApiService`; ainda restam trechos legados fora deste recorte (ex.: partes de catálogo/scheduling, configurações e fluxos específicos) para a convergência final do `--all`.

## 2026-05-01 - Bloco residual (catálogo/config/pagamento pontual) migrado no ApiService

### Alterações Realizadas

- Continuidade da migração REST-first em `api_service.dart` com foco em catálogo/scheduling/config e trechos pontuais:
  - `getProfessionTasks(...)`
    - removida consulta direta em `task_catalog` via Supabase;
    - leitura via backend `GET /api/v1/tasks?profession_id_eq=...&active_eq=true`;
    - mantida normalização e fallback por `getServicesMap()` para compatibilidade.
  - `getAppConfig()`
    - removida leitura direta em `app_configs`;
    - leitura via backend `GET /api/v1/app-config`.
  - `inferFixedFromProfessions(...)`
    - removida leitura direta em `provider_professions` e `professions`;
    - leitura via backend (`/api/v1/provider-professions` e `/api/v1/professions`).
  - `hasSavedCard()`
    - removida leitura direta em `user_payment_methods`;
    - leitura via backend `GET /api/v1/payment-methods?user_id_eq=...&limit=1`.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
  - `bash tool/check_no_direct_supabase.sh --changed`
- Resultado:
  - `dart analyze`: sem issues
  - `check_no_direct_supabase --changed`: OK

### Observação

- A redução de passivo segue incremental e segura; ainda restam trechos legados diretos no `ApiService` (especialmente blocos de scheduling/fixed-booking e alguns fluxos de serviço) para convergência total do `--all`.

## 2026-05-01 - Continuidade do bloco pesado (dispatch/service_requests) no ApiService

### Alterações Realizadas

- Novo corte no bloco residual de `ApiService` com foco em dispatch e pontos de `service_requests_new`:
  - `_filterRejectedDispatchOffers(...)`
    - removida leitura direta de `notificacao_de_servicos`;
    - leitura via backend (`/api/v1/dispatch/offers/rejected?...`).
  - `_filterActiveDispatchOffers(...)`
    - removidas leituras diretas de `service_dispatch_queue` e `notificacao_de_servicos`;
    - leitura via backend (`/api/v1/dispatch/queue/active?...` e `/api/v1/dispatch/offers/active?...`).
  - `testApprovePayment(...)`
    - removido update direto em `service_requests_new`;
    - migração para backend (`POST /api/v1/services/{id}/test-approve-payment`).

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
  - `bash tool/check_no_direct_supabase.sh --changed`
  - `rg` pontual para ocorrências remanescentes de `service_requests_new`/dispatch tables
- Resultado:
  - `dart analyze`: sem issues
  - `check_no_direct_supabase --changed`: OK
  - ocorrências diretas remanescentes de `service_requests_new` ainda existem em outros métodos e serão atacadas nas próximas rodadas.

## 2026-05-01 - Continuidade do bloco pesado (service_requests/task_catalog) no ApiService

### Alterações Realizadas

- Migração adicional de trechos residuais para backend REST em `ApiService`:
  - `getServicesMap()`
    - removida leitura direta de `task_catalog`;
    - leitura via backend `GET /api/v1/tasks?active_eq=true`.
  - `getServices()` (fluxo provider)
    - removida leitura direta em `service_requests_new`;
    - leitura via backend `GET /api/v1/services?user_id_eq=...`.
  - `createService(...)` (ramo mobile)
    - removido insert direto em `service_requests_new`;
    - criação via backend `POST /api/v1/services`.
  - `requestServiceEdit(...)`
    - removido update direto em `service_requests_new`;
    - update via backend `PUT /api/v1/services/{id}`.
  - `getAvailableForSchedule()`
    - removido fallback legado de leitura direta em `service_requests_new` quando endpoint principal não retorna dados.
  - `getProviderServices(...)`
    - removida leitura direta de `task_catalog`;
    - leitura via backend `GET /api/v1/tasks?profession_id_in=...`.
  - `resolveProfessionIdForServiceCreation(...)`
    - removidas consultas diretas em `task_catalog`/`professions`;
    - resolução via backend (`/api/v1/tasks` e `/api/v1/professions`).

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/services/api_service.dart`
  - `bash tool/check_no_direct_supabase.sh --changed`
  - `rg` para ocorrências residuais de `task_catalog` e `service_requests_new` diretos
- Resultado:
  - `dart analyze`: sem issues
  - `check_no_direct_supabase --changed`: OK
  - `rg`: sem ocorrências diretas restantes de `task_catalog` e `service_requests_new` no arquivo.

## 2026-05-01 - Continuidade do próximo passo (fixed_booking/provider_*) no ApiService

### Alterações Realizadas

- Migração de consultas de intenção PIX de agendamento fixo para backend REST:
  - `getPendingFixedBookingIntent(...)`
    - removida leitura direta em `fixed_booking_pix_intents`/`fixed_booking_slot_holds`;
    - leitura via backend (`/api/v1/bookings/fixed/intents/{id}` + `/slot-hold`).
  - `getLatestPendingFixedBookingIntentForCurrentClient()`
    - removida leitura direta em `fixed_booking_pix_intents`/`fixed_booking_slot_holds`;
    - leitura via backend (`/api/v1/bookings/fixed/intents/latest-pending` + `/slot-hold`).
  - `cancelPendingFixedBookingIntent(...)`
    - removidos updates diretos em `fixed_booking_pix_intents` e `fixed_booking_slot_holds` no fallback;
    - cancelamento via backend (`POST /api/v1/bookings/fixed/intents/{id}/cancel`).
- Limpeza técnica pós-migração:
  - removidos helpers/constantes órfãos de fallback de projeção de slot hold que ficaram sem uso.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/services/api_service.dart`
  - `bash tool/check_no_direct_supabase.sh --changed`
- Resultado:
  - `dart analyze`: sem issues
  - `check_no_direct_supabase --changed`: OK

### Observação

- O recorte de fixed booking avançou sem regressão de compilação; ainda existem blocos legados `provider_*` e alguns pontos de `agendamento_servico`/`provider_tasks` para próximo lote.

## 2026-05-01 - Lote provider_* e agendamento (continuação) no ApiService

### Alterações Realizadas

- Migração backend-first no bloco `provider_*` do `ApiService`:
  - `saveProviderService(...)`
    - removida leitura direta de `provider_professions`;
    - leitura via backend (`/api/v1/provider-professions?...`).
  - `getProviderServices(...)`
    - removida leitura direta de `provider_professions`;
    - leitura via backend (`/api/v1/provider-professions?...`).
    - removidas operações diretas em `provider_tasks` (select/upsert/reload);
    - leitura de personalização via backend (`/api/v1/provider-tasks?...`).
  - `setProviderServiceActive(...)`
    - mantido update canônico via backend;
    - removido acoplamento local de sincronização de contrato via client Supabase.
  - `getProviderProfile(providerId)`
    - `provider_schedules` migrado para backend (`/api/v1/providers/{id}/schedules`);
    - `provider_professions` migrado para backend (`/api/v1/providers/{id}/specialties`).
- Limpeza de warnings pós-migração:
  - removida constante `_providerScheduleProjection` sem uso;
  - removido cast desnecessário no processamento de profissões.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
  - `bash tool/check_no_direct_supabase.sh --changed`
  - `rg` para ocorrências de `provider_professions/provider_tasks/provider_schedules`
- Resultado:
  - `dart analyze`: sem issues
  - `check_no_direct_supabase --changed`: OK
  - ainda há ocorrências residuais desses termos em outros blocos (ex.: `searchProviders` e fluxos específicos), a serem tratadas no próximo lote.

## 2026-05-01 - Lote searchProviders + leitura de artifacts de agendamento fixo

### Alterações Realizadas

- `searchProviders(...)`:
  - removida consulta direta em `provider_professions` para filtro por profissão;
  - lookup agora via backend (`/api/v1/provider-professions?profession_id_in=...`).
- `_loadFixedCompletionArtifacts(serviceId)`:
  - removida leitura direta em `agendamento_servico` para artifacts/códigos;
  - leitura agora via backend (`/api/v1/bookings/fixed/{id}/artifacts`).

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
  - `bash tool/check_no_direct_supabase.sh --changed`
  - `rg` para mapear resíduos de `provider_professions`/`agendamento_servico`
- Resultado:
  - `dart analyze`: sem issues
  - `check_no_direct_supabase --changed`: OK
  - permanecem ocorrências residuais desses termos em outros métodos (já mapeadas para próximo lote).

## 2026-05-01 - Lote residual (provider_professions + agendamento_servico) no ApiService

### Alterações Realizadas

- `searchProvidersForServiceProgressive(...)`:
  - removidas consultas diretas em `provider_professions` e `provider_tasks`;
  - lookup de vínculos e tarefas do prestador migrado para backend (`/api/v1/provider-professions` e `/api/v1/provider-tasks`).
- `getProviderSpecialties()`:
  - removida leitura direta de `provider_professions`;
  - leitura via backend (`/api/v1/providers/{id}/specialties`).
- `_ensureFixedCompletionCode(serviceId)`:
  - removido update direto em `agendamento_servico`;
  - atualização de artifacts/código via backend (`PUT /api/v1/bookings/fixed/{id}/artifacts`).

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
  - `bash tool/check_no_direct_supabase.sh --changed`
  - `rg` para resíduos de `provider_professions`/`agendamento_servico`
- Resultado:
  - `dart analyze`: sem issues
  - `check_no_direct_supabase --changed`: OK
  - restam ocorrências residuais de `agendamento_servico` e referências textuais de `provider_professions` em outros pontos já mapeados para próximos lotes.

## 2026-05-01 - Fechamento do bloco final agendamento_servico (ApiService)

### Alterações Realizadas

- Removido insert direto em `agendamento_servico` no fluxo de criação de booking fixo:
  - `_createFixedBookingRecord(...)` agora cria via backend `POST /api/v1/bookings/fixed`.
- Removidos updates diretos de estado/telemetria do agendamento fixo para tabela:
  - `markClientDeparting(...)`
  - `updateServiceClientLocation(...)`
  - `updateClientTrackingState(...)`
  - `upsertClientTrackingLocation(...)`
  - `markClientArrived(...)`
  - todos migrados para `PUT /api/v1/bookings/fixed/{id}`.
- Ajustado `completeService(...)` (ramo fixo) para evitar uso de nome de tabela legada no helper de update.
- Limpeza técnica:
  - removidos helpers/constantes não utilizados após a migração (`_fixedBookingWithTaskProjection`, `_extractMissingColumnName`, `_updateTableByIdWithMissingColumnFallback`).

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/services/api_service.dart`
  - `bash tool/check_no_direct_supabase.sh --changed`
  - `rg` para `agendamento_servico` no arquivo
- Resultado:
  - `dart analyze`: sem issues
  - `check_no_direct_supabase --changed`: OK
  - ocorrência residual restante é apenas textual em filtro de campo relacional (`agendamento_servico_id`) e não acesso direto à tabela.

## 2026-05-01 - Limpeza final de referência textual residual (agendamento_servico_id)

### Alterações Realizadas

- `lib/services/api_service.dart`:
  - removida a referência textual residual de campo relacional `agendamento_servico_id` no `orFilter` do fluxo de conclusão de serviço fixo;
  - mantido apenas filtro canônico por `service_request_id`, sem acesso direto/indireto à tabela legada.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze lib/services/api_service.dart`
  - `bash tool/check_no_direct_supabase.sh --changed`
  - `rg -n "agendamento_servico_id|agendamento_servico" lib/services/api_service.dart`
- Resultado:
  - `dart analyze`: sem issues
  - `check_no_direct_supabase --changed`: OK
  - `rg`: sem ocorrências no arquivo.

## 2026-05-01 - Fix de build no emulador (ProviderKeepaliveService)

### Alterações Realizadas

- `lib/services/provider_keepalive_service.dart`:
  - corrigida referência inválida `ProviderPresenceService.sessionJsonKey` (membro removido na refatoração para `provider_presence/`);
  - mantida compatibilidade com chave legada via constante local:
    - `sessionJsonKey = 'provider_keepalive_session_json'`.

### Arquivos Impactados

- `lib/services/provider_keepalive_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `flutter analyze lib/services/provider_keepalive_service.dart`
- Resultado:
  - sem issues no arquivo analisado.

## 2026-05-01 - Correção de login (email/senha) no Android

### Alterações Realizadas

- `lib/integrations/supabase/auth/supabase_auth_repository.dart`:
  - removido uso do endpoint legado `/api/v1/auth/login` no fluxo de `login(...)`;
  - login passou a usar `Supabase.instance.client.auth.signInWithPassword(...)`, alinhado ao fluxo atual do app;
  - persistência do token mantida via `ApiService().saveToken(...)` após autenticação bem-sucedida.

### Arquivos Impactados

- `lib/integrations/supabase/auth/supabase_auth_repository.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `flutter analyze lib/integrations/supabase/auth/supabase_auth_repository.dart`
- Resultado:
  - `No issues found!`

## 2026-05-01 — Correção de build (ApiService)
- Corrigido erro estrutural em `lib/services/api_service.dart`: removido bloco duplicado/fora de escopo dentro da seção de `invokeEdgeFunction`, que estava quebrando o parser da classe e causando cascata de erros `The method ... isn't defined for the type 'ApiService'`.
- Ajustado tratamento de exceções em `invokeEdgeFunction`: removido `on TimeoutException` redundante no final do bloco `try/catch`.
- Corrigido `lib/core/network/backend_api_client.dart`: adicionado `import 'dart:async';` para suportar `TimeoutException` nos `on-catch`.
- Validação com `dart analyze` (arquivos-alvo): sem erros de compilação; restaram apenas 3 warnings de `unused_catch_clause` em `api_service.dart`.
- Ajustado `loginWithFirebase` em `lib/services/api_service.dart` para tolerar atraso de consistência após `/api/v1/auth/sync`: adicionado retry progressivo (até 5 tentativas) e fallback de leitura por `supabase_uid` antes de lançar erro de "usuário recém criado".
- Harden no fluxo `loginWithFirebase` (`lib/services/api_service.dart`) para erro de "usuário recém criado":
  - retry aumentado (6 tentativas) após `/api/v1/auth/sync`;
  - fallback adicional via `/api/v1/me` quando a linha ainda não aparece em `users`;
  - mensagem de erro final ajustada para indicar atraso de reflexão de sync.

## 2026-05-01 - Correção de crash no cadastro de novo usuário (lifecycle/context)

### Alterações Realizadas

- Corrigido o fluxo de finalização do cadastro em `RegisterScreen` para evitar acesso ao `BuildContext`/estado quando a tela já está em transição de descarte.
- Em `_submit()`:
  - adicionadas checagens `if (!mounted) return;` após chamadas assíncronas críticas (`signUpOrSignIn`, `register`, `saveProviderSchedule`, loop de `saveProviderService`, e antes/depois de `_clearState()`).
  - navegação final alterada para `await _redirectUserBasedOnRole();` com guarda de ciclo de vida prévia.
  - exibição de erro trocada para `ScaffoldMessenger.maybeOf(context)?.showSnackBar(...)` com guarda `mounted && context.mounted` para reduzir risco de assert durante desativação da árvore.
- Efeito prático:
  - reduz significativamente a chance do erro de framework ligado a lifecycle (`_ElementLifecycle`) ao concluir criação de usuário;
  - fluxo de cadastro fica mais resiliente a mudanças de rota e descarte do widget durante operações assíncronas.

### Arquivos Impactados

- `lib/features/auth/register_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/auth/register_screen.dart`
  - `dart analyze lib/features/auth/register_screen.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, o Dart tentou atualizar telemetria em diretório somente leitura (`/home/servirce/.dart-tool/...`) e retornou `FileSystemException`; isso não indica erro no código alterado.

## 2026-05-01 - Correção da seleção de sugestão na busca de serviços (query digitada)

### Alterações Realizadas

- Corrigido o fluxo de seleção em `HomeSearchScreen` para quando a sugestão não traz `service_type` explícito (ex.: "Sugestão digitada").
- Em `_handleSuggestionSelected(...)`:
  - método convertido para `Future<void>`;
  - antes de decidir navegação, o app agora tenta classificar a query com `ApiService.classifyService(query)`;
  - resultado da classificação é mesclado à sugestão (`service_type`, `profession_name`, `profession_id`, `task_id`, `task_name`);
  - navegação passa a usar a sugestão enriquecida, reduzindo erro de roteamento para fluxo errado.
- Efeito prático:
  - consultas como "copia chave" deixam de depender apenas de heurística local;
  - a abertura do fluxo de serviço fica mais consistente entre `on_site` e `at_provider`, com maior chance de mostrar os prestadores corretos.

### Arquivos Impactados

- `lib/features/home/home_search_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/home/home_search_screen.dart`
  - `dart analyze lib/features/home/home_search_screen.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, ocorreu aviso de telemetria em FS somente leitura (`/home/servirce/.dart-tool/...`); sem impacto no código.

## 2026-05-01 - Busca: bloqueio de "chave/chavce" + aceleração por cache de prefixo

### Alterações Realizadas

- Removido da busca qualquer sugestão relacionada a `chave/chavce`.
- Em `HomeSearchScreen`:
  - criada blacklist `_blockedSearchTokens` com `chave`, `chavce`, `chaveiro`, `fechadura`;
  - removido grupo de sinônimos de chaveiro do léxico base;
  - adicionado filtro em `_normalizeSuggestion(...)` para descartar sugestões bloqueadas;
  - adicionado bloqueio antecipado em `_fetchRemoteAutocompleteHints(...)` para limpar resultados quando a query estiver bloqueada.
- Aceleração da busca por digitação:
  - adicionado cache por prefixo (`_readPrefixCache`) para reutilizar resultados de teclas anteriores enquanto o usuário digita;
  - cache agora usa query normalizada (`TaskAutocomplete.normalizePt(query)`) para maior reaproveitamento e menor latência percebida.

### Arquivos Impactados

- `lib/features/home/home_search_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/home/home_search_screen.dart`
  - `dart analyze lib/features/home/home_search_screen.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`
- Observação:
  - após o `dart analyze`, houve aviso de telemetria em filesystem somente leitura (`/home/servirce/.dart-tool/...`), sem impacto no código.

## 2026-05-01 - Hardening de startup/sync contra consistência eventual (perfil e FCM)

### Alterações Realizadas

- Corrigido fluxo de startup/autenticação para não quebrar quando o `sync` do usuário ainda não refletiu no banco.
- Em `ApiService.registerDeviceToken(...)`:
  - tratamento específico para `PostgrestException` com código `PGRST116` no ramo `_userId == null`;
  - quando não há linha em `users` ainda, agora ignora de forma segura (não fatal) em vez de poluir logs com erro.
- Em `ApiService.syncUserProfile(...)` (trecho de criação/sincronização de usuário):
  - removido throw fatal `Falha ao carregar usuário recém criado (sync ainda não refletido)`;
  - adicionado fallback temporário local (`_role` + `_currentUserData` mínimos) para permitir continuidade do app enquanto o backend converge.
- Em `StartupService._refreshProfileFromBackend(...)`:
  - quando perfil canônico retorna `null`, não lança exceção;
  - comportamento ajustado para tolerância a atraso de propagação no startup.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `lib/services/startup_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart lib/services/startup_service.dart`
  - `dart analyze lib/services/api_service.dart lib/services/startup_service.dart`
- Resultado:
  - sem erros novos nas áreas alteradas;
  - analyzer reportou warnings preexistentes de `unused_catch_clause` em outras linhas de `api_service.dart`.
- Observação:
  - após a análise, houve aviso de telemetria em FS somente leitura (`/home/servirce/.dart-tool/...`), sem impacto funcional.

## 2026-05-01 - Home resiliente quando snapshot canônico indisponível

### Alterações Realizadas

- Ajustado `_loadServices()` em `HomeScreen` para não lançar exceção quando o snapshot canônico (`/api/v1/home/client`) estiver indisponível.
- Em vez de `throw Exception('Snapshot canônico da home do cliente indisponível.')`, o fluxo agora degrada graciosamente:
  - mantém o carregamento silencioso,
  - zera `servicesList`,
  - limpa `_activeServiceForBanner`,
  - finaliza `isLoadingServices` normalmente.
- Efeito prático:
  - evita erro ruidoso no log durante hot restart/janela de consistência,
  - mantém a Home estável enquanto o backend/sessão termina de hidratar.

### Arquivos Impactados

- `lib/features/home/home_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/home/home_screen.dart`
  - `flutter analyze lib/features/home/home_screen.dart lib/services/api_service.dart`
- Resultado:
  - sem novos erros introduzidos pela alteração;
  - análise retornou apenas 3 warnings preexistentes de `unused_catch_clause` em `lib/services/api_service.dart` (linhas 3011, 3074, 3084).

## 2026-05-01 - Correção da busca: desbloqueio de termos de chaveiro

### Alterações Realizadas

- Removido bloqueio de termos na busca da Home que estava descartando consultas válidas como `copia chave simples`.
- Em `HomeSearchScreen`:
  - removida a lista `_blockedSearchTokens`;
  - `_isBlockedQueryOrSuggestion(...)` passou a retornar `false` (sem bloqueio de consulta/sugestão).
- Efeito prático:
  - consultas com termos `chave`, `chaveiro`, `fechadura` deixam de ser barradas;
  - autocomplete e catálogo voltam a exibir resultados normalmente para esses serviços.

### Arquivos Impactados

- `lib/features/home/home_search_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/home/home_search_screen.dart`
  - `flutter analyze lib/features/home/home_search_screen.dart`
- Resultado:
  - `No issues found!`

## 2026-05-01 - Correção de binding autocomplete: parser de campos do endpoint

### Alterações Realizadas

- Corrigido parser de `fetchServiceAutocompleteHints(...)` em `ApiService`.
- O fallback de autocomplete agora aceita múltiplos nomes de campo retornados pelo backend:
  - `task_name`, `taskName`, `nome`, `name`, `title`, `titulo`.
- Efeito prático:
  - mesmo quando o endpoint retorna payload com `task_name` (em vez de `name`), a UI passa a receber e renderizar sugestões no autocomplete.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `flutter analyze lib/services/api_service.dart lib/features/home/home_search_screen.dart`
- Resultado:
  - sem erros novos relacionados à alteração;
  - análise retornou apenas 3 warnings preexistentes de `unused_catch_clause` em `lib/services/api_service.dart` (linhas 3011, 3074, 3084).

## 2026-05-01 - Redução de 404 na Home Web: migração de perfil de prestador para backend canônico

### Alterações Realizadas

- Corrigido ponto de leitura que ainda consultava `users` diretamente via Supabase no fluxo de perfil de prestador.
- Em `ApiService.getProviderProfile(int providerId)`:
  - removida a busca inicial direta em `Supabase.instance.client.from('users')...`;
  - adotado `GET /api/v1/providers/{providerId}/profile` como fonte canônica dos dados básicos.
- Padronizado endpoint de configs globais:
  - `ApiService.getAppConfig()` agora consulta `GET /api/v1/app-configs` (antes: `/api/v1/app-config`).
- Efeito prático:
  - reduz chamadas Web diretas que apareciam como `404` no `browser_client.dart`;
  - melhora consistência backend-first no carregamento de perfil/configs.

### Arquivos Impactados

- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart`
  - `dart analyze lib/services/api_service.dart`
- Resultado:
  - análise retornou warnings preexistentes de `unused_catch_clause` em outras seções de `api_service.dart`;
  - sem erro novo relacionado às mudanças aplicadas.
- Observação:
  - após o `dart analyze`, o Dart voltou a tentar gravar telemetria em área somente leitura (`FileSystemException`), aviso ambiental já recorrente no workspace.

## 2026-05-01 - Correção de URL inválida no autocomplete de tarefas (Edge Functions)

### Alterações Realizadas

- Corrigido o `BackendApiClient` para normalizar rotas canônicas `/api/v1/...` quando a base URL está em fallback de Edge Functions (`.../functions/v1`).
- Adicionado método `_normalizePathForBase(baseUrl, path)` com regra:
  - se `baseUrl` termina com `/functions/v1` e o path começa com `/api/v1/`, o cliente reescreve para `/api/...`.
- Aplicado o normalizador em todos os métodos HTTP do cliente:
  - `getJson`, `postJson`, `putJson`, `deleteJson`.
- Efeito prático:
  - evita URLs como `.../functions/v1/api/v1/tasks/autocomplete` (que geravam `Function not found`);
  - passa a montar `.../functions/v1/api/tasks/autocomplete` no fallback de functions.

### Arquivos Impactados

- `lib/core/network/backend_api_client.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/network/backend_api_client.dart`
  - `dart analyze lib/core/network/backend_api_client.dart`
- Resultado:
  - `No issues found!`
- Observação:
  - após a análise, ocorreu aviso ambiental de telemetria (`FileSystemException` em área read-only), sem impacto na validação do código.

## 2026-05-02 - Automação: subir Supabase local automaticamente no fluxo web

### Alterações Realizadas

- Atualizado `bin/run_web_local.sh` para auto-recuperar ambiente local do Supabase.
- Antes de coletar `API_URL`/`ANON_KEY`, o script agora:
  - verifica `supabase status`;
  - se estiver parado, executa `supabase start` automaticamente.
- Efeito prático:
  - ao iniciar o app web pelo script, o Supabase local sobe sozinho quando necessário;
  - evita erro de conexão por stack local desligado em ciclos de desenvolvimento.

### Arquivos Impactados

- `bin/run_web_local.sh`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `bash -n bin/run_web_local.sh`
- Resultado:
  - sintaxe do script válida.

## 2026-05-02 - Automação expandida: Supabase auto-start em scripts remotos

### Alterações Realizadas

- Expandida a automação de subida do Supabase local para os scripts remotos.
- `bin/run_android_remote.sh`:
  - adicionada validação de `supabase` CLI no PATH;
  - adicionado bloco de auto-start (`supabase status` + `supabase start` quando parado).
- `bin/run_web_remote.sh`:
  - adicionada validação de `supabase` CLI no PATH;
  - adicionado bloco de auto-start (`supabase status` + `supabase start` quando parado).
- Efeito prático:
  - fluxo local fica consistente em web local, web remote e android remote;
  - reduz falhas por ambiente Supabase desligado antes de `flutter run`.

### Arquivos Impactados

- `bin/run_android_remote.sh`
- `bin/run_web_remote.sh`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `bash -n bin/run_android_remote.sh`
  - `bash -n bin/run_web_remote.sh`
- Resultado:
  - sintaxe dos scripts válida.

## 2026-05-02 - Hotfix crítico: Stack Overflow em chamadas de API

### Alterações Realizadas

- Corrigido bug de recursão infinita em `BackendApiClient._normalizePathForBase(...)`.
- Causa raiz:
  - a variável `normalizedPath` estava sendo inicializada chamando o próprio método (`_normalizePathForBase(...)`), gerando loop recursivo imediato.
- Correção aplicada:
  - `normalizedPath` voltou a ser derivado diretamente de `path` (`path.startsWith('/') ? path : '/$path'`).
- Efeito prático:
  - elimina `Stack Overflow` em cascata nas chamadas do `ApiService`;
  - restabelece requests de busca/autocomplete/config/profile.

### Arquivos Impactados

- `lib/core/network/backend_api_client.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/network/backend_api_client.dart`
  - `dart analyze lib/core/network/backend_api_client.dart`
- Resultado:
  - formatação ok;
  - ambiente voltou a apresentar aviso de telemetria em FS read-only durante `dart analyze`.

## 2026-05-02 - Correção de 404 em /functions/v1/api/*: backend REST com base explícita

### Alterações Realizadas

- Ajustado `BackendApiClient.resolveBaseUrl()` para **não** usar fallback automático `SUPABASE_URL/functions/v1` quando `BACKEND_API_URL` não está definido.
- Motivo:
  - o fallback para Edge Functions estava gerando chamadas como `/functions/v1/api/auth/bootstrap` e retornando `Function not found` no ambiente local sem função `api` publicada.
- Scripts de execução atualizados para injetar `BACKEND_API_URL` por padrão:
  - `bin/run_web_local.sh` -> `http://127.0.0.1:4011`
  - `bin/run_web_remote.sh` -> `http://127.0.0.1:4011`
  - `bin/run_android_remote.sh` -> `http://10.0.2.2:4011`
- Efeito prático:
  - endpoints `/api/v1/*` passam a apontar para o `backend-api` (Express) em vez de tentar resolver como Edge Function.

### Arquivos Impactados

- `lib/core/network/backend_api_client.dart`
- `bin/run_web_local.sh`
- `bin/run_web_remote.sh`
- `bin/run_android_remote.sh`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `bash -n bin/run_web_local.sh`
  - `bash -n bin/run_web_remote.sh`
  - `bash -n bin/run_android_remote.sh`
  - `dart format lib/core/network/backend_api_client.dart`
- Resultado:
  - scripts com sintaxe válida;
  - arquivo Dart formatado sem alterações pendentes.

## 2026-05-02 - Reconfiguração para backend 100% Supabase (sem dependência de Node backend-api)

### Alterações Realizadas

- Restaurado o fallback canônico do `BackendApiClient` para Supabase Edge Functions:
  - quando `BACKEND_API_URL` não está definido, o cliente volta a usar `SUPABASE_URL/functions/v1`.
- Removida a injeção obrigatória de `BACKEND_API_URL` dos scripts de execução:
  - `bin/run_web_local.sh`
  - `bin/run_web_remote.sh`
  - `bin/run_android_remote.sh`
- Efeito prático:
  - o app volta a operar com backend via Supabase local (Edge Functions), sem exigir subir `backend-api` Node separado.

### Arquivos Impactados

- `lib/core/network/backend_api_client.dart`
- `bin/run_web_local.sh`
- `bin/run_web_remote.sh`
- `bin/run_android_remote.sh`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `bash -n bin/run_web_local.sh`
  - `bash -n bin/run_web_remote.sh`
  - `bash -n bin/run_android_remote.sh`
  - `dart format lib/core/network/backend_api_client.dart`
- Resultado:
  - scripts com sintaxe válida;
  - Dart format executado sem mudanças adicionais.

## 2026-05-02 - Implementação do gateway Supabase `api` para rotas /api/v1 e correção da busca

### Alterações Realizadas

- Criada nova Edge Function canônica: `supabase/functions/api/index.ts`.
- Implementado roteamento interno para contratos usados pelo app:
  - `GET /api/v1/auth/bootstrap`
  - `GET /api/v1/home/client`
  - `GET /api/v1/tasks`
  - `GET /api/v1/tasks/autocomplete`
- Implementado fallback de prefixo de rota para aceitar tanto `/api/v1/*` quanto `/api/*` dentro da função.
- Reaproveitada a estratégia de ranking lexical/sinônimos para autocomplete de tarefas (compatível com a busca "copia de chave").
- Padronizado retorno para rota não implementada no gateway (`route_not_found`, status 404) em vez de erro estrutural "Function not found".
- Durante validação, corrigida aderência ao schema real do banco local:
  - removido uso de `task_catalog.description` (coluna inexistente);
  - removido uso de `professions.keywords` (coluna inexistente no join atual).

### Arquivos Impactados

- `../supabase/functions/api/index.ts`
- `RELATORIO_DEV.md`

### Validação (Terminal)

- `GET /functions/v1/api/auth/bootstrap`:
  - respondeu `200` com payload canônico (`authenticated`, `nextRoute`, etc.).
- `GET /functions/v1/api/tasks?active_eq=true&limit=20`:
  - respondeu `200` com lista real de tarefas ativas.
- `GET /functions/v1/api/tasks/autocomplete?q=copia&limit=8`:
  - respondeu `200` com resultados relevantes (ex.: "Cópia de Chave Tetra", "Cópia de Chave Simples").

### Resultado prático

- A causa estrutural da busca vazia foi resolvida no backend Supabase local: agora existe a função `api` para atender os endpoints canônicos usados pelo app.

## 2026-05-02 - Extensão do gateway `api` para rotas-base do app (eliminação de 404 em cascata)

### Alterações Realizadas

- Expandida a função `supabase/functions/api/index.ts` para cobrir endpoints ainda ausentes e eliminar `route_not_found` recorrente no frontend:
  - `GET /api/v1/users`
  - `GET /api/v1/me`
  - `GET /api/v1/profile/me`
  - `GET /api/v1/app-configs`
  - `GET /api/v1/tracking/active-service`
- Ajustada projeção da tabela `users` para schema real do ambiente local (remoção de `is_medical`, coluna inexistente nesse banco).
- Mantida resposta canônica para estado sem serviço ativo (`activeService: null`) no endpoint de tracking.

### Arquivos Impactados

- `../supabase/functions/api/index.ts`
- `RELATORIO_DEV.md`

### Validação (Terminal)

- `GET /functions/v1/api/users?supabase_uid_eq=...&limit=1` -> `200` com usuário.
- `GET /functions/v1/api/app-configs` -> `200` com lista de configs.
- `GET /functions/v1/api/tracking/active-service` -> `200` com `{ activeService: null }`.
- `GET /functions/v1/api/me` e `GET /functions/v1/api/profile/me`:
  - retornam `401 unauthorized` sem token Bearer (esperado via curl anônimo);
  - no app autenticado devem responder sem 404.

## 2026-05-02 - Remoção de lista duplicada de sugestões na tela Buscar serviços

### Alterações Realizadas

- Removido o bloco duplicado de renderização de sugestões no corpo da `HomeSearchScreen`.
- Antes, quando havia `_remoteAutocompleteHints`, a tela exibia:
  - lista principal no `HomeSearchBar` (topo);
  - e uma segunda lista idêntica abaixo (parte circulada pelo usuário).
- Agora permanece apenas a lista principal no topo, evitando duplicação visual.

### Arquivos Impactados

- `lib/features/home/home_search_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/home/home_search_screen.dart`
- Resultado:
  - formatação aplicada com sucesso.

## 2026-05-02 - Correção do fluxo de criação de serviço no gateway Supabase `api`

### Problemas reportados

- `GET /api/v1/service-disputes` retornando `404 route_not_found`.
- `POST /api/v1/services` retornando `405 method_not_allowed`, quebrando criação de serviço no app com erro `502`.

### Alterações Realizadas

- Expandido `supabase/functions/api/index.ts` com rotas adicionais:
  - `GET /api/v1/service-disputes`
  - `POST /api/v1/service-disputes`
  - `GET /api/v1/services`
  - `POST /api/v1/services`
- Descoberta técnica no schema local:
  - não existe tabela `public.services`;
  - tabela canônica local é `public.service_requests`.
- Ajustado gateway para operar em `service_requests`.
- Implementada geração de `id` no `POST /services` (campo obrigatório sem default no schema local).
- Implementado filtro de colunas permitidas no insert para ignorar campos não existentes enviados pelo app (ex.: `client_uid`), evitando erro de schema cache.

### Validação (Terminal)

- `GET /functions/v1/api/service-disputes?...` -> `200` com `{ data: [] }` (sem 404).
- `POST /functions/v1/api/services` -> `200` com registro criado em `service_requests`.
- `GET /functions/v1/api/services?user_id_eq=419...` -> `200` listando serviço criado.

### Resultado prático

- Erro `405` em `/api/services` removido.
- Falha de criação de serviço com `502` (origem: rota ausente/incompatível) resolvida no gateway Supabase.

## 2026-05-02 - Correção de 404 no tracking de serviço (gateway `api` Supabase)

### Problemas reportados

- `GET /api/v1/tracking/services/:id?scope=mobileOnly` retornando `404 route_not_found`.
- `GET /api/v1/tracking/services/:id/snapshot?scope=mobileOnly` retornando `404 route_not_found`.

### Alterações Realizadas

- Adicionadas rotas no `supabase/functions/api/index.ts`:
  - `GET /api/v1/tracking/services/:id`
  - `GET /api/v1/tracking/services/:id/snapshot`
- Implementação baseada na tabela canônica local `service_requests`.
- Para `snapshot`, adicionado enriquecimento mínimo compatível com app:
  - `service`
  - `providerLocation` (null)
  - `paymentSummary` (null)
  - `finalActions` (null)
  - `openDispute`
  - `latestPrimaryDispute`

### Validação (Terminal)

- `GET /functions/v1/api/tracking/services/1777694486648-7s2739fm?scope=mobileOnly` -> `200` com `data.service`.
- `GET /functions/v1/api/tracking/services/1777694486648-7s2739fm/snapshot?scope=mobileOnly` -> `200` com payload de snapshot compatível.

### Resultado prático

- Eliminado ciclo de `404 route_not_found` no tracking do serviço recém-criado.

## 2026-05-02 - Correção de UUID no tracking/disputes e compatibilidade de stream

### Problemas reportados

- `GET /api/v1/service-disputes?...service_id_eq=<id não-uuid>` retornando `500` com `invalid input syntax for type uuid`.
- Stream de serviço degradando com `PostgrestException 22P02` ao acompanhar IDs não-UUID.

### Alterações Realizadas

- Gateway Supabase `api` (`../supabase/functions/api/index.ts`):
  - `POST /services` agora gera `id` em UUID v4 (`crypto.randomUUID()`), alinhando com colunas UUID em fluxos relacionados.
  - `GET /service-disputes` agora faz short-circuit seguro: quando `service_id_eq` não é UUID válido, retorna `data: []` em vez de consultar e estourar erro 500.
- App Flutter (`DataGateway.watchService`):
  - stream móvel alterado de `service_requests_new` para `service_requests`, compatível com os serviços criados pelo gateway local atual.

### Arquivos Impactados

- `../supabase/functions/api/index.ts`
- `lib/services/data_gateway.dart`
- `RELATORIO_DEV.md`

### Validação (Terminal)

- `POST /functions/v1/api/services` -> `200` com `id` UUID válido (`2e1af653-...`).
- `GET /functions/v1/api/service-disputes?...service_id_eq=<id legado não-uuid>` -> `200` com `data: []` (sem erro 500).
- `dart format lib/services/data_gateway.dart` executado.

## 2026-05-02 - Ajuste para envio do app ao backend remoto (fluxo PIX/webhook)

### Alterações Realizadas

- Atualizados scripts remotos para exigir e repassar `BACKEND_API_URL` ao app (via `--dart-define`):
  - `bin/run_web_remote.sh`
  - `bin/run_android_remote.sh`
- Atualizado script local para modo opcional de backend remoto:
  - `bin/run_web_local.sh` agora aceita `USE_REMOTE_BACKEND=true`;
  - nesse modo, exige `BACKEND_API_URL` e injeta `--dart-define=BACKEND_API_URL=...`.
- Objetivo prático:
  - permitir que chamadas canônicas `/api/v1/*` sejam resolvidas no backend online (onde webhook/PIX do Mercado Pago está operacional), sem depender do gateway local durante testes de pagamento real.

### Arquivos Impactados

- `bin/run_web_local.sh`
- `bin/run_web_remote.sh`
- `bin/run_android_remote.sh`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `bash -n bin/run_web_local.sh`
  - `bash -n bin/run_web_remote.sh`
  - `bash -n bin/run_android_remote.sh`
- Resultado:
  - sintaxe dos scripts válida.

## 2026-05-02 - Deploy para Supabase remoto + configuração de BACKEND_API_URL

### Alterações Realizadas

- Executado `supabase db push` para sincronizar migrations no projeto remoto.
- Histórico de migration remoto reparado antes do push:
  - `supabase migration repair --status reverted 20260501233226`
- Executado deploy em lote das Edge Functions existentes (`functions/*` com `index.ts`) para o projeto remoto `mroesvsmylnaxelrhqtl`.
- Atualizado `supabase/.env.deploy` com:
  - `BACKEND_API_URL=https://SEU_BACKEND_ONLINE`

### Resultado do Deploy

- Migrations: remoto atualizado (`Remote database is up to date`).
- Functions: maioria publicada com sucesso.
- Pendência detectada:
  - função `validate-rekognition` falhou no bundle por dependência inválida (`workspace:^` em `@smithy/service-error-classification`).

### Arquivos Impactados

- `../supabase/.env.deploy`
- `RELATORIO_DEV.md`

## 2026-05-02 - Criação de functions listadas sem entrypoint + deploy remoto

### Alterações Realizadas

- Criadas funções faltantes (listadas no projeto Supabase, mas sem `index.ts`) com implementação mínima segura (`501 not_implemented`):
  - `issue-driver-commission-pix`
  - `uber-get-pix-data`
  - `create-trip`
  - `requeue-trip`
  - `update-trip-status`
  - `accept-trip`
  - `cancel-trip`
  - `rate-trip`
  - `uber-payment-intent`
- Cada função nova responde CORS + payload JSON explícito de não implementada, evitando falha estrutural de bundling/deploy por entrypoint ausente.
- Deploy remoto executado com sucesso para todas as funções acima no projeto `mroesvsmylnaxelrhqtl`.

### Arquivos Impactados

- `../supabase/functions/issue-driver-commission-pix/index.ts`
- `../supabase/functions/uber-get-pix-data/index.ts`
- `../supabase/functions/create-trip/index.ts`
- `../supabase/functions/requeue-trip/index.ts`
- `../supabase/functions/update-trip-status/index.ts`
- `../supabase/functions/accept-trip/index.ts`
- `../supabase/functions/cancel-trip/index.ts`
- `../supabase/functions/rate-trip/index.ts`
- `../supabase/functions/uber-payment-intent/index.ts`
- `RELATORIO_DEV.md`

## 2026-05-02 - Hardening de timeout no BackendApiClient (fallback automático de base URL)

### Alterações Realizadas

- Ajustado `BackendApiClient` para usar múltiplos candidatos de base URL em `GET`:
  - base primária (`BACKEND_API_URL` quando definido);
  - fallback para `SUPABASE_URL/functions/v1`.
- Em caso de timeout/erro de rede na base primária, o cliente tenta a base fallback automaticamente antes de desistir.
- Objetivo prático:
  - reduzir falhas de bootstrap (`/api/auth/bootstrap`) quando backend remoto estiver lento/instável;
  - manter app responsivo com caminho alternativo para Edge Functions.

### Arquivos Impactados

- `lib/core/network/backend_api_client.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/network/backend_api_client.dart`
  - `dart analyze lib/core/network/backend_api_client.dart`
- Observação:
  - ambiente apresentou aviso recorrente de telemetria (`FileSystemException` em área read-only) após comando Dart.

## 2026-05-02 - Controle explícito de Supabase remoto no run_web_local.sh

### Alterações Realizadas

- Atualizado `bin/run_web_local.sh` para suportar modo remoto de Supabase.
- Nova flag:
  - `USE_REMOTE_SUPABASE=true`
- Com essa flag ativa, o script **não** usa `supabase status` local para sobrescrever URL/chave;
  - passa a exigir `SUPABASE_URL` e `SUPABASE_ANON_KEY` vindos do ambiente.
- Sem a flag, comportamento anterior permanece (usa Supabase local automaticamente).

### Arquivos Impactados

- `bin/run_web_local.sh`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `bash -n bin/run_web_local.sh`
- Resultado:
  - sintaxe válida.

## 2026-05-02 - Forçar Supabase remoto no run_web_local + diagnóstico de fallback local

- Atualizado `bin/run_web_local.sh` para carregar automaticamente `../supabase/.env.deploy` quando `USE_REMOTE_SUPABASE=true`.
- Diagnóstico atual:
  - `SUPABASE_URL` e `SUPABASE_ANON_KEY` em `.env.deploy` já apontam para o projeto remoto.
  - `BACKEND_API_URL` em `.env.deploy` ainda está como placeholder: `https://SEU_BACKEND_ONLINE`.
- Impacto:
  - Sem `BACKEND_API_URL` real, o app pode continuar com fallback/local em partes do fluxo.
- Execução correta para forçar remoto:
  - `USE_REMOTE_SUPABASE=true USE_REMOTE_BACKEND=true bin/run_web_local.sh`
  - Requer `BACKEND_API_URL` real no `.env.deploy` (endpoint online válido).

## 2026-05-02 - Card expansivel para mapa em Confirmar servico (mobile)

- Arquivo alterado: `lib/features/home/mobile_service_request_review_screen.dart`.
- Mudanca de UX no bloco de mapa:
  - o mapa deixou de ficar sempre visivel;
  - foi encapsulado em um card expansivel/recolhivel;
  - cabecalho com icone + texto `Ver no mapa`;
  - toque no cabecalho alterna entre expandido e recolhido;
  - seta (`chevron`) indica estado atual.
- Implementacao tecnica:
  - adicionada flag de estado `_mapExpanded` (inicial `false`);
  - renderizacao condicional do `SizedBox(height: 280)` com `FlutterMap` apenas quando expandido;
  - mantidos pino central, controles de zoom e fluxo de erro/loading dentro da area expandida.

## 2026-05-02 - Drawer: edição de perfil por toque (foto/nome) + persistência REST

- Arquivos alterados:
  - `lib/widgets/app_drawer.dart`
  - `lib/services/api_service.dart`

- Implementado no menu lateral (perfil):
  - toque na foto abre edição de perfil;
  - toque no nome também abre edição;
  - mantido botão da câmera para trocar avatar.

- Fluxo de edição (100% REST, sem persistência local de negócio):
  - novo método `ApiService.updateMyProfileViaApi(...)` envia JSON autenticado para backend:
    - tentativa principal: `PUT /api/v1/profile/me`
    - fallback: `PUT /api/v1/me`
  - em sucesso:
    - recarrega perfil remoto;
    - atualiza UI do drawer;
    - mostra `Perfil atualizado com sucesso!`.
  - em recusa/erro:
    - mostra mensagem retornada pelo backend (sem mascarar validação/autorização).

- Observação de autenticação:
  - a validação de autenticidade permanece no backend (token Bearer já enviado pelo `BackendApiClient`).

## 2026-05-02 - Tela Confirmar servico: botão azul movido para cima

- Arquivo alterado: `lib/features/home/mobile_service_request_review_screen.dart`.
- Ajuste de ordem dos blocos no `ListView`:
  - botão azul `Confirmar serviço e pagar sinal Pix` movido para logo após o card do serviço (`_taskName`, profissão e preço);
  - bloco `Como funciona` permanece abaixo do botão;
  - card `Ver no mapa` permanece abaixo.
- Objetivo: reduzir rolagem para ação principal de confirmação/pagamento.

## 2026-05-02 - Validação anti-fallback local no run_web_local

- Arquivo alterado: `bin/run_web_local.sh`.
- Adicionada validação para impedir execução remota com placeholder:
  - se `USE_REMOTE_BACKEND=true` e `BACKEND_API_URL=https://SEU_BACKEND_ONLINE`, o script encerra com erro explicativo.
- Objetivo: evitar cair em fallback e confusão de tráfego local/remoto.

## 2026-05-02 - run_web_local: leitura robusta de .env.deploy com valores contendo $

- Arquivo alterado: `bin/run_web_local.sh`.
- Substituído `source .env.deploy` por parser linha-a-linha (`key=value`) com `export` direto.
- Benefício:
  - evita erro de expansão de variável quando o valor contém `$` (ex.: chaves ASAAS);
  - mantém execução remota estável com `USE_REMOTE_SUPABASE=true`.

## 2026-05-02 - Migração REST: createService/getBlockingDispute sem acesso direto de negócio ao Supabase

- Arquivo alterado: `lib/services/api_service.dart`.

### 1) `createService(...)`
- Removida dependência de identidade via leitura direta para escrita de negócio.
- Fluxo agora:
  - resolve identidade do usuário por REST (`GET /api/v1/me`) quando necessário;
  - usa `client_id` e `client_uid` resolvidos;
  - cria serviço por REST (`POST /api/v1/services`) como caminho canônico.
- Mantida validação de disputa bloqueante antes da criação.

### 2) `getBlockingDisputeForCurrentClient()`
- Mantido 100% REST:
  - resolve user por `GET /api/v1/me` quando `_userId` está nulo;
  - consulta disputa por `GET /api/v1/service-disputes?...`.

### 3) `reverseGeocode/searchAddress`
- Permanecem via Edge Function HTTP (`geo` e `geo/search`) pelo `ApiGeoService`.
- Não fazem query/insert direto em tabela no app.

### 4) `loadToken()`
- Mantido como gestão de sessão/local auth (sem escrita de regra de negócio).

## 2026-05-02 - Fix crítico: serviço sumindo da tela de tracking por not_found transitório

- Arquivo alterado: `lib/features/client/service_tracking_page.dart`.
- Problema:
  - sinais transitórios de `not_found` (realtime/polling) estavam redirecionando imediatamente para `/home`.
- Correção aplicada:
  - adicionada proteção com contador `_consecutiveNotFoundSignals`;
  - só redireciona para Home após **3 sinais consecutivos** de `not_found`;
  - nos primeiros sinais, força refresh (`_refreshNow`) para confirmar estado real;
  - ao receber snapshot válido novamente, contador é resetado para `0`.
- Resultado esperado:
  - evita sumiço repentino do serviço durante atualização de tela/rebuild/oscilações de sincronização.

## 2026-05-02 - Blindagem 2: persistir/restaurar serviceId ativo no tracking

- Arquivos alterados:
  - `lib/features/client/service_tracking_page.dart`
  - `lib/widgets/scaffold_with_nav_bar.dart`

### O que foi implementado
- Ao carregar/atualizar o serviço no tracking, o app agora chama:
  - `ClientTrackingService.syncTrackingForService(...)`
- Isso persiste contexto do serviço ativo (serviceId/user/session) para recuperação.

- Em `ScaffoldWithNavBar`, foi adicionada restauração automática para cliente:
  - se estiver em `/home` (ou `/login`) e existir `activeServiceId` persistido;
  - redireciona automaticamente para `/service-tracking/:id`.

### Resultado esperado
- Em reload do web ou retorno inesperado para Home, o usuário volta automaticamente para o tracking do serviço ativo, evitando sensação de “serviço sumiu”.

## 2026-05-02 - Restauração de tracking vinculada à sessão do cliente

- Arquivos alterados:
  - `lib/services/client_tracking_service.dart`
  - `lib/widgets/scaffold_with_nav_bar.dart`

- Implementado método novo:
  - `ClientTrackingService.activeServiceIdForCurrentSession()`
  - valida `serviceId` salvo + `userUid` persistido + `currentUser.id` autenticado.
  - só retorna serviceId quando pertence à mesma sessão ativa.

- Ajuste de navegação automática:
  - `ScaffoldWithNavBar` agora usa `activeServiceIdForCurrentSession()` (em vez de `activeServiceId()` simples).

- Resultado:
  - reload/navegação volta para `/service-tracking/:id` apenas para o cliente dono da sessão;
  - evita redirecionamento indevido entre sessões/usuários diferentes.

## 2026-05-02 - Configuração permanente para `flutter run` usar Supabase remoto

- Arquivos alterados:
  - `.env`
  - `assets/env/app.env`

- Alterações:
  - `SUPABASE_URL` trocado de local (`127.0.0.1`) para remoto (`https://mroesvsmylnaxelrhqtl.supabase.co`).
  - `SUPABASE_ANON_KEY` atualizado para a chave anon do projeto remoto.
  - `BACKEND_API_URL` atualizado para `https://mroesvsmylnaxelrhqtl.supabase.co/functions/v1`.

- Efeito:
  - execução via `flutter run` (sem scripts auxiliares) passa a consumir Supabase remoto por padrão.

## 2026-05-02 - Liberação de cancelamento na fase de pagamento (PIX)

- Arquivo alterado: `lib/features/client/service_tracking_page.dart`.
- Ajuste:
  - no card `TrackingPaymentPendingStep`, o bloqueio por proximidade (`cancelBlockedByProximity`) passa a ser ignorado quando `inSecurePaymentPhase == true`.
- Efeito:
  - botão `CANCELAR (SEM CUSTO)` permanece habilitado durante a etapa de pagamento/entrada;
  - ação chama `_cancelService()` e segue cancelamento via API.

## 2026-05-02 - Modal de confirmação antes de cancelar serviço

- Arquivo alterado: `lib/features/client/service_tracking_page.dart`.
- Ajuste implementado:
  - antes de executar `_cancelService`, abre `AlertDialog` com confirmação:
    - título: `Cancelar serviço`
    - mensagem: `Tem certeza que deseja cancelar este serviço?`
    - ações: `Voltar` e `Cancelar serviço`.
- Comportamento:
  - só chama API de cancelamento quando o usuário confirma explicitamente.

## 2026-05-02 - Persistir tracking também com pagamento pendente (Ctrl+R)

- Arquivo alterado: `lib/services/client_tracking_service.dart`.
- Ajuste em `syncTrackingForService`:
  - antes: só persistia contexto quando `payment_status` estava `paid/partially_paid`.
  - agora: também persiste quando status do serviço está em fase ativa pré-pagamento:
    - `waiting_payment`
    - `pending_payment`
    - `awaiting_payment`
- Efeito esperado:
  - ao dar `Ctrl+R`, o app restaura `/service-tracking/:id` mesmo com pagamento pendente, ajudando o cliente a concluir o serviço.

## 2026-05-02 - Fix bootstrap 401: Authorization com anon key no BackendApiClient

- Arquivo alterado: `lib/core/network/backend_api_client.dart`.
- Ajuste em `buildHeaders()`:
  - quando não há token de sessão do usuário, agora envia:
    - `Authorization: Bearer <SUPABASE_ANON_KEY>`
  - mantém envio de `apikey` normalmente.
- Objetivo:
  - evitar `401 UNAUTHORIZED_NO_AUTH_HEADER` em endpoints de bootstrap (`/api/auth/bootstrap`) durante inicialização sem sessão autenticada.

## 2026-05-02 - Trava de rota no tracking: evitar redirecionamento automático para Home

- Arquivo alterado: `lib/features/client/service_tracking_page.dart`.
- Implementado helper `_shouldPinTrackingRoute()`:
  - fixa a tela/URL `/service-tracking/:id` enquanto o serviço estiver ativo;
  - considera ativo inclusive status de pagamento pendente.

- Proteções aplicadas:
  - `_handleServiceNotFound()`:
    - se rota está fixada, não redireciona para Home; força refresh e permanece na tela.
  - `_handleOpenForScheduleFallback()`:
    - se rota está fixada, não redireciona.
  - redirecionamento automático pós-conclusão:
    - só ocorre quando `_shouldPinTrackingRoute()` permitir.

- Resultado esperado:
  - URL de tracking permanece ativa e não volta sozinha para `/home` após alguns segundos enquanto serviço estiver pendente/ativo.

## 2026-05-02 - Fix refresh web: retry de restauração do tracking ativo

- Arquivo alterado: `lib/widgets/scaffold_with_nav_bar.dart`.
- Problema observado:
  - após `refresh` no navegador, app caía em `/home` e não redirecionava para `/service-tracking/:id`.
  - causa: sessão/auth Supabase ainda não hidratada no primeiro check.

- Correção:
  - adicionado retry automático em `_restoreActiveTrackingIfNeeded()`:
    - até 8 tentativas;
    - intervalo de 700ms;
    - só marca `_restoreChecked=true` quando encontra serviço ativo da sessão ou esgota tentativas.

- Resultado esperado:
  - ao dar refresh em `/home`, se houver serviço ativo da sessão, o app redireciona para tracking após poucos instantes.

## 2026-05-02 - Backend canônico de tracking ativo no Supabase (`api`)

- Arquivo alterado: `../supabase/functions/api/index.ts`.
- Deploy realizado: `supabase functions deploy api` no projeto `mroesvsmylnaxelrhqtl`.

### Mudanças implementadas
- Adicionada lógica de serviço ativo por usuário (`fetchLatestActiveServiceForUser`):
  - consulta `service_requests` por `client_id` (mais recentes);
  - retorna o primeiro com status ativo/pendente (inclui `waiting_payment`, `pending_payment`, `accepted`, `in_progress`, etc.).

- Endpoint `GET /api/v1/tracking/active-service`:
  - antes: retornava sempre `activeService: null`.
  - agora: retorna `activeService` real da sessão autenticada quando existir.

- Endpoint `GET /api/v1/auth/bootstrap`:
  - agora calcula `nextRoute` com base em serviço ativo.
  - quando existir serviço ativo: `nextRoute=/service-tracking/:id`.
  - sem serviço ativo: mantém `/home` (ou `/login` sem autenticação).

### Resultado esperado
- Refresh/nova navegação em cliente autenticado com serviço ativo deve voltar automaticamente para o tracking canônico.

## 2026-05-02 - Fix deploy `validate-rekognition`

- Arquivo alterado: `../supabase/functions/validate-rekognition/index.ts`.
- Problema:
  - deploy falhava por resolução de dependência com `workspace:^` em cadeia do AWS SDK.
- Ação:
  - ajustado import do Rekognition para versão estável:
    - `npm:@aws-sdk/client-rekognition@3.515.0`
- Resultado:
  - `supabase functions deploy validate-rekognition` concluído com sucesso no projeto remoto `mroesvsmylnaxelrhqtl`.

## 2026-05-02 - API gateway: habilitado POST /tracking/services/:id/cancel

- Arquivo alterado: `../supabase/functions/api/index.ts`.
- Implementada rota:
  - `POST /api/v1/tracking/services/:id/cancel`
- Comportamento:
  - valida autenticação;
  - valida se o serviço pertence ao usuário autenticado (`client_id == appUser.id`);
  - atualiza `service_requests.status = cancelled` e `status_updated_at`;
  - retorna payload canônico `{ success: true, service: ... }`.
- Deploy realizado:
  - `supabase functions deploy api` no projeto remoto `mroesvsmylnaxelrhqtl`.

## 2026-05-02 - Removida seta de voltar da tela Status do Serviço

- Arquivo alterado: `lib/features/client/service_tracking_page.dart`.
- Alteração:
  - removido `IconButton` de voltar (`arrow_back`) do header da tela de tracking.
- Objetivo:
  - impedir saída manual via seta, mantendo o fluxo principal em pagar ou cancelar serviço.

## 2026-05-02 - Persistência de serviço ativo para retorno automático ao tracking

### Alterações Realizadas

- Implementado fallback de persistência local do serviço ativo do cliente no `GoRouter redirect`.
- Em `main.dart`:
  - adicionado uso de `SharedPreferences` com a chave `last_client_active_service_id`;
  - quando há serviço ativo resolvido no redirect, o `serviceId` é salvo localmente;
  - quando não há serviço ativo, o cache é limpo para evitar retorno indevido;
  - ao abrir/recarregar em `/` ou `/home`, se existir `serviceId` salvo, o app redireciona para `/service-tracking/:serviceId`.
- Efeito prático:
  - melhora a continuidade do fluxo do cliente após recarregar a página web ou reabrir o app, priorizando o retorno ao serviço ativo.

### Arquivos Impactados

- `lib/main.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/main.dart`
  - `dart analyze lib/main.dart lib/core/navigation/app_redirect_resolver.dart lib/core/utils/mobile_client_navigation_gate.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`

## 2026-05-02 - Correção de crash no login (setState com widget inativo)

### Alterações Realizadas

- Corrigido possível crash na tela de login com erro:
  - `'_ElementLifecycle.inactive': is not true`
- Em `LoginScreen`:
  - adicionado `if (!mounted) return;` no callback `PopScope.onPopInvokedWithResult` antes de qualquer `setState`.
- Ajuste complementar de análise:
  - removido uso desnecessário de operador null-aware em `row?['...']` após checagem de null em `_checkCpfAndRedirect`.

### Arquivos Impactados

- `lib/features/auth/login_screen.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/auth/login_screen.dart`
  - `dart analyze lib/features/auth/login_screen.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`

## 2026-05-02 - Compatibilidade de endpoints backend (404/405 no emulador)

### Alterações Realizadas

- Ajustado fallback de rotas para reduzir erros de contrato entre app e backend atual.
- Em `ProviderPresenceService.sendHeartbeatWithCoords`:
  - mantido `POST /api/v1/providers/heartbeat` como primeira tentativa;
  - adicionado fallback para `PUT /api/v1/providers/heartbeat` quando o backend não aceita POST.
- Em `ApiService.getAvailableServices`:
  - mantida tentativa em `/api/v1/services/available`;
  - adicionado fallback para `/api/v1/dispatch/offers/active` quando a rota legada não existir.
- Em `ApiService.getAvailableForSchedule`:
  - mantida tentativa em `/api/v1/providers/schedule/available`;
  - adicionado fallback para `/api/v1/providers/{userId}/availability` quando a rota legada não existir.

### Arquivos Impactados

- `lib/services/provider_presence/provider_presence_service.dart`
- `lib/services/api_service.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/services/api_service.dart lib/services/provider_presence/provider_presence_service.dart`
  - `dart analyze lib/services/api_service.dart lib/services/provider_presence/provider_presence_service.dart`
- Resultado:
  - Sem erros novos de compilação.
  - Permanecem 3 warnings antigos (`unused_catch_clause`) em `api_service.dart` fora do escopo deste ajuste.

## 2026-05-02 - Bootstrap backend-first para redirecionar direto ao serviço ativo

### Alterações Realizadas

- Reforçado o fluxo de abertura do app para consultar serviço ativo no backend (banco) antes de renderizar a Home.
- Em `AppBootstrapCoordinator`:
  - adicionado `BackendTrackingApi` no bootstrap;
  - quando usuário está logado com role `client`, o app chama `GET /api/v1/tracking/active-service` durante a inicialização;
  - se houver serviço ativo, o `activeService` é injetado no `AppBootstrapRouteResolver` e o `initialLocation` já nasce em rota ativa (`/service-tracking/:id` ou rota correspondente), sem etapa visual intermediária na Home.
- Efeito prático:
  - ao recarregar/reabrir app, o redirecionamento vem do estado persistido no banco/API e acontece imediatamente no bootstrap.

### Arquivos Impactados

- `lib/core/bootstrap/app_bootstrap_coordinator.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/core/bootstrap/app_bootstrap_coordinator.dart`
  - `dart analyze lib/core/bootstrap/app_bootstrap_coordinator.dart lib/core/navigation/app_navigation_policy.dart lib/core/tracking/backend_tracking_api.dart`
- Resultado:
  - Flutter/Dart: `No issues found!`

## 2026-05-02 - Modal de oferta do prestador via API JSON (sem stream direto Supabase)

### Alterações Realizadas

- Ajustado `ProviderHomeMobile` para fluxo backend-first nas ofertas de serviço.
- Removido uso ativo de streams diretos do Supabase para:
  - vitrine de serviços (`service_requests_new` stream);
  - notificações de oferta (`notificacao_de_servicos` stream).
- `ProviderHomeMobile` agora depende de chamadas API JSON já existentes:
  - refresh por `_loadData()` (`getAvailableServices` / `getAvailableForSchedule`);
  - detecção de oferta por polling canônico (`_pollOffersFallback`) e abertura de `ServiceOfferModal`.
- Efeito prático:
  - após confirmação de PIX + mudança de status para busca/dispatch, o prestador passa a receber oportunidade pelo caminho API JSON, sem depender de assinatura direta no Supabase nessa tela.

### Arquivos Impactados

- `lib/features/provider/provider_home_mobile.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart format lib/features/provider/provider_home_mobile.dart`
  - `dart analyze lib/features/provider/provider_home_mobile.dart`
- Resultado:
  - Sem erros de compilação.
  - Restaram apenas warnings de funções não usadas (legado da remoção de stream direto), sem impacto funcional.

## 2026-05-02 - Webhook Mercado Pago para confirmação real de PIX (backend API)

### Alterações Realizadas

- Implementada rota canônica no backend API:
  - `POST /api/v1/payments/webhook/mercadopago`
- Fluxo da rota:
  - recebe notificação do Mercado Pago (`payment id`);
  - consulta pagamento real em `https://api.mercadopago.com/v1/payments/{id}` usando `MERCADO_PAGO_ACCESS_TOKEN`;
  - extrai `serviceId` via `external_reference` (ou `metadata.service_id`);
  - quando status for `approved`, atualiza `service_requests.status` para `searching_provider` e `status_updated_at`.
- A rota retorna `ok` também em cenários não críticos (topic não suportado, pagamento ainda não aprovado), para evitar retries agressivos desnecessários.

### Arquivos Impactados

- `supabase/functions/api/index.ts`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `deno check supabase/functions/api/index.ts`
- Resultado:
  - o arquivo já possuía erros de tipagem preexistentes em outras seções (`Deno.serve` overload e tipagem de `task["name"]`), fora do escopo desta alteração;
  - não houve indicação de erro novo específico no bloco do webhook implementado.

## 2026-05-02 - Alinhamento final Mercado Pago (token + webhook canônico + referência de serviço)

### Alterações Realizadas

- `mp-process-payment` atualizado para aceitar secret principal `MERCADO_PAGO_ACCESS_TOKEN` (com fallback para `MP_ACCESS_TOKEN`).
- `mp-process-payment` passou a usar como padrão de `notification_url` o webhook canônico da API:
  - `/functions/v1/api/api/v1/payments/webhook/mercadopago`
  - ainda respeita `MP_WEBHOOK_URL` quando definido explicitamente.
- `mp-process-payment` reforçado com `metadata.service_id = entityId`.
- `mp-process-payment` já usava `external_reference: entityId`; mantido.
- `api` webhook atualizado para aceitar também fallback de token `MP_ACCESS_TOKEN`.

### Arquivos Impactados

- `supabase/functions/mp-process-payment/index.ts`
- `supabase/functions/api/index.ts`
- `RELATORIO_DEV.md`

### Validação

- Validação funcional por inspeção de payload e variáveis de ambiente.
- Observação: `index.ts` da função `api` já tinha erros de tipagem preexistentes fora do escopo do webhook.

## 2026-05-02 - PIX decision-complete: webhook canônico + persistência de pagamento + gatilho de UI por status

### Alterações Realizadas

- Correção de roteamento e duplicidade no backend `api`:
  - removido bloco duplicado legado de `POST /payments/webhook/mercadopago` que estava competindo com a rota canônica;
  - mantida rota canônica pública (GET/POST compatível) com resposta diagnóstica (`dispatchTriggered`, `dispatchDetail`).
- Correção no `mp-process-payment`:
  - adicionado hard-fail para persistência em `public.payments`;
  - quando `insert` em `payments` falha, agora retorna erro explícito (`PAYMENT_PERSIST_FAILED`) e grava log técnico em `payment_transaction_logs`.
- Correção de UI no cliente (`ServiceTrackingPage`):
  - o estado `searching_provider` (e equivalentes de busca) agora ativa `entryPaid` operacional mesmo sem `payment_status` disponível na linha de serviço;
  - evita ficar preso no card de PIX após backend já ter migrado para busca de prestador.
- Deploy remoto executado:
  - `api` e `mp-process-payment` publicados no projeto `mroesvsmylnaxelrhqtl`.

### Arquivos Impactados

- `supabase/functions/api/index.ts`
- `supabase/functions/mp-process-payment/index.ts`
- `mobile_app/lib/features/client/service_tracking_page.dart`
- `RELATORIO_DEV.md`

### Validação

- Executado:
  - `dart analyze mobile_app/lib/features/client/service_tracking_page.dart`
  - `supabase functions deploy api --no-verify-jwt`
  - `supabase functions deploy mp-process-payment`
- Resultado:
  - Flutter/Dart: `No issues found!`
  - Deploy remoto concluído com sucesso.

## 2026-05-02 - PIX decision complete via API JSON (webhook + persistência + gatilho de status)

### Alterações Realizadas

- Backend `mp-process-payment` consolidado com falha explícita na persistência financeira:
  - validação de `insertRes.error` ao inserir em `public.payments`;
  - retorno de erro explícito com `reason_code=PAYMENT_PERSIST_FAILED` e `trace_id`;
  - log estruturado em `payment_transaction_logs` com contexto (`service_id/trip_id`, `mp_payment_id`, `payment_stage`, `token_source`).
- Backend `api` (webhook Mercado Pago) consolidado como fonte operacional:
  - mantém compatibilidade com `POST` real e `GET topic/id` para simulação;
  - no `approved`, atualiza `service_requests.status=searching_provider` e `status_updated_at`;
  - dispara `dispatch` com `serviceId` (formato esperado) e fallback de secret (`SUPABASE_SERVICE_ROLE_KEY || PROJECT_SERVICE_KEY`);
  - resposta diagnóstica padronizada com `trace_id`, `serviceId`, `paymentId`, `paymentStatus`, `dispatchTriggered`, `dispatchDetail`;
  - adicionada observabilidade em `service_logs` para transição aprovada e resultado do dispatch.
- Frontend cliente (`ServiceTrackingPage`) mantido com gatilho principal por `status` vindo da API:
  - status de busca (`searching_provider` e equivalentes) prevalece sobre estado visual de PIX pendente;
  - transição automática para `/service-busca-prestador-movel/:serviceId` no ciclo de polling/render.

### Deploy Remoto

- Executado deploy para o projeto remoto `mroesvsmylnaxelrhqtl`:
  - `supabase functions deploy api --no-verify-jwt`
  - `supabase functions deploy mp-process-payment`

### Arquivos Impactados

- `../supabase/functions/api/index.ts`
- `../supabase/functions/mp-process-payment/index.ts`
- `lib/features/client/service_tracking_page.dart`
- `RELATORIO_DEV.md`

## 2026-05-02 - Reforço de segurança financeira PIX (reconciliação obrigatória no webhook)

### Alterações Realizadas

- `supabase/functions/api/index.ts` atualizado para reforço de trilha financeira:
  - adicionado mapeamento canônico de status MP -> status local de pagamento (`paid/pending/cancelled`);
  - webhook `/payments/webhook/mercadopago` agora sempre reconcilia `public.payments` por `external_payment_id`/`mp_payment_id` antes do fluxo de serviço;
  - atualização obrigatória de colunas financeiras: `status`, `provider`, `payment_method_id`, `payment_method`, `payer_email`, `mp_response`, `raw_response`, `updated_at`, e `service_id` quando disponível;
  - mantido `trace_id` no retorno para auditoria.
- Ajustado fechamento de bloco em `fetchLatestActiveServiceForUser` para estabilizar build/deploy.

### Deploy Remoto

- Executado com sucesso:
  - `supabase functions deploy api --no-verify-jwt`

### Arquivos Impactados

- `../supabase/functions/api/index.ts`
- `RELATORIO_DEV.md`

## 2026-05-02 - Camada anti-duplicidade e anti-regressão em pagamentos PIX

### Alterações Realizadas

- `mp-process-payment` reforçado com proteção de cobrança duplicada:
  - idempotency key estável por contexto (`entityId + paymentMethod + paymentStage + amount`), removendo variação por timestamp;
  - antes de criar novo pagamento no MP, consulta `public.payments` por entidade/método com status `pending|paid`;
  - se já existir cobrança ativa, reutiliza e retorna dados existentes (incluindo payload/QR PIX), sem criar nova cobrança.
- `api` webhook reforçado para consistência de status:
  - evita regressão de status financeiro (não rebaixa `paid` para `pending/cancelled` por evento tardio);
  - se receber webhook e não encontrar linha em `payments`, cria registro mínimo para não perder trilha financeira;
  - mantém reconciliação de `mp_response/raw_response` e ids externos.

### Deploy Remoto

- `supabase functions deploy mp-process-payment`
- `supabase functions deploy api --no-verify-jwt`

### Arquivos Impactados

- `../supabase/functions/mp-process-payment/index.ts`
- `../supabase/functions/api/index.ts`
- `RELATORIO_DEV.md`

## 2026-05-02 - Proteção de banco anti-duplicidade PIX por serviço

### Alterações Realizadas

- Criada migração SQL de proteção transacional no banco:
  - `supabase/migrations/20260502153000_payments_unique_pending_pix_per_service.sql`
- Regra aplicada:
  - índice único parcial `ux_payments_service_pending_pix` em `public.payments(service_id)`
  - escopo: `provider='mercado_pago'`, método PIX (`pix`/`pix_app`) e `status='pending'`
- Efeito:
  - garante no banco que não exista mais de uma cobrança PIX pendente para o mesmo `service_id`, mesmo sob corrida extrema de requisições/retries.

### Deploy Banco Remoto

- Executado com sucesso:
  - `supabase db push`
  - migração aplicada: `20260502153000_payments_unique_pending_pix_per_service.sql`

### Arquivos Impactados

- `../supabase/migrations/20260502153000_payments_unique_pending_pix_per_service.sql`
- `RELATORIO_DEV.md`

## 2026-05-02 - Correção FK payments.service_id x service_requests (erro 500 no mp-get-pix-data)

### Alterações Realizadas

- Corrigida causa do erro `Falha ao registrar pagamento em public.payments` durante geração de PIX.
- Contexto técnico:
  - `public.payments.service_id` possui FK para `service_requests_new`.
  - fluxo operacional atual usa `service_requests`.
  - inserir `service_id` de `service_requests` em `payments` gerava violação de FK e retorno 500.
- Ajustes aplicados:
  - `mp-process-payment`: só preenche `payments.service_id` quando a fonte canônica for `service_requests_new`.
  - quando fonte for `service_requests`, grava `service_id = null` e preserva rastreabilidade em `payments.metadata.canonical_service_id` + `canonical_source`.
  - `api` webhook: mesma regra para update/insert de reconciliação, com checagem de existência em `service_requests_new`.

### Deploy Remoto

- `supabase functions deploy mp-process-payment`
- `supabase functions deploy api --no-verify-jwt`

### Arquivos Impactados

- `../supabase/functions/mp-process-payment/index.ts`
- `../supabase/functions/api/index.ts`
- `RELATORIO_DEV.md`

## 2026-05-02 - Hotfix PIX: coluna billing_type inexistente no payments remoto

### Alterações Realizadas

- Corrigido `mp-process-payment` para compatibilidade com schema remoto de `public.payments`.
- Antes: insert enviava `billing_type` (coluna inexistente no ambiente atual), causando `PAYMENT_PERSIST_FAILED`.
- Agora: grava `payment_type` no lugar de `billing_type`.

### Deploy Remoto

- `supabase functions deploy mp-process-payment`

### Arquivos Impactados

- `../supabase/functions/mp-process-payment/index.ts`
- `RELATORIO_DEV.md`

## 2026-05-02 - Hotfix adicional PIX: settlement_status/billing_type incompatíveis com payments remoto

### Alterações Realizadas

- Corrigido `mp-process-payment` para evitar novas falhas de persistência por colunas inexistentes no schema remoto de `public.payments`.
- Ajustes:
  - `settlement_status` -> `settlement_category` (mapeado por status MP)
  - `billing_type` (fluxo de crédito de cancelamento) -> `payment_type`

### Deploy Remoto

- `supabase functions deploy mp-process-payment`

### Arquivos Impactados

- `../supabase/functions/mp-process-payment/index.ts`
- `RELATORIO_DEV.md`

## 2026-05-02 - Hotfix webhook PIX: fallback de serviceId via ledger payments

### Alterações Realizadas

- `api` webhook Mercado Pago ganhou fallback para resolver `serviceId` quando `external_reference/metadata` não vierem no payload consultado do MP.
- Nova estratégia:
  - busca em `public.payments` por `external_payment_id`/`mp_payment_id`;
  - usa `service_id` da linha, ou `metadata.canonical_service_id` como fallback;
  - com isso, mantém transição de status `waiting_payment -> searching_provider` mesmo em payload MP incompleto.

### Deploy Remoto

- `supabase functions deploy api --no-verify-jwt`

### Arquivos Impactados

- `../supabase/functions/api/index.ts`
- `RELATORIO_DEV.md`

## 2026-05-02 - Correção crítica: dispatch compatível com service_requests (fluxo móvel)

### Alterações Realizadas

- Causa raiz do "não chamou prestador" identificada no `dispatch`:
  - função consultava apenas `service_requests_new`,
  - elegibilidade dependia de `payment_status=paid` e status legados (`pending/searching/open_for_schedule`),
  - fluxo móvel atual usa `service_requests` + status `searching_provider`.
- Correções aplicadas em `supabase/functions/dispatch/index.ts`:
  - `loadDispatchService()` agora faz fallback para `service_requests` quando não achar em `service_requests_new`;
  - para registro vindo de `service_requests`, injeta `payment_status='paid'` para elegibilidade operacional;
  - `isDispatchEligible()` agora aceita `status='searching_provider'` como pago por status;
  - `markServiceSearching()` faz update primário em `service_requests_new` e fallback para `service_requests` (mantendo `searching_provider`).

### Deploy Remoto

- `supabase functions deploy dispatch`

### Arquivos Impactados

- `../supabase/functions/dispatch/index.ts`
- `RELATORIO_DEV.md`

## 2026-05-02 - Compat API prestador: services/available + providers/schedule/available + heartbeat

### Alterações Realizadas

- Implementadas rotas faltantes no `api` para compatibilidade com o app do prestador:
  - `POST /api/providers/heartbeat`
  - `GET /api/services/available`
  - `GET /api/providers/schedule/available`
- `services/available` agora busca em `notificacao_de_servicos` por `provider_user_id` autenticado e anexa dados do serviço de `service_requests`.
- `providers/schedule/available` retorna lista disponível de notificações para o prestador.
- `providers/heartbeat` responde sucesso e mantém pulso de vida do usuário autenticado.

### Deploy Remoto

- `supabase functions deploy api --no-verify-jwt`

### Arquivos Impactados

- `../supabase/functions/api/index.ts`
- `RELATORIO_DEV.md`

## 2026-05-02 - Hotfix prestador: notificacao_de_servicos sem created_at + rotas de compatibilidade

### Alterações Realizadas

- Corrigido erro 500 em rotas do prestador causado por ordenação em coluna inexistente:
  - `GET /api/services/available`
  - `GET /api/providers/schedule/available`
- Antes: `order by created_at` (coluna inexistente em `notificacao_de_servicos`).
- Agora: `order by queue_order`.
- Adicionadas rotas de compatibilidade para reduzir falhas no app prestador:
  - `GET /api/home/provider` (snapshot mínimo)
  - `POST /api/remote-ui/get-screen` (payload mínimo compatível)

### Deploy Remoto

- `supabase functions deploy api --no-verify-jwt`

### Arquivos Impactados

- `../supabase/functions/api/index.ts`
- `RELATORIO_DEV.md`

## 2026-05-02 - Compat runtime notificações: registro_de_notificações vs notificacao_de_servicos

### Alterações Realizadas

- Causa de fila vazia identificada: ambiente remoto usa tabela `registro_de_notificações` (acentuada), enquanto funções usavam `notificacao_de_servicos`.
- Aplicado fallback dinâmico nas funções `dispatch` e `api`:
  - tenta `registro_de_notificações`
  - depois `registro_de_notificacoes`
  - depois `notificacao_de_servicos`
- Fluxos afetados e corrigidos:
  - materialização da fila de prestadores no dispatch
  - leitura de serviços disponíveis para prestador
  - leitura de agenda disponível para prestador
  - snapshot de home prestador (contador de disponíveis)

### Deploy Remoto

- `supabase functions deploy dispatch`
- `supabase functions deploy api --no-verify-jwt`

### Arquivos Impactados

- `../supabase/functions/dispatch/index.ts`
- `../supabase/functions/api/index.ts`
- `RELATORIO_DEV.md`

## 2026-05-02 - Fix dispatch: service_requests sem profession_id

### Alterações Realizadas

- Corrigida incompatibilidade de schema no dispatch para fluxo `service_requests`.
- Causa raiz:
  - `service_requests` não possui coluna `profession_id`.
  - dispatch tentava selecionar esse campo, quebrando lookup do serviço e impedindo materialização da fila.
- Ajuste aplicado:
  - leitura de `service_requests` passou a usar `task_id/category_id/profession`;
  - `profession_id` agora é resolvido via `task_catalog.profession_id` com base em `task_id`;
  - fallback mantém fluxo operacional sem depender de coluna inexistente.

### Deploy Remoto

- `supabase functions deploy dispatch`

### Arquivos Impactados

- `../supabase/functions/dispatch/index.ts`
- `RELATORIO_DEV.md`

## 2026-05-02 - Fallback dispatch sem filtro de profissão quando RPC retorna vazio

### Alterações Realizadas

- Ajustado `dispatch` para evitar fila zerada quando `find_nearby_providers_v2` não retorna candidatos com `profession_id`.
- Nova lógica em `loadNearbyProviders(...)`:
  - tentativa primária com `p_profession_id` resolvido;
  - se retornar vazio e houver profissão, tentativa fallback com `p_profession_id = null`;
  - logs operacionais para auditoria:
    - `DISPATCH_PROVIDER_RPC_FALLBACK_USED`
    - `DISPATCH_PROVIDER_RPC_FALLBACK_ERROR`
- Mantido raio de busca e ordenação por proximidade.

### Deploy Remoto

- `supabase functions deploy dispatch`

### Arquivos Impactados

- `../supabase/functions/dispatch/index.ts`
- `RELATORIO_DEV.md`

## 2026-05-02 - Dispatch por profissão usando `provider_professions` (correção de fila vazia)

### Alterações Realizadas

- Corrigida a seleção de prestadores no Edge Function de dispatch para usar a fonte canônica de profissão confirmada em produção:
  - `provider_professions` para elegibilidade por `profession_id`.
- Substituída a dependência exclusiva de `find_nearby_providers_v2` por montagem direta da lista de candidatos com:
  - `provider_professions` (profissão do prestador),
  - `users` (`is_active`, `is_online`, `fcm_token`),
  - `provider_locations` (última localização).
- Implementado cálculo de distância (Haversine) no próprio dispatch e ordenação por menor distância.
- Mantido filtro estrito por profissão:
  - se o serviço for chaveiro (`profession_id=1`), somente prestadores com `provider_professions.profession_id=1` entram na fila.
- Mantido filtro de raio (`SEARCH_RADIUS_KM = 50`) e exclusão de prestadores sem token FCM.

### Arquivos Impactados

- `/home/servirce/Documentos/101/projeto-central-/supabase/functions/dispatch/index.ts`
- `RELATORIO_DEV.md`

### Validação

- Validação lógica realizada sobre o fluxo de montagem da fila com os dados apresentados no ambiente de produção.
- Próximo passo operacional: publicar a função `dispatch` atualizada e retestar um serviço em `searching_provider`.

## 2026-05-02 - Diagnóstico detalhado no `loadDispatchService` (dispatch)

### Alterações Realizadas

- Aplicado patch curto para diagnóstico objetivo de falhas na carga do serviço no Edge Function `dispatch`.
- `loadDispatchService(...)` agora retorna também um objeto `diagnostic` com:
  - fonte consultada (`service_requests_new` ou `service_requests`),
  - erro em `service_requests_new`,
  - erro em `service_requests`,
  - erro em `task_catalog` ao resolver `profession_id`.
- Quando o serviço não é encontrado:
  - a função grava `DISPATCH_SERVICE_LOOKUP_FAILED` em `service_logs` com o diagnóstico;
  - a resposta HTTP `404` inclui `diagnostic` no body para depuração imediata.

### Arquivos Impactados

- `/home/servirce/Documentos/101/projeto-central-/supabase/functions/dispatch/index.ts`
- `RELATORIO_DEV.md`

### Validação

- Patch aplicado com sucesso no arquivo da função.
- Próximo passo: publicar novamente `dispatch` e repetir `POST /functions/v1/dispatch` para receber o erro exato no payload de resposta.

## 2026-05-02 - Compatibilidade de schema no dispatch (colunas ausentes)

### Alterações Realizadas

- Ajustadas queries do `dispatch` para não depender de colunas ausentes no remoto:
  - removido `total_price` do `select` em `service_requests_new`.
  - removido `dispatch_started_at` e `total_price` do `select` em `service_requests`.
- Ajustado `markServiceSearching` para fallback legado sem `dispatch_started_at/dispatch_round` em `service_requests`.

### Arquivos Impactados

- `/home/servirce/Documentos/101/projeto-central-/supabase/functions/dispatch/index.ts`
- `RELATORIO_DEV.md`


## 2026-05-02 - Dispatch: online por atividade recente + fallback `driver_locations`

### Alterações Realizadas

- Atualizado o filtro de elegibilidade de prestador no `dispatch` para não depender somente de `users.is_online=true`.
- Incluída lógica de online por atividade recente (`ONLINE_WINDOW_MINUTES = 15`) usando:
  - `provider_locations.updated_at`,
  - `driver_locations.updated_at`,
  - `users.updated_at`.
- Incluído fallback de localização:
  - além de `provider_locations`, o dispatch agora também considera `driver_locations`.
- Mantida ordenação por distância e filtro por profissão (`provider_professions`).

### Arquivos Impactados

- `/home/servirce/Documentos/101/projeto-central-/supabase/functions/dispatch/index.ts`
- `RELATORIO_DEV.md`

### Validação

- Deploy realizado com sucesso.
- Teste do dispatch retornou `success=true` porém `queued=0`, indicando ausência de prestadores com atividade recente dentro da janela configurada.

## 2026-05-02 - Heartbeat do prestador atualiza presença + localização

### Alterações Realizadas

- Corrigido endpoint `POST /providers/heartbeat` no Edge Function `api`.
- Antes: atualizava apenas `users.updated_at`.
- Agora:
  - marca `users.is_online = true`;
  - atualiza `users.last_seen_at` e `users.updated_at`;
  - quando recebe coordenadas (`latitude/longitude` ou `lat/lon`), faz upsert em:
    - `provider_locations` (`provider_id`),
    - `driver_locations` (`driver_id`) para compatibilidade com legado.
- Resposta do endpoint passou a indicar `hasCoords` para facilitar diagnóstico.

### Arquivos Impactados

- `/home/servirce/Documentos/101/projeto-central-/supabase/functions/api/index.ts`
- `RELATORIO_DEV.md`

## 2026-05-09 - Correção do backend de negociação de agenda móvel no `provider_propose`

### Objetivo

- Corrigir o backend para permitir que o prestador proponha horário quando o serviço ainda está em `open_for_schedule` sem `provider_id`.
- Corrigir a fallback `mobile-schedule-negotiation` para não falhar com `400 {"error":"[object Object]"}`.

### Diagnóstico

- O endpoint canônico `POST /api/v1/tracking/services/:id/propose-schedule` validava o prestador como participante apenas quando:
  - `provider_id` já fosse igual ao usuário autenticado.
- Isso bloqueava exatamente o primeiro `provider_propose`, retornando:
  - `Only participants can propose schedule`
- A fallback `mobile-schedule-negotiation` tinha dois problemas:
  - serializava erros não-`Error` como `"[object Object]"`, escondendo a causa real;
  - atualizava `schedule_round`, mas não mantinha `schedule_client_rounds` e `schedule_provider_rounds` em sincronia, violando a constraint:
    - `chk_service_requests_schedule_round_consistency`

### Ajuste aplicado

- Arquivo: `../supabase/functions/api/index.ts`
  - o fluxo canônico passou a aceitar `provider` autenticado como ator válido quando:
    - o serviço ainda está sem `provider_id`;
    - e o prestador está iniciando a reserva/agendamento;
  - o `update` agora usa filtros otimistas adicionais para evitar sobrescrita indevida:
    - `schedule_round`;
    - `provider_id` nulo ou igual ao prestador atual;
    - `client_id` no caso de ação do cliente;
  - quando o serviço mudar entre leitura e gravação, o endpoint agora responde conflito explícito (`409`) em vez de seguir silenciosamente.

- Arquivo: `../supabase/functions/mobile-schedule-negotiation/index.ts`
  - adicionada rotina `describeError(...)` para expor mensagem real de erro (`message/details/hint/code`) em vez de `"[object Object]"`;
  - o body agora aceita tanto:
    - `service_id` / `scheduled_at`
    - quanto `serviceId` / `scheduledAt`
  - `provider_propose` passou a atualizar também:
    - `schedule_provider_rounds`
    - `schedule_client_rounds`
  - `client_counter_propose` passou a atualizar também:
    - `schedule_client_rounds`
    - `schedule_provider_rounds`
  - o `select` interno da function foi ampliado para carregar esses contadores e manter consistência com as constraints do banco.

### Publicação remota

- Functions publicadas no projeto remoto `mroesvsmylnaxelrhqtl`:
  - `api`
  - `mobile-schedule-negotiation`

### Validação

- Executado:
  - `npx deno fmt /home/servirce/Documentos/101/projeto-central-/supabase/functions/api/index.ts /home/servirce/Documentos/101/projeto-central-/supabase/functions/mobile-schedule-negotiation/index.ts`
  - `supabase functions deploy api --project-ref mroesvsmylnaxelrhqtl`
  - `supabase functions deploy mobile-schedule-negotiation --project-ref mroesvsmylnaxelrhqtl`
- Validação remota com o serviço real `f806fac0-2a60-487b-b284-fc2194273486`:
  - resetado para `open_for_schedule` com `provider_id = null`;
  - autenticado `chaveiro10@gmail.com` com o usuário `428`;
  - reexecutado o canônico `POST /api/v1/tracking/services/:id/propose-schedule` a partir do estado sem prestador vinculado;
  - resultado:
    - `HTTP 200`
    - `status = schedule_proposed`
  - reexecutada a fallback `POST /functions/v1/mobile-schedule-negotiation` com `action = provider_propose` a partir do mesmo estado;
  - resultado:
    - `HTTP 200`
    - serviço salvo com:
      - `provider_id = 428`
      - `status = schedule_proposed`
      - `schedule_round = 1`
      - `schedule_provider_rounds = 1`
      - `schedule_client_rounds = 0`

### Efeito esperado

- O prestador consegue propor o primeiro horário diretamente pelo endpoint canônico mesmo quando o serviço ainda não possui `provider_id`.
- Se o app cair no fallback `mobile-schedule-negotiation`, a proposta também passa a funcionar sem violar as constraints de negociação.
- Erros futuros da fallback deixam de aparecer como `"[object Object]"`, facilitando diagnóstico real em produção.

## 2026-05-09 - Botão `ENVIAR PARA CLIENTE` sem ação na tela de serviço ativo do prestador

### Objetivo

- Fazer o botão `ENVIAR PARA CLIENTE` funcionar também na tela focada de serviço ativo do prestador.

### Diagnóstico

- O widget `ProviderServiceCard` já renderizava o formulário de agendamento e o botão:
  - `ENVIAR PARA CLIENTE`
- Nessa UI, o clique chamava apenas:
  - `widget.onSchedule?.call(finalDate, '')`
- Na tela `ProviderActiveServiceMobileScreen`, o card era montado sem:
  - `onSchedule`
  - `onConfirmSchedule`
- Resultado:
  - o botão aparecia normalmente;
  - mas o callback era `null`;
  - ao tocar, nada acontecia visualmente e nenhuma proposta era enviada.

### Ajuste aplicado

- Arquivo: `lib/features/provider/provider_active_service_mobile_screen.dart`
  - adicionada rotina `_proposeSchedule(...)` usando:
    - `ApiService.proposeSchedule(...)`
    - `scope: ServiceDataScope.mobileOnly`
  - adicionada rotina `_confirmSchedule()` para aceitar proposta ativa nessa mesma tela;
  - conectados no `ProviderServiceCard`:
    - `onSchedule`
    - `onConfirmSchedule`
  - após sucesso, a tela agora:
    - mostra `SnackBar`;
    - recarrega os detalhes do serviço para refletir o novo status.

### Validação

- Executado:
  - `flutter analyze --no-pub lib/features/provider/provider_active_service_mobile_screen.dart`
- Resultado:
  - `No issues found!`

### Efeito esperado

- Ao tocar em `ENVIAR PARA CLIENTE` na tela de serviço ativo do prestador, a proposta de horário passa a ser enviada de fato.
- O usuário volta a receber feedback claro de sucesso ou erro nessa tela.

## 2026-05-09 - Correção da vitrine móvel quando payload de dispatch usa `id` da fila em vez do `service_id`

### Objetivo

- Corrigir a home móvel do prestador para tratar corretamente ofertas vindas do dispatch privado.
- Evitar erro de UUID inválido, rota com coordenadas nulas e quebra em `getAvailableForSchedule()`.

### Diagnóstico

- O payload observado em produção vinha no formato de linha de oferta/notificação, por exemplo:
  - `id = 242`
  - `service_id = f806fac0-2a60-487b-b284-fc2194273486`
- A UI estava tratando `id` como se fosse o ID do serviço canônico.
- Isso gerava três efeitos colaterais:
  - `DataGateway.loadActivePrivateDispatchServiceIds(...)` consultava colunas UUID com `"242"`, disparando:
    - `invalid input syntax for type uuid: "242"`
  - a lógica de rota tentava usar coordenadas em chaves erradas (`latitude/longitude`), enquanto o payload trazia:
    - `service_latitude`
    - `service_longitude`
  - a vitrine misturava linha de fila/notificação com objeto de serviço, causando inconsistência de shape e erros de leitura.

### Ajuste aplicado

- Arquivo: `lib/services/api_service.dart`
  - `_mapServiceData(...)` passou a normalizar payloads híbridos de dispatch:
    - usa `service_id` como `id` canônico da UI;
    - preserva o `id` numérico da fila em `dispatch_row_id`;
    - aproveita o objeto aninhado `service` quando existir;
    - faz fallback de coordenadas para:
      - `service_latitude`
      - `service_longitude`
    - faz fallback de descrição/nome e valor do prestador:
      - `service_name`
      - `price_provider`
    - normaliza `provider_id` via `provider_user_id` quando necessário.

- Arquivo: `lib/services/data_gateway.dart`
  - `loadActivePrivateDispatchServiceIds(...)` agora extrai o identificador canônico usando:
    - `service_id`
    - fallback para `id` apenas quando realmente for objeto de serviço.

### Validação

- Executado:
  - `flutter analyze --no-pub lib/services/api_service.dart lib/services/data_gateway.dart lib/features/provider/provider_home_mobile.dart`
- Resultado:
  - nenhuma issue nova da correção;
  - permaneceram apenas warnings antigos já existentes:
    - `unused_element` em `provider_home_mobile.dart`
    - `unused_catch_clause` em `api_service.dart`

### Efeito esperado

- A home móvel do prestador volta a tratar corretamente ofertas privadas de dispatch.
- O app deixa de enviar IDs numéricos de fila para consultas que exigem UUID de serviço.
- O cálculo de rota volta a usar as coordenadas corretas do serviço.

## 2026-05-09 - Correção do contrato de `getAvailableForSchedule()` para endpoint que retorna lista direta

### Objetivo

- Corrigir o erro:
  - `type 'String' is not a subtype of type 'int' of 'index'`
- Fazer `getAvailableForSchedule()` aceitar corretamente o formato atual de resposta do backend.

### Diagnóstico

- O endpoint backend:
  - `GET /api/v1/providers/schedule/available`
  retorna uma `List` direta no corpo `data`, e não um objeto no formato:
  - `{"data":{"services":[...]}}`
- O app ainda tentava ler esse payload como:
  - `backendPayload['data']['services']`
- Quando `backendPayload['data']` era uma lista, o acesso por chave string gerava:
  - `type 'String' is not a subtype of type 'int' of 'index'`

### Ajuste aplicado

- Arquivo: `lib/services/api_service.dart`
  - `getAvailableForSchedule()` agora aceita múltiplos contratos:
    - `List` direta;
    - `data.services`;
    - `services`;
    - `data` como lista;
  - adicionada filtragem com `whereType<Map>()` antes de normalizar os itens.

### Validação

- Executado:
  - `flutter analyze --no-pub lib/services/api_service.dart`
- Resultado:
  - nenhuma issue nova da alteração;
  - permaneceram apenas 3 warnings antigos já existentes em `api_service.dart` por `unused_catch_clause`.

### Efeito esperado

- `getAvailableForSchedule()` deixa de quebrar quando o backend responde com lista direta.
- O log de erro `type 'String' is not a subtype of type 'int' of 'index'` deixa de aparecer nesse fluxo.

## 2026-05-09 - Correção de watchers legados ainda apontando para `service_requests_new`

### Objetivo

- Eliminar o erro de realtime/polling:
  - `Could not find the table 'public.service_requests_new' in the schema cache`

### Diagnóstico

- Parte do app já havia migrado para a tabela canônica:
  - `public.service_requests`
- Porém ainda existiam watchers legados em serviços auxiliares usando:
  - `service_requests_new`
- Isso afetava especialmente:
  - stream de sincronização de serviço;
  - stream/listagem de serviços do usuário;
  - polling fallback que tentava religar o estado do serviço.

### Ajuste aplicado

- Arquivo: `lib/services/service_sync_service.dart`
  - polling fallback alterado de:
    - `service_requests_new`
  - para:
    - `service_requests`
  - sincronização manual (`syncNow`) também passou a consultar `service_requests`.

- Arquivo: `lib/services/central_service.dart`
  - `watchUserServices(...)` alterado para stream em `service_requests`;
  - `getActiveServiceForClient(...)` alterado para buscar serviços móveis em `service_requests`.

### Validação

- Executado:
  - `flutter analyze --no-pub lib/services/service_sync_service.dart lib/services/central_service.dart`
- Resultado:
  - `No issues found!`

### Efeito esperado

- O erro `PGRST205` por tabela `service_requests_new` ausente deixa de aparecer nos fluxos de stream/polling desses serviços legados.
- O app passa a observar a tabela canônica do backend de forma consistente.
