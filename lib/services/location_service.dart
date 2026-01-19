import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';

/// LocationService: Rastreamento contínuo de geolocalização com batching
/// - Captura GPS a cada 10m de movimento ou 30s (máximo)
/// - Envia batches a cada 5s ou 10 posições
/// - Otimizado para economizar bateria
class LocationService {
  static final LocationService _instance = LocationService._internal();

  factory LocationService() {
    return _instance;
  }

  LocationService._internal();

  StreamSubscription<Position>? _positionStream;
  final List<Map<String, dynamic>> _locationBuffer = [];
  Timer? _batchTimer;
  String? _activeServiceId;
  bool _isTracking = false;

  /// Solicitar permissões e iniciar rastreamento contínuo
  Future<void> startTracking(String serviceId) async {
    if (_isTracking && _activeServiceId == serviceId) {
      print('[Location] Já está rastreando serviço $serviceId');
      return;
    }

    _activeServiceId = serviceId;

    try {
      // 1. Verificar permissões
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        print('[Location] Permissão de localização negada permanentemente');
        throw Exception('Location permission denied forever');
      }

      if (permission == LocationPermission.denied) {
        print('[Location] Permissão de localização negada pelo usuário');
        throw Exception('Location permission denied');
      }

      // 2. Configurar stream de localização
      final LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.best, // GPS de alta precisão
        distanceFilter: 10, // Atualizar se moveu 10 metros
        timeLimit: Duration(seconds: 30), // Ou a cada 30 segundos
      );

      // 3. Iniciar listening
      _positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          _addToBuffer(position, serviceId);
        },
        onError: (error) {
          print('[Location] Stream error: $error');
          _stopStream();
        },
      );

      _isTracking = true;
      print('[Location] Rastreamento iniciado para serviço $serviceId');
    } catch (error) {
      print('[Location] Erro ao iniciar rastreamento: $error');
      _isTracking = false;
      rethrow;
    }
  }

  /// Adicionar posição ao buffer
  void _addToBuffer(Position position, String serviceId) {
    _locationBuffer.add({
      'lat': position.latitude,
      'lng': position.longitude,
      'accuracy': position.accuracy,
      'speed': position.speed,
      'altitude': position.altitude,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    // Enviar a cada 10 posições OU 5 segundos
    if (_locationBuffer.length >= 10) {
      _flush(serviceId);
    }

    // Timer para flush a cada 5s
    _batchTimer ??= Timer(Duration(seconds: 5), () => _flush(serviceId));
  }

  /// Enviar batch de localizações para o servidor
  Future<void> _flush(String serviceId) async {
    if (_locationBuffer.isEmpty || _activeServiceId == null) {
      return;
    }

    final batch = List<Map<String, dynamic>>.from(_locationBuffer);
    _locationBuffer.clear();
    _batchTimer?.cancel();
    _batchTimer = null;

    try {
      await ApiService.post('/location/batch', {
        'locations': batch,
        'service_id': serviceId,
      });

      print('[Location] Batch enviado: ${batch.length} posições');
    } catch (error) {
      // Retentar no próximo batch
      _locationBuffer.addAll(batch);
      print('[Location] Falha ao enviar batch: $error');
    }
  }

  /// Parar rastreamento
  Future<void> stopTracking() async {
    if (!_isTracking) {
      return;
    }

    try {
      // Cancelar stream
      await _positionStream?.cancel();
      _positionStream = null;

      // Enviar último batch
      if (_activeServiceId != null && _locationBuffer.isNotEmpty) {
        await _flush(_activeServiceId!);
      }

      // Limpar timers
      _batchTimer?.cancel();
      _batchTimer = null;

      _isTracking = false;
      _activeServiceId = null;

      print('[Location] Rastreamento parado');
    } catch (error) {
      print('[Location] Erro ao parar rastreamento: $error');
    }
  }

  /// Parar stream internamente
  void _stopStream() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  /// Verificar se está rastreando
  bool get isTracking => _isTracking;

  /// Obter serviço ativo
  String? get activeServiceId => _activeServiceId;

  /// Obter tamanho do buffer atual
  int get bufferSize => _locationBuffer.length;
}
