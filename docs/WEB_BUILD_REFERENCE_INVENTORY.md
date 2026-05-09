# Web build reference inventory

Fonte de verdade escolhida: `https://www.101service.com.br/login`.

## Identidade do build

- Versao do app: `1.0.2+6`
- `vercel_dist/main.dart.js`: `7739710` bytes
- SHA-256 de `vercel_dist/main.dart.js`: `e843dd1c4a271fcecfc0c2089d983129d157335cfe578e488b7d3d59066723cb`
- SHA-256 de `vercel_dist/version.json`: `12c4476dbc8fbb316cc75992439bd87631ca97b25d2543acc1ee47a0c4cbfe59`
- SHA-256 de `vercel_dist/assets/AssetManifest.bin.json`: `4646106e3425bde060f02f3772ccaaa08253d94eb1c6fc70c37e467760184efb`
- Renderer web: CanvasKit com variante `chromium`

## Rotas observadas no bundle

- `/login`
- `/cpf-completion`
- `/register`
- `/ios-login`
- `/home`
- `/home-search`
- `/home-explore`
- `/servicos`
- `/beauty-booking`
- `/pix-payment`
- `/service-tracking/:serviceId`
- `/service-busca-prestador-movel/:serviceId`
- `/scheduled-service/:serviceId`
- `/provider-home`
- `/provider-active/:serviceId`
- `/provider-schedule`
- `/medical-home`
- `/provider-profile`
- `/my-provider-profile`
- `/my-services`
- `/payment/:serviceId`
- `/provider-service-details/:serviceId`
- `/provider-service-finish/:serviceId`
- `/notifications`
- `/payment-methods`
- `/card-registration`
- `/refund-request`
- `/menu`

## Textos e contratos-chave observados

- Home/marketing:
  - `A plataforma 101 Service`
  - `Atendimento movel e em estabelecimentos`
  - `Buscar servicos`
  - `Explorar beleza`
  - `O que você precisa hoje?`
  - `Servicos`, `Atendimento movel`, `Beleza`, `Salao e barbearia`
- Cadastro:
  - `Quero ser Cliente`
  - `Quero ser Prestador`
  - `Prova de vida`
  - `Antes dos dados finais, precisamos validar rapidamente sua identidade para proteger sua conta.`
  - `CPF é obrigatório`
  - `CPF deve ter 11 dígitos`
  - `Faça a prova de vida para continuar o cadastro.`
  - chaves persistidas: `register_step`, `register_is_client`, `register_sub_role`, `register_flow_signature`, `register_birth_date`, `register_verification_data`
- Tracking/pagamento:
  - rotas canônicas: `/service-tracking/:serviceId`, `/service-busca-prestador-movel/:serviceId`, `/scheduled-service/:serviceId`
  - endpoints backend-first: `/api/v1/tracking/active-service`, `/api/v1/tracking/services/{id}`, `/api/v1/tracking/services/{id}/snapshot`
  - Pix/service payment: `service_payment_v1`

## Decisoes de restauracao

- O build web publicado prevalece sobre alteracoes locais nao publicadas quando houver divergencia de comportamento.
- `vercel_dist/` e o bundle minificado sao referencia de comportamento, textos, rotas e assets, nao fonte Dart reconstituivel linha a linha.
- Mudancas necessarias apenas para manter o source local analisavel/compilavel podem permanecer se nao alterarem comportamento do build bom.
