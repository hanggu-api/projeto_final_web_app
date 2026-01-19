import 'dart:async';
import 'api_service.dart';
import 'data_gateway.dart';

/// ServiceSyncService: Sincronizar estado do serviço com fallback
/// - Começa com Firebase (rápido <200ms)
/// - Se Firebase falhar, ativa polling a cada 5s
/// - Mantém stream contínuo de atualizações
class ServiceSyncService {
  static final ServiceSyncService _instance = ServiceSyncService._internal();

  factory ServiceSyncService() {
    return _instance;
  }

  ServiceSyncService._internal();

  final Map<String, _ServiceWatch> _watches = {};

  /// Começar a escutar atualizações de um serviço
  Stream<Map<String, dynamic>> watchService(String serviceId) {
    // Se já está observando, retornar stream existente
    if (_watches.containsKey(serviceId)) {
      return _watches[serviceId]!.controller.stream;
    }

    // Criar novo watch
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    final watch = _ServiceWatch(
      serviceId: serviceId,
      controller: controller,
    );

    _watches[serviceId] = watch;

    // Iniciar Firebase listener
    _startFirebaseListener(serviceId, watch);

    // Iniciar polling fallback
    _startPollingFallback(serviceId, watch);

    return controller.stream;
  }

  /// Parar de escutar um serviço
  Future<void> stopWatching(String serviceId) async {
    final watch = _watches[serviceId];
    if (watch == null) return;

    // Cancelar listeners
    await watch.firebaseSubscription?.cancel();
    watch.pollingTimer?.cancel();

    // Fechar stream
    await watch.controller.close();

    _watches.remove(serviceId);

    print('[ServiceSync] Parando watch para $serviceId');
  }

  /// Começar listener do Firebase
  void _startFirebaseListener(
    String serviceId,
    _ServiceWatch watch,
  ) {
    try {
      watch.firebaseSubscription = DataGateway()
          .watchService(serviceId)
          .listen(
            (service) {
              // Firebase funcionando!
              watch.firebaseWorking = true;
              watch.controller.add(service);

              print('[ServiceSync] Firebase update recebido para $serviceId');
            },
            onError: (error) {
              // Firebase falhou
              watch.firebaseWorking = false;
              print(
                '[ServiceSync] Firebase erro para $serviceId: $error, '
                'ativando polling fallback...',
              );
            },
          );
    } catch (error) {
      watch.firebaseWorking = false;
      print('[ServiceSync] Erro ao iniciar Firebase listener: $error');
    }
  }

  /// Começar polling fallback (se Firebase falhar)
  void _startPollingFallback(
    String serviceId,
    _ServiceWatch watch,
  ) {
    watch.pollingTimer?.cancel();

    watch.pollingTimer = Timer.periodic(
      Duration(seconds: 5),
      (_) async {
        // Só fazer polling se Firebase não está funcionando
        if (watch.firebaseWorking) {
          return;
        }

        try {
          final api = ApiService();
          final response = await api.get('/services/$serviceId');

          if (response.containsKey('service')) {
            final service = response['service'] as Map<String, dynamic>;
            watch.controller.add(service);

            print('[ServiceSync] Polling update para $serviceId');
          }
        } catch (error) {
          // Erro no polling, tentar de novo no próximo ciclo
          print('[ServiceSync] Polling erro para $serviceId: $error');
        }
      },
    );
  }

  /// Retornar stream contínuo com fallback automático
  Stream<Map<String, dynamic>> createSyncStream(String serviceId) {
    return watchService(serviceId);
  }

  /// Sincronizar manualmente (forçar update)
  Future<void> syncNow(String serviceId) async {
    try {
      final api = ApiService();
      final response = await api.get('/services/$serviceId');

      if (response.containsKey('service')) {
        final watch = _watches[serviceId];
        if (watch != null && !watch.controller.isClosed) {
          watch.controller.add(response['service']);
        }
      }
    } catch (error) {
      print('[ServiceSync] Erro ao sincronizar: $error');
    }
  }

  /// Obter número de watches ativos
  int get activeWatches => _watches.length;

  /// Limpar todos os watches
  Future<void> clearAll() async {
    for (final serviceId in List.from(_watches.keys)) {
      await stopWatching(serviceId);
    }
  }
}

/// Watch interno para um serviço
class _ServiceWatch {
  final String serviceId;
  final StreamController<Map<String, dynamic>> controller;
  StreamSubscription<Map<String, dynamic>>? firebaseSubscription;
  Timer? pollingTimer;
  bool firebaseWorking = false;

  _ServiceWatch({
    required this.serviceId,
    required this.controller,
  });

  void dispose() {
    firebaseSubscription?.cancel();
    pollingTimer?.cancel();
    controller.close();
  }
}
