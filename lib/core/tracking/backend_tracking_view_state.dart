import '../constants/trip_statuses.dart';
import '../utils/mobile_client_navigation_gate.dart';
import '../utils/provider_mobile_active_policy.dart';
import '../../services/api_service.dart';

class BackendTrackingViewState {
  const BackendTrackingViewState({
    required this.serviceId,
    required this.role,
    required this.route,
    required this.screen,
    required this.stage,
    required this.title,
    required this.message,
    required this.isActive,
    required this.shouldPinTracking,
    required this.primaryAction,
    required this.secondaryActions,
    required this.raw,
  });

  final String serviceId;
  final String role;
  final String route;
  final String screen;
  final String stage;
  final String title;
  final String message;
  final bool isActive;
  final bool shouldPinTracking;
  final Map<String, dynamic>? primaryAction;
  final List<String> secondaryActions;
  final Map<String, dynamic> raw;

  factory BackendTrackingViewState.fromMap(Map<String, dynamic> map) {
    return BackendTrackingViewState(
      serviceId: _readString(map, const ['serviceId', 'service_id']),
      role: _readString(map, const ['role']),
      route: _readString(map, const ['route']),
      screen: _readString(map, const ['screen']),
      stage: _readString(map, const ['stage']),
      title: _readString(map, const ['title', 'headline']),
      message: _readString(map, const ['message', 'body', 'subtitle']),
      isActive: _readBool(map, const ['isActive', 'is_active']),
      shouldPinTracking: _readBool(map, const [
        'shouldPinTracking',
        'should_pin_tracking',
      ]),
      primaryAction: _readMap(map, const ['primaryAction', 'primary_action']),
      secondaryActions: _readStringList(map, const [
        'secondaryActions',
        'secondary_actions',
      ]),
      raw: Map<String, dynamic>.from(map),
    );
  }

  factory BackendTrackingViewState.fallback({
    required Map<String, dynamic> service,
    required ServiceDataScope scope,
    required String? role,
  }) {
    final serviceId = service['id']?.toString().trim() ?? '';
    final normalizedRole = (role ?? '').trim().toLowerCase();
    final status = normalizeServiceStatus(service['status']?.toString());
    final terminal = ServiceStatusSets.inactiveTerminal.contains(status);
    final effectiveRole = normalizedRole.isNotEmpty
        ? normalizedRole
        : scope == ServiceDataScope.mobileOnly
        ? 'provider'
        : 'client';

    final route = effectiveRole == 'provider'
        ? (resolveProviderMobileActiveRoute(service) ?? '/provider-home')
        : resolveClientActiveServiceRoute(service, serviceId);
    final stage = _stageForStatus(status);
    return BackendTrackingViewState(
      serviceId: serviceId,
      role: effectiveRole,
      route: route,
      screen: effectiveRole == 'provider'
          ? (route.startsWith('/provider-active/')
                ? 'provider_tracking'
                : 'provider_home')
          : (route.startsWith('/service-tracking/')
                ? 'client_tracking'
                : 'client_home'),
      stage: stage,
      title: _titleForStatus(status),
      message: _messageForStatus(status, effectiveRole),
      isActive: !terminal,
      shouldPinTracking:
          !terminal &&
          (route.contains('tracking') || route.startsWith('/provider-active/')),
      primaryAction: _primaryActionForStatus(status, effectiveRole),
      secondaryActions: const ['chat'],
      raw: {
        'source': 'flutter_fallback',
        'serviceId': serviceId,
        'role': effectiveRole,
        'status': status,
        'route': route,
        'stage': stage,
      },
    );
  }

  static String _readString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }

  static bool _readBool(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is bool) return value;
      final text = value?.toString().trim().toLowerCase();
      if (text == 'true') return true;
      if (text == 'false') return false;
    }
    return false;
  }

  static Map<String, dynamic>? _readMap(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = map[key];
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return value.cast<String, dynamic>();
    }
    return null;
  }

  static List<String> _readStringList(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = map[key];
      if (value is List) {
        return value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
      }
    }
    return const [];
  }

  static String _stageForStatus(String status) {
    if (ServiceStatusSets.paymentRemaining.contains(status)) return 'payment';
    if (ServiceStatusSets.providerConcluding.contains(status)) {
      return 'completion';
    }
    switch (status) {
      case TripStatuses.waitingPayment:
        return 'reserve_payment';
      case TripStatuses.searching:
      case ServiceStatusAliases.searchingProvider:
      case ServiceStatusAliases.searchProvider:
      case ServiceStatusAliases.waitingProvider:
        return 'searching_provider';
      case TripStatuses.accepted:
      case 'provider_near':
      case TripStatuses.arrived:
      case TripStatuses.clientDeparting:
      case TripStatuses.clientArrived:
        return 'arrival';
      case TripStatuses.inProgress:
        return 'execution';
      case ServiceStatusAliases.scheduleProposed:
      case TripStatuses.scheduled:
        return 'schedule';
      case ServiceStatusAliases.contested:
        return 'dispute';
      default:
        return 'status';
    }
  }

  static String _titleForStatus(String status) {
    switch (_stageForStatus(status)) {
      case 'reserve_payment':
        return 'Aguardando pagamento da reserva';
      case 'searching_provider':
        return 'Buscando prestador';
      case 'arrival':
        return 'Prestador a caminho';
      case 'payment':
        return 'Pagamento restante';
      case 'execution':
        return 'Serviço em execução';
      case 'schedule':
        return 'Serviço agendado';
      case 'completion':
        return 'Aguardando conclusão';
      case 'dispute':
        return 'Em análise';
      default:
        return 'Status do serviço';
    }
  }

  static String _messageForStatus(String status, String role) {
    if (role == 'provider') {
      switch (_stageForStatus(status)) {
        case 'execution':
          return 'Execute o serviço e finalize quando concluir.';
        case 'completion':
          return 'Envie a comprovação e aguarde a confirmação do cliente.';
        case 'schedule':
          return 'Acompanhe o horário combinado com o cliente.';
        default:
          return 'Acompanhe este serviço ativo em tempo real.';
      }
    }
    switch (_stageForStatus(status)) {
      case 'searching_provider':
        return 'Pagamento confirmado. Estamos buscando um prestador disponível.';
      case 'payment':
        return 'Conclua o pagamento restante para liberar a próxima etapa.';
      case 'completion':
        return 'Confira o serviço e confirme a conclusão.';
      default:
        return 'Acompanhe a atualização do serviço em tempo real.';
    }
  }

  static Map<String, dynamic>? _primaryActionForStatus(
    String status,
    String role,
  ) {
    final stage = _stageForStatus(status);
    if (role == 'provider' && stage == 'execution') {
      return {'type': 'finish_service', 'label': 'FINALIZAR SERVIÇO'};
    }
    if (role == 'provider' && stage == 'arrival') {
      return {'type': 'arrive_service', 'label': 'CHEGUEI NO SERVIÇO'};
    }
    if (role == 'client' && stage == 'payment') {
      return {'type': 'pay_remaining', 'label': 'PAGAR RESTANTE'};
    }
    if (role == 'client' && stage == 'completion') {
      return {'type': 'confirm_completion', 'label': 'CONFIRMAR CONCLUSÃO'};
    }
    return null;
  }
}
