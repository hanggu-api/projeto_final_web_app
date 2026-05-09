# Changelog - Busca na Home (Fixos e Móveis)

Data: 2026-04-14

## Objetivo
Garantir que a pesquisa de serviços (fixos e móveis) aconteça somente na Home, sem redirecionamento automático durante a digitação.

## Mudanças aplicadas

### 1) Correção de imports quebrados no app
Arquivo: `lib/main.dart`
- Ajustado import de telas que estavam com caminho antigo/inexistente.
- Novo mapeamento:
  - `features/client/home_prestador_fixo.dart` (classe `ServiceRequestScreenMobile`)
  - `features/client/hme_prestador_movel.dart` (classe `ServiceRequestScreenFixed`)

### 2) Busca inline na Home (sem navegar durante digitação)
Arquivo: `lib/features/home/home_screen.dart`
- Alterado fluxo da `HomeSearchBar` para callbacks inline:
  - `onSuggestionSelected` -> atualização local de busca
  - `onQuerySubmitted` -> atualização local de busca
- Criado/ajustado estado de busca inline:
  - `_inlineSearchText`
  - `_serviceSearchMode`
- Input permanece no topo da área de busca e resultados carregam abaixo.
- Layout em modo busca:
  - margem superior: `30`
  - laterais: `16`
- Esconde conteúdos não essenciais durante modo busca (home normal), mantendo foco no input + resultados.

### 3) Bloqueio de redirecionamento automático enquanto busca está ativa
Arquivo: `lib/features/home/home_screen.dart`
- Criado guard:
  - `_shouldSuppressAutoNavigation`
- Aplicado bloqueio no fluxo de reconexão/realtime da Home para evitar sair da tela durante busca.
- Quando houver serviço ativo durante busca, mantém estado local (`_activeServiceForBanner`) sem navegar.

### 4) Bloqueio adicional no roteador global
Arquivo: `lib/main.dart`
- Ajustado `GoRouter.redirect` no bloco de `findActiveService()`:
  - Se rota atual for `/home`, não forçar redirecionamento automático por serviço ativo.
- Isso impede que a Home seja "arrancada" para outra rota no meio da pesquisa.

## Comportamento esperado após os ajustes
1. Tocar no input da Home não deve abrir outra página.
2. A busca acontece no próprio painel da Home.
3. Digitar mostra autocomplete/resultados inline.
4. Redirecionamento automático por serviço ativo não deve interromper pesquisa em andamento.

## Observações
- Navegação manual (cliques explícitos do usuário em botões/cartões) pode continuar levando para as telas de sequência do pedido.
- As telas `/servicos` e `/beauty-booking` permanecem como etapas de continuidade do pedido, não ponto primário de pesquisa.
