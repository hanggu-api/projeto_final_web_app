# DIAGRAMA DE ALGORITMO DO APLICATIVO - SISTEMA COMPLETO

## Visão Geral
Aplicativo de gestão de serviços com múltiplos fluxos: Cadastro, Atualização, Criação de Serviços, Aceitação de Serviços, Notificações em tempo real e Rastreamento.

---

## 1. FLUXO DE CADASTRO (REGISTRO)

### 1.1. Tela de Registro - RegisterScreen
```
┌─────────────────────────────────────────┐
│  REGISTER SCREEN - Multi-step Form      │
│  ┌───────────────────────────────────┐  │
│  │  PageController (7 etapas)        │  │
│  │  ┌─────────┐ ┌─────────┐ ┌──────┐ │  │
│  │  │ 1. Info │ │ 2. Doc  │ │ 3.   │ │  │
│  │  │ Básica  │ │ Identif │ │ Loca │ │  │
│  │  └─────────┘ └─────────┘ └──────┘ │  │
│  │  ┌─────────┐ ┌─────────┐ ┌──────┐ │  │
│  │  │ 4. Prof │ │ 5. Medi │ │ 6.   │ │  │
│  │  │ ssão    │ │ Serviço │ │ Sched│ │  │
│  │  └─────────┘ └─────────┘ └──────┘ │  │
│  │  ┌─────────┐                      │  │
│  │  │ 7. Face │                      │  │
│  │  │ Liveness│                      │  │
│  │  └─────────┘                      │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### 1.2. Estados do Cadastro
```dart
Map<String, dynamic> _verificationData = {
  'name': _nameController.text,
  'email': _emailController.text,
  'password': _passwordController.text,
  'document': _docController.text,
  'phone': _phoneController.text,
  'birth_date': _birthDateController.text,
  'address': {
    'street': _addressController.text,
    'latitude': _latitude,
    'longitude': _longitude
  },
  'profession': _selectedProfession,
  'schedule': _schedule,
  'medical': {
    'price': _medicalPrice,
    'has_return': _medicalHasReturn
  },
  'sub_role': _effectiveProviderSubRole()
};
```

### 1.3. Validações
- ✅ BasicInfoStep: Nome, Email, Senha (mínimo 6 chars)
- ✅ IdentificationStep: CPF/CNPJ válido, Data Nascimento
- ✅ LocationStep: GPS ativado, Coordenadas válidas
- ✅ ProfessionStep: Profissão selecionada
- ✅ MedicalServiceStep: Preço definido se médico
- ✅ ScheduleStep: Horários configurados
- ✅ FacialLivenessStep: Biometria facial aprovada

### 1.4. Fluxo de Submissão
```
1. User preenche formulário multi-step
2. Validação local de cada etapa
3. Captura foto facial (Liveness check)
4. Monta payload completo
5. POST /api/register
6. Supabase Auth cria usuário
7. Salva perfil no banco
8. Redireciona para Login/Home
```

---

## 2. FLUXO DE ATUALIZAÇÃO DE CADASTRO

### 2.1. ProviderProfileScreen
```
┌─────────────────────────────────────────┐
│  PROFILE UPDATE                          │
│  ┌───────────────────────────────────┐  │
│  │  ProviderProfileContent           │  │
│  │  ┌─────────┐ ┌─────────┐          │  │
│  │  │  Nome   │ │  Email  │          │  │
│  │  └─────────┘ └─────────┘          │  │
│  │  ┌─────────┐ ┌─────────┐          │  │
│  │  │  Tel    │ │  Endere │          │  │
│  │  └─────────┘ └─────────┘          │  │
│  │  ┌─────────┐ ┌─────────┐          │  │
│  │  │  Horár  │ │  Servi  │          │  │
│  │  │  ios    │ │  ços    │          │  │
│  │  └─────────┘ └─────────┘          │  │
│  │  [Button: Salvar Alterações]      │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### 2.2. Processo de Atualização
```dart
Future<void> updateProfile(Map<String, dynamic> data) async {
  // 1. Valida campos alterados
  // 2. Atualiza Supabase Auth (se email/senha)
  // 3. PATCH /api/provider/profile
  // 4. Atualiza cache local
  // 5. Notifica mudança via WebSocket
}
```

---

## 3. FLUXO DE CRIAÇÃO DE SERVIÇO

### 3.1. ServiceRequestScreenMobile
```
┌─────────────────────────────────────────┐
│  CRIAR NOVO SERVIÇO                     │
│  ┌───────────────────────────────────┐  │
│  │  Tipo de Serviço                  │  │
│  │  [Fixo/Sob Demanda]               │  │
│  ├───────────────────────────────────┤  │
│  │  Detalhes                         │  │
│  │  ┌─────────┐ ┌─────────┐          │  │
│  │  │  Título │ │ Descri- │          │  │
│  │  │         │ │ ção     │          │  │
│  │  └─────────┘ └─────────┘          │  │
│  │  ┌─────────┐ ┌─────────┐          │  │
│  │  │  Preço  │ │ Local   │          │  │
│  │  │         │ │         │          │  │
│  │  └─────────┘ └─────────┘          │  │
│  │  [Button: Publicar Serviço]       │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### 3.2. Estados do Serviço (ServiceState)
```dart
enum ServiceState {
  requested,    // 🟡 Solicitado
  accepted,     // 🔵 Aceito pelo provider
  inProgress,   // 🟠 Em andamento
  arrived,      // 🟢 Prestador chegou
  completed,    // ✅ Concluído
  cancelled,    // ❌ Cancelado
}
```

### 3.3. Transições Válidas
```
requested → [accepted, cancelled]
accepted → [inProgress, cancelled]
inProgress → [arrived, completed, cancelled]
arrived → [completed, cancelled]
completed → []
cancelled → []
```

### 3.4. Criação via API
```dart
class ServiceRepository {
  Future<Service> createService({
    required String title,
    required String description,
    required double price,
    required String location,
    required String providerId,
    required bool isFixed,
  }) async {
    // POST /api/services
    // Gera ID único
    // Define estado inicial: requested
    // Notifica providers disponíveis
    // Retorna serviço criado
  }
}
```

---

## 4. FLUXO DE ACEITAÇÃO DE SERVIÇO

### 4.1. ProviderHomeScreen - Aceitação
```
┌─────────────────────────────────────────┐
│  SERVIÇOS DISPONÍVEIS                   │
│  ┌───────────────────────────────────┐  │
│  │  [Serviço 1]                      │  │
│  │  Título: Manutenção               │  │
│  │  Valor: R$ 150,00                 │  │
│  │  [Button: Aceitar]                │  │
│  ├───────────────────────────────────┤  │
│  │  [Serviço 2]                      │  │
│  │  Título: Consulta                 │  │
│  │  Valor: R$ 200,00                 │  │
│  │  [Button: Aceitar]                │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### 4.2. Processo de Aceitação
```dart
class ChangeServiceStatusUseCase {
  Future<void> acceptService({
    required String serviceId,
    required String providerId,
  }) async {
    // 1. Verifica disponibilidade do provider
    // 2. Valida transição: requested → accepted
    // 3. Atualiza status no banco
    // 4. Atribui provider ao serviço
    // 5. Envia notificação ao cliente
    // 6. Inicia rastreamento (se mobile)
  }
}
```

### 4.3. Lógica de Negócio
```dart
static const Map<ServiceState, Set<ServiceState>> _allowedTransitions = {
  ServiceState.requested: {ServiceState.accepted, ServiceState.cancelled},
  ServiceState.accepted: {ServiceState.inProgress, ServiceState.cancelled},
  ServiceState.inProgress: {ServiceState.arrived, ServiceState.completed, ServiceState.cancelled},
  ServiceState.arrived: {ServiceState.completed, ServiceState.cancelled},
  ServiceState.completed: {},
  ServiceState.cancelled: {},
};
```

---

## 5. FLUXO DE NOTIFICAÇÕES

### 5.1. Arquitetura de Notificações
```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Supabase      │────▶│  Realtime        │────▶│  Client App     │
│   Database      │     │  Listeners       │     │  (StreamBuilder)│
└─────────────────┘     └──────────────────┘     └─────────────────┘
       ▲                        │                        │
       │                        ▼                        ▼
       │                ┌──────────────────┐     ┌─────────────────┐
       │                │ Notification     │     │ Notification    │
       │                │ Envelope         │     │ Screen          │
       │                └──────────────────┘     └─────────────────┘
       │                        │                        │
       └────────────────────────┼────────────────────────┘
                                ▼
                       ┌──────────────────┐
                       │  DataGateway     │
                       │  - watchNotif    │
                       │  - markAsRead    │
                       │  - navigate      │
                       └──────────────────┘
```

### 5.2. NotificationEnvelope
```dart
class NotificationEnvelope {
  final String canonicalType;  // Tipo: service, chat, system
  final String? title;         // Título da notif
  final String? body;          // Corpo da notif
  final Map<String, dynamic> data;  // Payload extra
  final bool fromLegacyAlias;  // Compatibilidade
}
```

### 5.3. Fluxo de Recebimento
```
1. Evento no banco (novo status, nova msg)
2. Supabase Realtime dispara evento
3. DataGateway.watchNotifications() captura
4. StreamBuilder atualiza UI
5. NotificationItem exibe na lista
6. User clica → markAsRead() + navigate()
```

### 5.4. Tipos de Notificações
- 🔔 **Service**: Status alterado (aceito, iniciado, concluído)
- 💬 **Chat**: Nova mensagem do cliente/provider
- 📋 **System**: Atualizações de sistema, promoções
- ⚠️ **Alert**: Cancelamentos, problemas

---

## 6. FLUXO DE ACOMPANHAMENTO (TRACKING)

### 6.1. TrackingPage - Rastreamento em Tempo Real
```
┌─────────────────────────────────────────┐
│  TRACKING PAGE                          │
│  ┌───────────────────────────────────┐  │
│  │  FlutterMap + Mapbox              │  │
│  │  ┌─────────┐                       │  │
│  │  │   MAPA  │                       │  │
│  │  │   🚗 →  │                       │  │
│  │  │    ⬇    │                       │  │
│  │  │   📍    │                       │  │
│  │  └─────────┘                       │  │
│  ├───────────────────────────────────┤  │
│  │  ServicePanelContent              │  │
│  │  ┌─────────┐ ┌─────────┐          │  │
│  │  │ Motorista│ │ Cancelar│          │  │
│  │  │ Info    │ │         │          │  │
│  │  └─────────┘ └─────────┘          │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### 6.2. TrackingState
```dart
class TrackingState {
  String serviceId;
  LatLng? driverLocation;
  LatLng? pickupLocation;
  LatLng? dropoffLocation;
  double bearing;
  ServiceStatus status;
  DriverInfo? driverInfo;
  ETA? eta;
}
```

### 6.3. Atualização em Tempo Real
```dart
class TrackingCubit extends Cubit<TrackingState> {
  void initialize() {
    // 1. Conecta WebSocket
    // 2. Fetch localização inicial
    // 3. Inicia Timer de polling (30s)
    // 4. Listen de eventos Realtime
    // 5. Atualiza mapa animado
  }
  
  void _updateDriverLocation(LatLng newPos) {
    // Interpolação suave (lerp)
    // Atualiza bearing
    // Re-centra mapa
    // Verifica proximidade (geofence)
  }
}
```

### 6.4. MapManager
```dart
class MapManager {
  void animateTo(LatLng position) {
    // Transição suave 500ms
    // Mantém markers atualizados
  }
  
  void drawRoute(Polyline route) {
    // Desenha rota otimizada
    // Mostra ETA
  }
}
```

---

## 7. FLUXO COMPLETO DE UM SERVIÇO

### 7.1. Diagrama de Estados Completo
```

   CLIENTE CRIA SERVIÇO     
  (ServiceRequestScreen)    

              │
              ▼

   STATUS: REQUESTED        
    🟡 Aguardando aceite     

              │
              ├─► Provider recebe notificação
              │
              ▼

   PROVIDER ACEITA          
  (ProviderHomeScreen)      

              │
              ▼

   STATUS: ACCEPTED         
    🔵 Aceito, aguardando   

              │
              ├─► Rastreamento inicia
              │
              ▼

   STATUS: IN PROGRESS      
    🟠 Motorista a caminho   

              │
              ▼

   STATUS: ARRIVED          
    🟢 No local             

              │
              ▼

   STATUS: COMPLETED        
    ✅ Serviço finalizado   

              │
              ├─► Pagamento processado
              ├─► Avaliação solicitada
              └─► Notificação enviada
```

### 7.2. Transições com Handlers
```dart
// Em TrackingPage/Cubit
void changeStatus(ServiceState newState) {
  switch (newState) {
    case ServiceState.accepted:
      _showServiceAcceptedModal();
      _startDriverTracking();
      break;
    case ServiceState.inProgress:
      _showServiceStartedModal();
      _enableChat();
      break;
    case ServiceState.arrived:
      _showArrivedNotification();
      _enableCompletion();
      break;
    case ServiceState.completed:
      _showCompletionModal();
      _requestRating();
      _processPayment();
      break;
    case ServiceState.cancelled:
      _showCancellationReason();
      _refundIfApplicable();
      break;
  }
}
```

---

## 8. ARQUITETURA DE ARQUIVOS PRINCIPAIS

### 8.1. Estrutura de Domínios
```
lib/
├── domains/
│   ├── auth/              # Autenticação
│   │   ├── presentation/
│   │   │   └── auth_controller.dart
│   │   ├── domain/
│   │   │   └── login_usecase.dart
│   │   └── data/
│   │       └── auth_repository.dart
│   │
│   ├── service/           # Serviços
│   │   ├── models/
│   │   │   └── service_state.dart
│   │   ├── domain/
│   │   │   ├── change_service_status_usecase.dart
│   │   │   └── slot_generator.dart
│   │   └── data/
│   │       └── service_repository.dart
│   │
│   ├── chat_notifications/ # Notificações
│   │   └── models/
│   │       └── notification_envelope.dart
│   │
│   └── scheduling/        # Agendamentos
│       ├── models/
│       ├── domain/
│       └── data/
│
├── features/
│   ├── auth/
│   │   ├── register_screen.dart    # Cadastro
│   │   └── login_screen.dart       # Login
│   │
│   ├── provider/
│   │   ├── provider_home_screen.dart     # Home Provider
│   │   └── widgets/
│   │       ├── service_started_modal.dart
│   │       └── service_completion_modal.dart
│   │
│   ├── tracking/
│   │   ├── tracking_page.dart           # Rastreamento
│   │   ├── cubit/tracking_cubit.dart
│   │   └── widgets/
│   │       ├── service_panel_content.dart
│   │       └── map_controls.dart
│   │
│   └── shared/
│       └── notification_screen.dart      # Notificações
│
└── integrations/
    └── supabase/              # Backend
        ├── auth/
        ├── service/
        └── remote_ui/
```

---

## 9. DIAGRAMA DE FLUXO CONTÍNUO

```

  [CADASTRO]                                                       
  RegisterScreen → Multi-step → Supabase Auth → Perfil           

                     │                                            
                     ▼                                            

  [LOGIN]                                                         
  LoginScreen → AuthController → ProviderHome/ClientHome         

                     │                                            
                     ├─► [CLIENTE]                                
                     │    ServiceRequest → Create Service         
                     │                                            
                     └─► [PROVIDER]                               
                          ProviderHome → Accept Service           
                                        │                        
                                        ▼                        
                              
                              [TRACKING]                         
                              TrackingPage ← Cubit ← WebSocket   
                              │   │   │                          
                              │   │   └─ Status Updates          
                              │   └─► Location Updates           
                              └─► Notifications                  
                                        │                        
                                        ▼                        
                              
                              [NOTIFICAÇÕES]                      
                              Stream → DataGateway → UI           

```

---

## 10. RESUMO DOS ALGORITMOS

### 10.1. Cadastro
- **Tipo**: Multi-step form com validação progressiva
- **Tecnologias**: PageController, Form validation, Supabase Auth
- **Saída**: Usuário autenticado com perfil completo

### 10.2. Atualização
- **Tipo**: Edição parcial com merge
- **Tecnologias**: Provider pattern, PATCH requests
- **Saída**: Perfil atualizado em tempo real

### 10.3. Criação de Serviço
- **Tipo**: CRUD com atribuição automática
- **Tecnologias**: ServiceRepository, State transitions
- **Saída**: Serviço no estado REQUESTED

### 10.4. Aceitação de Serviço
- **Tipo**: State machine com validação
- **Tecnologias**: ChangeServiceStatusUseCase, Allowed transitions
- **Saída**: Serviço no estado ACCEPTED

### 10.5. Notificações
- **Tipo**: Realtime push via WebSocket
- **Tecnologias**: Supabase Realtime, StreamBuilder
- **Saída**: UI atualizada instantaneamente

### 10.6. Rastreamento
- **Tipo**: Location tracking com polling
- **Tecnologias**: TrackingCubit, MapManager, Geofencing
- **Saída**: Localização em tempo real no mapa

---

## 11. FLUXOGRAMA VISUAL COMPLETO

```

                    INÍCIO                           

                         │
        
                                             
         [CADASTRO]                          [LOGIN]    
  1. Multi-step form                        1. Email/Senha
  2. Validação                              2. AuthController
  3. Supabase Auth                          3. Redirect
         │                                          │
          └───────────────┬────────────────────────┘
                          │
              
               [ESCOLHA DE PERFIL]  
              
                         │
        
                                             
    [CLIENTE]                           [PROVIDER]   
 1. ServiceRequest                  1. ProviderHome   
 2. Create Service                  2. Accept Service 
 3. Aguardar aceite                 3. Start Tracking 
         │                                          │
          └───────────────┬────────────────────────┘
                          │
              
               [SERVIÇO ACEITO]   
              
                         │
                         ▼
              
               [TRACKING ATIVO]    
              
              ┌─────────────────────────┐
              │  TrackingPage           │
              │  ┌───────────────────┐  │
              │  │   Mapa em tempo   │  │
              │  │   real (30s)      │  │
              │  └───────────────────┘  │
              │  ┌───────────────────┐  │
              │  │   Status:         │  │
              │  │   IN_PROGRESS →   │  │
              │  │   ARRIVED →       │  │
              │  │   COMPLETED       │  │
              │  └───────────────────┘  │
              └─────────────────────────┘
                         │
        
                                             
    [NOTIFICAÇÕES]                     [COMPLETAR]  
 1. Push via WS                       1. Código     
 2. StreamBuilder                     2. Foto       
 3. Mark as read                      3. Upload     
                         │
                         ▼
              
               [STATUS: COMPLETED]   
              
                         │
                         ▼
              
               [FIM DO FLUXO]        
              
```

---

## 12. TABELA DE ESTADOS E AÇÕES

| Estado | Ação Permitida | Quem Pode | Notificação |
|--------|----------------|-----------|-------------|
| REQUESTED | Aceitar | Provider | 🔔 Novo serviço |
| REQUESTED | Cancelar | Cliente | 🔔 Cancelado |
| ACCEPTED | Iniciar | Provider | 🔔 Aceito |
| ACCEPTED | Cancelar | Provider | 🔔 Cancelado |
| IN_PROGRESS | Chegar | Provider | 📍 Chegou |
| IN_PROGRESS | Cancelar | Provider | 🔔 Cancelado |
| ARRIVED | Concluir | Provider | ✅ Pronto |
| ARRIVED | Cancelar | Provider | 🔔 Cancelado |
| COMPLETED | Avaliar | Cliente | ⭐ Avaliação |
| CANCELLED | - | - | ❌ Cancelado |

---

## 13. SEQUÊNCIA DE EVENTOS TÍPICA

```
1. 08:00 - Cliente cria serviço
   → ServiceState: REQUESTED
   → Notif: "Serviço criado"

2. 08:05 - Provider aceita
   → ServiceState: ACCEPTED  
   → Notif: "Serviço aceito por João"
   → Tracking: Iniciado

3. 08:15 - Provider inicia serviço
   → ServiceState: IN_PROGRESS
   → Notif: "João iniciou o serviço"
   → Map: Motorista visível

4. 08:25 - Provider chega no local
   → ServiceState: ARRIVED
   → Notif: "João chegou"
   → Map: Ícone no local

5. 08:45 - Service concluído
   → ServiceState: COMPLETED
   → Notif: "Serviço concluído"
   → Modal: Código + Foto

6. 08:50 - Cliente avalia
   → Notif: "Avaliação recebida"
   → Fim do fluxo
```

---

## 14. CONEXÕES ENTRE MÓDULOS

```

  AUTH        SERVICE      NOTIFICATION   TRACKING  
  CONTROLLER  USECASE      ENVELOPE       CUBIT    

       │              │              │              │
       ├─ login ──────┼──────────────┼──────────────┤
       │              │              │              │
       ├─ profile ────┼──────────────┼──────────────┤
       │              │              │              │
       └─ logout ─────┼──────────────┼──────────────┤
                      │              │              │
         create       │              │              │
        service ──────┼──────────────┼──────────────┤
                      │              │              │
         accept       │              │              │
        service ──────┼──────────────┼──────────────┤
                      │              │              │
         update       │              │              │
        status ───────┼──────────────┼──────────────┤
                      │              │              │
         notify ──────┼──────────────┼──────────────┤
                      │              │              │
         track ───────┼──────────────┼──────────────┤
                      │              │              │

```

---

## 15. PONTOS DE INTEGRAÇÃO

### 15.1. Supabase (Backend)
- Auth: Registro/Login
- Realtime: Notificações
- Storage: Fotos de serviço
- Database: Perfis e serviços

### 15.2. APIs REST
- `/api/register`: POST - Cria usuário
- `/api/services`: POST/GET - Serviços
- `/api/services/{id}/status`: PATCH - Atualiza status
- `/api/provider/home`: GET - Dados do provider
- `/api/tracking/{id}`: GET/WS - Localização

### 15.3. WebSockets
- `service:{id}`: Atualizações de status
- `location:{id}`: Localização em tempo real
- `notifications:{uid}`: Push notifications
- `chat:{serviceId}`: Mensagens do serviço

---

## 16. DIAGRAMA DE FLUXO DE DADOS

```

  CLIENT APP              API SERVER           DATABASE       

      │                       │                       │
      │ 1. POST /register     │                       │
      │──────────────────────▶│                       │
      │                       │ 2. Create User       │
      │                       │─────────────────────▶│
      │                       │                       │
      │ 3. Auth Token         │                       │
      │◀──────────────────────│                       │
      │                       │                       │
      │ 4. POST /services     │                       │
      │──────────────────────▶│                       │
      │                       │ 5. Create Service    │
      │                       │─────────────────────▶│
      │                       │                       │
      │ 6. WS: service:123    │                       │
      │◀──────────────────────│                       │
      │                       │ 7. Status Update     │
      │                       │─────────────────────▶│
      │                       │                       │
      │ 8. PATCH /status      │                       │
      │──────────────────────▶│                       │
      │                       │ 9. Update Service    │
      │                       │─────────────────────▶│
      │                       │                       │
      │ 10. WS: notify        │                       │
      │◀──────────────────────┼───────────────────────┤
      │                       │                       │
      │ 11. GET /tracking     │                       │
      │──────────────────────▶│                       │
      │                       │ 12. Get Location     │
      │                       │─────────────────────▶│
      │                       │                       │
      │ 13. WS: location:123  │                       │
      │◀──────────────────────│                       │
      │                       │                       │

```

---

## 17. FLUXO DE ERROS E RECUPERAÇÃO

### 17.1. Falha no Cadastro
```
1. Validação falha → Mostra erro no campo
2. Email já existe → "Email já cadastrado"
3. Senha fraca → "Mínimo 6 caracteres"
4. Network error → "Verifique conexão"
5. Timeout → Tentativa automática (3x)
```

### 17.2. Falha na Aceitação
```
1. Service não encontrado → "Serviço indisponível"
2. Provider ocupado → "Você já tem serviço ativo"
3. Network error → "Falha ao aceitar"
4. Conflito de status → "Serviço já aceito"
```

### 17.3. Falha no Tracking
```
1. GPS desativado → Solicita ativação
2. Location null → Usa última posição
3. WS desconectado → Reconnect automático
4. Timeout → Mostra "Offline"
```

---

## 18. OTIMIZAÇÕES E BOAS PRÁTICAS

### 18.1. Performance
- ✅ Debounce em buscas (300ms)
- ✅ Lazy load de imagens
- ✅ Cache de perfil (SharedPreferences)
- ✅ Pool de conexões WebSocket
- ✅ Throttle de localização (5s)

### 18.2. Segurança
- ✅ Senhas hasheadas (bcrypt)
- ✅ Tokens JWT com expiração
- ✅ Validação de input server-side
- ✅ Rate limiting nas APIs
- ✅ Criptografia de dados sensíveis

### 18.3. UX
- ✅ Feedback visual em todas ações
- ✅ Skeleton screens no loading
- ✅ Toast messages para erros
- ✅ Pull-to-refresh nas listas
- ✅ Animações suaves (300ms)

---

## 19. RESUMO EXECUTIVO

### Componentes Principais:
1. **Auth** - Registro/Login via Supabase
2. **Service** - CRUD com state machine
3. **Notification** - Realtime push via WebSocket
4. **Tracking** - Location tracking com Mapbox
5. **Provider** - Dashboard de prestadores
6. **Client** - Interface de solicitação

### Fluxos Principais:
1. Cadastro → 7 etapas validadas
2. Login → Token JWT
3. Criação → Service no estado REQUESTED
4. Aceitação → Transição ACCEPTED
5. Rastreamento → Updates em tempo real
6. Notificações → Push via WebSocket
7. Conclusão → Pagamento + Avaliação

### Tecnologias:
- Flutter 3.x + Riverpod + GoRouter
- Supabase (Auth, Realtime, Storage, DB)
- Mapbox + FlutterMap
- WebSocket + StreamBuilder
- State Machine (Transições validadas)

---

## 20. LEGENDA DE SÍMBOLOS

- 🟡 REQUESTED - Aguardando
- 🔵 ACCEPTED - Aceito
- 🟠 IN_PROGRESS - Em andamento
- 🟢 ARRIVED - No local
- ✅ COMPLETED - Concluído
- ❌ CANCELLED - Cancelado
- 🔔 Notificação push
- 📍 Localização GPS
- ⚡ WebSocket
- 🗄️ Database
- 🔄 Atualização
- ➡️ Transição
- ⏱️ Timer/Polling

---

**Documentação gerada em:** 2026-05-05  
**Versão:** 1.0.0  
**Status:** ✅ Completo
