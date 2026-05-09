import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/maps/app_tile_layer.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/custom_alert.dart';
import '../../../services/api_service.dart';
import '../../../services/app_config_service.dart';
import '../../../services/data_gateway.dart';
import '../../../services/notification_service.dart';
import '../../../widgets/skeleton_loader.dart';

class ServiceOfferModal extends StatefulWidget {
  final String serviceId;
  final Map<String, dynamic>? initialData;
  final VoidCallback? onAccepted;
  final VoidCallback? onRejected;

  const ServiceOfferModal({
    super.key,
    required this.serviceId,
    this.initialData,
    this.onAccepted,
    this.onRejected,
  });

  @override
  State<ServiceOfferModal> createState() => _ServiceOfferModalState();
}

class _ServiceOfferModalState extends State<ServiceOfferModal>
    with WidgetsBindingObserver {
  static const int _providerResponseTimeoutSeconds = 30;
  final _api = ApiService();
  final MapController _mapController = MapController();

  Map<String, dynamic>? _serviceData;
  bool _isLoadingDetails = true;

  List<LatLng> _routePoints = [];
  String _routeDistance = '--';
  String _routeDuration = '--';
  bool _isLoadingAction = false;
  LatLng? _providerPoint;
  LatLng? _servicePoint;
  String? _providerAddress;
  String? _serviceAddress;
  bool _isLoadingAddresses = false;

  // Media State
  List<String> _photoUrls = [];
  List<String> _audioKeys = [];
  VideoPlayerController? _videoController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAudioPlaying = false;
  String? _playingAudioKey;
  String? _loadingAudioKey;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;

  // Timer for auto-close alinhado ao backend (default 30 seconds)
  Timer? _autoCloseTimer;
  Timer? _forceCloseTimer;
  Timer? _queueStatePollTimer;
  int _secondsRemaining = 30;
  int _initialTimeoutSeconds = 30;
  DateTime? _offerEndsAt;
  bool _hasResponded = false;
  bool _closed = false;

  // Notification Sound Player
  final AudioPlayer _notificationPlayer = AudioPlayer();

  String _friendlyAcceptErrorMessage(Object error) {
    int? statusCode;
    String rawMessage = error.toString();
    if (error is ApiException) {
      statusCode = error.statusCode;
      rawMessage = error.message;
    }
    final msg = rawMessage.toLowerCase();

    if (statusCode == 409 ||
        msg.contains('já foi aceito por outro prestador') ||
        msg.contains('ja foi aceito por outro prestador')) {
      return 'Oferta já aceita por outro prestador.';
    }
    if (statusCode == 410 ||
        msg.contains('oferta expirada') ||
        msg.contains('timeout')) {
      return 'Oferta expirada por tempo.';
    }
    if (statusCode == 403 ||
        msg.contains('rls') ||
        msg.contains('acesso negado') ||
        msg.contains('tentativa de modificar dado alheio')) {
      return 'Sem permissão para aceitar esta oferta (RLS).';
    }
    return 'Erro ao aceitar: $rawMessage';
  }

  bool _isLateReject(Object error) {
    if (error is ApiException && error.statusCode == 409) return true;
    final msg = error.toString().toLowerCase();
    return msg.contains('oferta não pôde ser recusada') ||
        msg.contains('oferta nao pode ser recusada') ||
        msg.contains('não pôde ser recusada a tempo') ||
        msg.contains('nao pode ser recusada a tempo');
  }

  String _friendlyRejectErrorMessage(Object error) {
    if (_isLateReject(error)) {
      return 'Oferta já não está mais disponível para recusa.';
    }
    if (error is ApiException && error.statusCode == 410) {
      return 'Oferta expirada por tempo.';
    }
    return 'Não foi possível confirmar a recusa. Tente novamente.';
  }

  double _resolveProviderNetAmount(Map<String, dynamic> s) {
    final direct =
        double.tryParse((s['provider_amount'] ?? '').toString()) ?? 0.0;
    if (direct > 0) return direct;

    final gross =
        double.tryParse(
          (s['price_estimated'] ?? s['price'] ?? s['total_price'] ?? 0)
              .toString(),
        ) ??
        0.0;
    if (gross <= 0) return 0.0;

    // Regra oficial: valor líquido do prestador = valor do serviço - comissão.
    final cfg = AppConfigService();
    final net = cfg.calculateNetGain(gross);
    if (net > 0) return double.parse(net.toStringAsFixed(2));

    // Fallback defensivo para não exibir zero quando houver valor bruto.
    return double.parse((gross * 0.85).toStringAsFixed(2));
  }

  DateTime? _parseExpiresAt(Map<String, dynamic>? data) {
    final raw = data?['expires_at'];
    if (raw == null) return null;
    try {
      if (raw is String) return DateTime.parse(raw).toUtc();
      if (raw is DateTime) return raw.toUtc();
    } catch (_) {}
    return null;
  }

  Future<int> _resolveTimeoutSeconds() async {
    final expiresAt = _parseExpiresAt(_serviceData);
    if (expiresAt != null) {
      final diff = expiresAt.difference(DateTime.now().toUtc()).inSeconds;
      return diff > 0 ? diff : 0;
    }
    return _providerResponseTimeoutSeconds;
  }

  Future<void> _initOfferTimeout() async {
    final expiresAt = _parseExpiresAt(_serviceData);
    if (expiresAt != null) {
      _offerEndsAt = expiresAt;
    } else {
      final timeoutSeconds = await _resolveTimeoutSeconds();
      _initialTimeoutSeconds = timeoutSeconds.clamp(1, 600);
      _offerEndsAt = DateTime.now().toUtc().add(
        Duration(seconds: _initialTimeoutSeconds),
      );
    }

    final remaining = _offerEndsAt == null
        ? _initialTimeoutSeconds
        : _offerEndsAt!.difference(DateTime.now().toUtc()).inSeconds;

    if (!mounted) return;
    setState(() {
      _secondsRemaining = remaining.clamp(0, 600);
      if (_secondsRemaining > 0) {
        _initialTimeoutSeconds = _secondsRemaining;
      }
    });

    debugPrint(
      '⏱️ [ServiceOfferModal] timeout init: serviceId=${widget.serviceId} expires_at=${expiresAt?.toIso8601String()} initial=$_initialTimeoutSeconds remaining=$_secondsRemaining',
    );

    _scheduleForceCloseFromDeadline();
  }

  void _scheduleForceCloseFromDeadline() {
    _forceCloseTimer?.cancel();
    final endsAt = _offerEndsAt;
    if (endsAt == null) return;

    final delay = endsAt.difference(DateTime.now().toUtc());
    if (delay <= Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _closed || _hasResponded) return;
        debugPrint(
          '⏱️ [ServiceOfferModal] deadline local já vencido. Forçando fechamento serviceId=${widget.serviceId}',
        );
        _autoReject();
      });
      return;
    }

    _forceCloseTimer = Timer(delay, () {
      if (!mounted || _closed || _hasResponded) return;
      debugPrint(
        '⏱️ [ServiceOfferModal] force-close timer disparou. serviceId=${widget.serviceId}',
      );
      _autoReject();
    });
  }

  Future<void> _loadDetails() async {
    try {
      final data = await _api.getServiceDetails(widget.serviceId);
      if (mounted) {
        setState(() {
          _serviceData = data;
          _isLoadingDetails = false;
        });
        await _ensureTaskName();
        _loadRoute();
        _loadMedia();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingDetails = false);
        // Show error or close?
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _playNotificationSound(); // Start looping sound immediately

    // ✅ REGISTRAR DELIVERED IMEDIATAMENTE AO ABRIR O MODAL (FOREGROUND)
    _api.logServiceEvent(
      widget.serviceId,
      'DELIVERED',
      'Offer Modal Opened (Foreground)',
    );

    _serviceData = widget.initialData;
    if (_serviceData != null && _serviceData!.containsKey('latitude')) {
      _isLoadingDetails = false;
      // Best-effort to resolve task name even when opened from push payload.
      _ensureTaskName();
      _loadRoute();
      _loadMedia();
    } else {
      _loadDetails();
    }
    _setupAudioPlayer();
    _initOfferTimeout();
    _startAutoCloseTimer();
    _startQueueStateMonitor();

    // Keep screen on
    WakelockPlus.enable();

    // Monitor backgrounding
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      debugPrint(
        '🚨 [ServiceOfferModal] App minimized during offer. Closing modal locally and keeping backend timeout active.',
      );
      _handleBackgroundSkip();
    }
  }

  Future<void> _handleBackgroundSkip() async {
    _closeModalLocal('background_skip', accepted: false);
    widget.onRejected?.call();
  }

  void _startAutoCloseTimer() {
    _autoCloseTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_hasResponded) {
        _autoCloseTimer?.cancel();
        return;
      }

      final endsAt =
          _offerEndsAt ??
          DateTime.now().toUtc().add(Duration(seconds: _secondsRemaining));
      final remaining = endsAt.difference(DateTime.now().toUtc()).inSeconds;

      if (remaining <= 0) {
        setState(() => _secondsRemaining = 0);
        _autoCloseTimer?.cancel();
        _autoReject();
        return;
      }

      setState(() {
        _offerEndsAt = endsAt;
        _secondsRemaining = remaining;
      });

      if (_secondsRemaining % 5 == 0) {
        debugPrint(
          '⏱️ [ServiceOfferModal] tick: serviceId=${widget.serviceId} remaining=$_secondsRemaining',
        );
      }
    });
  }

  void _closeModalLocal(String reason, {bool accepted = false}) {
    if (_closed) return;
    _closed = true;
    _hasResponded = true;
    _autoCloseTimer?.cancel();
    _forceCloseTimer?.cancel();
    _queueStatePollTimer?.cancel();
    _notificationPlayer.stop();

    debugPrint(
      '⏱️ [ServiceOfferModal] closing modal: reason=$reason serviceId=${widget.serviceId}',
    );

    if (!mounted) return;

    void tryPop() {
      if (!mounted) return;

      final localNavigator = Navigator.maybeOf(context);
      if (localNavigator != null && localNavigator.canPop()) {
        localNavigator.pop(accepted);
        return;
      }

      final rootNavigator = Navigator.maybeOf(context, rootNavigator: true);
      if (rootNavigator != null && rootNavigator.canPop()) {
        rootNavigator.pop(accepted);
      }
    }

    tryPop();
    WidgetsBinding.instance.addPostFrameCallback((_) => tryPop());
  }

  Future<void> _autoReject() async {
    if (_hasResponded) return;
    _closeModalLocal('timeout', accepted: false);

    // REMOVED: await _api.post('/services/${widget.serviceId}/skip', {});
    // Reason: Backend Alarm handles the timeout. Sending skip here cancels the alarm
    // and causes immediate re-dispatch (spam).

    // --- Log REJECTED Event (Audit v11) ---
    unawaited(
      _api
          .logServiceEvent(
            widget.serviceId,
            'REJECTED',
            'Offer Modal - Timeout (Auto-Close)',
          )
          .timeout(const Duration(seconds: 2))
          .catchError((e) {
            debugPrint(
              '⚠️ [ServiceOfferModal] Erro ao registrar REJECTED no timeout: $e',
            );
          }),
    );

    widget.onRejected?.call();
  }

  Future<void> _playNotificationSound() async {
    try {
      await _notificationPlayer.setReleaseMode(ReleaseMode.loop);
      // Ensure source is set before playing for stability
      await _notificationPlayer.setSource(AssetSource('sounds/chamado.mp3'));
      await _notificationPlayer.play(
        AssetSource('sounds/chamado.mp3'),
        volume: 1.0,
      );
    } catch (e) {
      debugPrint('🚨 [ServiceOfferModal] Error playing notification sound: $e');
    }
  }

  @override
  void dispose() {
    _notificationPlayer.stop(); // Ensure sound stops when modal closes
    _notificationPlayer.dispose();

    _autoCloseTimer?.cancel();
    _forceCloseTimer?.cancel();
    _queueStatePollTimer?.cancel();
    _videoController?.dispose();
    _audioPlayer.dispose();

    // Release screen lock
    WakelockPlus.disable();

    // Remove background observer
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  void _startQueueStateMonitor() {
    _queueStatePollTimer?.cancel();
    _queueStatePollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_syncQueueState());
    });
    unawaited(_syncQueueState());
  }

  Future<void> _syncQueueState() async {
    if (!mounted || _closed || _hasResponded) return;

    try {
      final offerState = await _api.dispatch.getActiveProviderOfferState(
        widget.serviceId,
      );

      if (!mounted || _closed || _hasResponded) return;

      if (offerState == null) {
        debugPrint(
          '⏱️ [ServiceOfferModal] queue row ausente. Fechando modal serviceId=${widget.serviceId}',
        );
        _closeModalLocal('queue_row_missing', accepted: false);
        widget.onRejected?.call();
        return;
      }

      final status = offerState.status;
      final deadlineAt = offerState.responseDeadlineAt?.toUtc();
      final now = DateTime.now().toUtc();

      if (status != 'notified') {
        debugPrint(
          '⏱️ [ServiceOfferModal] queue status mudou para $status. Fechando modal serviceId=${widget.serviceId}',
        );
        _closeModalLocal('queue_status_$status', accepted: false);
        widget.onRejected?.call();
        return;
      }

      if (deadlineAt != null) {
        final remaining = deadlineAt.difference(now).inSeconds;
        if (remaining <= 0) {
          debugPrint(
            '⏱️ [ServiceOfferModal] deadline expirado no banco. Fechando modal serviceId=${widget.serviceId}',
          );
          _closeModalLocal('queue_deadline_elapsed', accepted: false);
          widget.onRejected?.call();
          return;
        }

        if (mounted && !_closed) {
          setState(() {
            _offerEndsAt = deadlineAt;
            _secondsRemaining = remaining.clamp(0, 600);
          });
          _scheduleForceCloseFromDeadline();
        }
      }
    } catch (e) {
      debugPrint(
        '⚠️ [ServiceOfferModal] Falha ao sincronizar estado da fila: $e',
      );
    }
  }

  void _setupAudioPlayer() {
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isAudioPlaying = false;
          _audioPosition = Duration.zero;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _audioDuration = d);
    });

    _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _audioPosition = p);
    });
  }

  Future<void> _ensureTaskName() async {
    try {
      final s = _serviceData;
      if (s == null) return;
      final existing = (s['task_name'] ?? s['task_title'] ?? '')
          .toString()
          .trim();
      if (existing.isNotEmpty) return;

      final dynamic taskIdRaw = s['task_id'];
      final int? taskId = taskIdRaw is int
          ? taskIdRaw
          : int.tryParse(taskIdRaw?.toString() ?? '');
      if (taskId == null) return;

      final name = await DataGateway().loadTaskNameById(taskId) ?? '';
      if (name.isEmpty) return;

      if (!mounted) return;
      setState(() {
        _serviceData = {...s, 'task_name': name};
      });
    } catch (_) {
      // ignore best-effort
    }
  }

  Future<void> _loadRoute() async {
    try {
      final s = _serviceData!;
      final payloadDistanceKm =
          double.tryParse(s['distance_km']?.toString() ?? '') ?? 0;
      final payloadEstimatedMinutes =
          int.tryParse(s['estimated_minutes']?.toString() ?? '') ?? 0;

      if (mounted) {
        setState(() {
          if (payloadDistanceKm > 0) {
            _routeDistance = payloadDistanceKm >= 1
                ? '${payloadDistanceKm.toStringAsFixed(1)} km'
                : '${(payloadDistanceKm * 1000).round()} m';
          }
          if (payloadEstimatedMinutes > 0) {
            _routeDuration = '$payloadEstimatedMinutes min';
          }
        });
      }

      // Coordinates from service (Destination)
      final destLat = double.tryParse(s['latitude']?.toString() ?? '0') ?? 0;
      final destLng = double.tryParse(s['longitude']?.toString() ?? '0') ?? 0;

      // Coordinates from provider (Origin) - usually passed in data or we assume current
      // Ideally the offer data contains distance/duration pre-calculated, but if not we calc it.
      // If we don't have provider lat/lon in data, we can't easily draw route without geolocation permission here.
      // For a modal, maybe just showing the destination marker is enough if we can't get current loc quickly?
      // Let's try to use the data if available.

      double provLat =
          double.tryParse(s['provider_lat']?.toString() ?? '0') ?? 0;
      double provLon =
          double.tryParse(s['provider_lon']?.toString() ?? '0') ?? 0;

      if (provLat == 0 || provLon == 0) {
        // Fallback: Get current location if not in payload
        try {
          debugPrint(
            '📍 [ServiceOfferModal] Finding precise location for route...',
          );
          // ✅ Usar apenas lastKnownPosition com timeout curto para não travar o modal
          Position? pos = await Geolocator.getLastKnownPosition(
            forceAndroidLocationManager:
                true, // Garante mais rapidez no Android
          );

          if (pos != null) {
            provLat = pos.latitude;
            provLon = pos.longitude;
          }
        } catch (e) {
          debugPrint(
            '⚠️ [ServiceOfferModal] Could not get GPS for route: $e. Using destination only.',
          );
        }
      }

      if (destLat == 0 || destLng == 0 || provLat == 0 || provLon == 0) {
        return;
      }

      if (mounted) {
        setState(() {
          _providerPoint = LatLng(provLat, provLon);
          _servicePoint = LatLng(destLat, destLng);
        });
      }

      // Best-effort: resolve readable addresses for both points (provider + service).
      _loadAddressesIfNeeded(
        providerLat: provLat,
        providerLon: provLon,
        serviceLat: destLat,
        serviceLon: destLng,
      );

      final url = Uri.parse(
        'http://router.project-osrm.org/route/v1/driving/$provLon,$provLat;$destLng,$destLat?overview=full&geometries=geojson',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry'];
          final coordinates = geometry['coordinates'] as List;

          final points = coordinates
              .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
              .toList();

          final distanceMeters = route['distance'] as num;
          final durationSeconds = route['duration'] as num;

          if (mounted) {
            setState(() {
              _routePoints = points;
              _routeDistance = distanceMeters >= 1000
                  ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
                  : '${distanceMeters.round()} m';
              _routeDuration = '${(durationSeconds / 60).round()} min';
            });

            // Fit bounds
            if (points.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  try {
                    final bounds = LatLngBounds.fromPoints(points);
                    _mapController.fitCamera(
                      CameraFit.bounds(
                        bounds: bounds,
                        padding: const EdgeInsets.all(20),
                      ),
                    );
                  } catch (_) {}
                }
              });
            }
          }
        }
      } else {
        // Fallback distance only (no polyline)
        final distM = Geolocator.distanceBetween(
          provLat,
          provLon,
          destLat,
          destLng,
        );
        if (mounted) {
          setState(() {
            _routeDistance = distM >= 1000
                ? '${(distM / 1000).toStringAsFixed(1)} km'
                : '${distM.round()} m';
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading route in modal: $e');
      // if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  String _formatReverseGeocode(Map<String, dynamic> result) {
    final road = (result['road'] ?? result['street'] ?? '').toString().trim();
    final houseNumber = (result['house_number'] ?? result['number'] ?? '')
        .toString()
        .trim();
    final suburb =
        (result['suburb'] ??
                result['neighbourhood'] ??
                result['district'] ??
                '')
            .toString()
            .trim();

    final line1 = <String>[];
    if (road.isNotEmpty) line1.add(road);
    if (houseNumber.isNotEmpty) line1.add(houseNumber);
    final firstLine = line1.join(', ').trim();

    if (firstLine.isNotEmpty && suburb.isNotEmpty) {
      return '$firstLine • $suburb';
    }
    if (firstLine.isNotEmpty) return firstLine;
    if (suburb.isNotEmpty) return suburb;

    final displayName = (result['display_name'] ?? '').toString().trim();
    if (displayName.isNotEmpty) {
      final tokens = displayName
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (tokens.isNotEmpty) {
        return tokens.take(3).join(' • ');
      }
      return displayName;
    }
    return 'Endereço não disponível';
  }

  Future<void> _loadAddressesIfNeeded({
    required double providerLat,
    required double providerLon,
    required double serviceLat,
    required double serviceLon,
  }) async {
    if (_isLoadingAddresses) return;
    if (_providerAddress != null && _serviceAddress != null) return;
    if (!mounted) return;

    setState(() => _isLoadingAddresses = true);
    try {
      final providerPoint = LatLng(providerLat, providerLon);
      final servicePoint = LatLng(serviceLat, serviceLon);

      // Service address: prefer DB field when it is informative.
      final s = _serviceData;
      final String existingServiceAddr = (s?['address'] ?? '')
          .toString()
          .trim();
      if (existingServiceAddr.isNotEmpty &&
          existingServiceAddr.toLowerCase() != 'localização atual') {
        _serviceAddress ??= existingServiceAddr;
      }

      final futures = <Future<void>>[];
      if (_providerAddress == null) {
        futures.add(() async {
          try {
            final res = await _api.reverseGeocode(
              providerPoint.latitude,
              providerPoint.longitude,
            );
            if (!mounted) return;
            setState(() => _providerAddress = _formatReverseGeocode(res));
          } catch (_) {
            if (!mounted) return;
            setState(() => _providerAddress = _formatReverseGeocode({}));
          }
        }());
      }

      if (_serviceAddress == null) {
        futures.add(() async {
          try {
            final res = await _api.reverseGeocode(
              servicePoint.latitude,
              servicePoint.longitude,
            );
            if (!mounted) return;
            setState(() => _serviceAddress = _formatReverseGeocode(res));
          } catch (_) {
            if (!mounted) return;
            setState(() => _serviceAddress = _formatReverseGeocode({}));
          }
        }());
      }

      if (futures.isNotEmpty) {
        await Future.wait(futures);
      }
    } finally {
      if (mounted) setState(() => _isLoadingAddresses = false);
    }
  }

  Future<void> _loadMedia() async {
    final data = _serviceData!;
    try {
      // Photos
      if (data['photos'] != null && (data['photos'] as List).isNotEmpty) {
        final keys = List<String>.from(data['photos']);
        final urls = <String>[];
        for (final key in keys) {
          try {
            final url = await _api.getMediaViewUrl(key);
            urls.add(url);
          } catch (_) {}
        }
        if (mounted) setState(() => _photoUrls = urls);
      }

      // Video
      if (data['video'] != null && data['video'].toString().isNotEmpty) {
        try {
          final videoKey = data['video'].toString();
          final videoUrl = await _api.getMediaViewUrl(videoKey);
          final controller = VideoPlayerController.networkUrl(
            Uri.parse(videoUrl),
          );
          await controller.initialize();
          if (mounted) setState(() => _videoController = controller);
        } catch (_) {}
      }

      // Audio
      if (data['audios'] != null && (data['audios'] as List).isNotEmpty) {
        if (mounted) {
          setState(() => _audioKeys = List<String>.from(data['audios']));
        }
      } else if (data['audio'] != null && data['audio'].toString().isNotEmpty) {
        if (mounted) setState(() => _audioKeys = [data['audio'].toString()]);
      }
    } catch (_) {}
  }

  Future<void> _toggleAudioPlay(String key) async {
    if (_loadingAudioKey != null) return;

    try {
      if (_playingAudioKey == key) {
        if (_isAudioPlaying) {
          await _audioPlayer.pause();
          setState(() => _isAudioPlaying = false);
        } else {
          await _audioPlayer.resume();
          setState(() => _isAudioPlaying = true);
        }
        return;
      }

      await _audioPlayer.stop();
      setState(() {
        _isAudioPlaying = false;
        _playingAudioKey = null;
        _loadingAudioKey = key;
        _audioPosition = Duration.zero;
        _audioDuration = Duration.zero;
      });

      final bytes = await _api.getMediaBytes(key);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/modal_audio_${key.hashCode}.m4a');

      if (!await file.exists()) {
        await file.writeAsBytes(bytes);
      }

      await _audioPlayer.play(DeviceFileSource(file.path));
      setState(() {
        _playingAudioKey = key;
        _isAudioPlaying = true;
        _loadingAudioKey = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingAudioKey = null;
          _playingAudioKey = null;
          _isAudioPlaying = false;
        });
      }
    }
  }

  Future<void> _acceptService() async {
    if (_hasResponded || _isLoadingAction) return;

    // ✅ PARAR SOM IMEDIATAMENTE
    _notificationPlayer.stop();

    debugPrint(
      'ServiceOfferModal: _acceptService called for ${widget.serviceId}',
    );
    setState(() => _isLoadingAction = true);
    final serviceId = widget.serviceId;

    // if (serviceId == null) return;

    try {
      debugPrint('ServiceOfferModal: Calling API acceptService...');

      // Não bloquear o aceite principal por causa de log auxiliar.
      unawaited(
        _api
            .logServiceEvent(
              serviceId,
              'ACCEPTED',
              'Offer Modal - User Tapped Accept',
            )
            .timeout(const Duration(seconds: 2))
            .catchError((e) {
              debugPrint(
                '⚠️ [ServiceOfferModal] Erro ao registrar ACCEPTED pré-aceite: $e',
              );
            }),
      );

      const maxAttempts = 2;
      Object? lastError;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          await _api.dispatch
              .acceptService(serviceId)
              .timeout(const Duration(seconds: 8));
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
          debugPrint(
            '⚠️ [ServiceOfferModal] acceptService falhou '
            'attempt=$attempt/$maxAttempts serviceId=$serviceId erro=$e',
          );
          if (attempt < maxAttempts) {
            await Future.delayed(const Duration(milliseconds: 250));
          }
        }
      }
      if (lastError != null) {
        throw lastError;
      }

      debugPrint('ServiceOfferModal: API acceptService success!');
      _hasResponded = true;

      if (mounted) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        _closeModalLocal('accepted', accepted: true);
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('Serviço aceito com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onAccepted?.call();
        });
      }

      // Stop persistent notifications in background (não bloquear fechamento do modal).
      final ns = NotificationService();
      ns.stopPersistentNotification(serviceId);
      unawaited(ns.cancelAll());
    } catch (e) {
      debugPrint('ServiceOfferModal: Error accepting service: $e');
      if (mounted) {
        final friendly = _friendlyAcceptErrorMessage(e);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendly)));
      }
    } finally {
      if (mounted) setState(() => _isLoadingAction = false);
    }
  }

  Future<void> _rejectService() async {
    final serviceId = widget.serviceId;
    if (_isLoadingAction) return;

    final confirm = await CustomAlert.show(
      context: context,
      title: 'Recusar Serviço',
      content: 'Tem certeza que deseja recusar este serviço?',
      confirmText: 'Recusar',
      cancelText: 'Cancelar',
      isDestructive: true,
      confirmColor: AppTheme.primaryYellow,
      confirmTextColor: Colors.black, // Prerto

      icon: LucideIcons.xCircle,
    );

    if (confirm == true) {
      if (mounted) setState(() => _isLoadingAction = true);
      _autoCloseTimer?.cancel();
      _forceCloseTimer?.cancel();
      _queueStatePollTimer?.cancel();

      // ✅ PARAR SOM IMEDIATAMENTE
      _notificationPlayer.stop();

      try {
        await _api.dispatch
            .rejectService(serviceId)
            .timeout(const Duration(seconds: 4));

        _hasResponded = true;

        // --- Log REJECTED Event (Audit v11) ---
        unawaited(
          _api
              .logServiceEvent(
                serviceId,
                'REJECTED',
                'Offer Modal - User Tapped Reject',
              )
              .timeout(const Duration(seconds: 2))
              .catchError((e) {
                debugPrint(
                  '⚠️ [ServiceOfferModal] Erro ao registrar REJECTED manual: $e',
                );
              }),
        );

        // Stop persistent notifications
        NotificationService().stopPersistentNotification(serviceId);

        if (mounted) {
          _closeModalLocal('rejected', accepted: false);
          widget.onRejected?.call();
        }
      } catch (e) {
        if (_isLateReject(e)) {
          _hasResponded = true;
          NotificationService().stopPersistentNotification(serviceId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_friendlyRejectErrorMessage(e))),
            );
            _closeModalLocal('late_reject', accepted: false);
            widget.onRejected?.call();
          }
          return;
        }

        if (!_closed) {
          _startQueueStateMonitor();
          _scheduleForceCloseFromDeadline();
          _startAutoCloseTimer();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_friendlyRejectErrorMessage(e))),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoadingAction = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingDetails) {
      return Dialog(
        child: Container(
          padding: const EdgeInsets.all(32),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Carregando oferta...'),
            ],
          ),
        ),
      );
    }

    if (_serviceData == null) {
      return Dialog(
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text('Erro ao carregar oferta.'),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).pop(),
                child: const Text('Fechar'),
              ),
            ],
          ),
        ),
      );
    }

    final s = _serviceData!;
    final lat = double.tryParse(s['latitude']?.toString() ?? '0') ?? 0;
    final lon = double.tryParse(s['longitude']?.toString() ?? '0') ?? 0;
    final hasMap = lat != 0 && lon != 0;
    final String serviceTitle =
        [
              s['task_name'],
              s['task_title'],
              s['service_name'],
              s['category_name'],
              s['profession'],
            ]
            .map((value) => (value ?? '').toString().trim())
            .firstWhere((value) => value.isNotEmpty, orElse: () => 'Serviço');
    final String? clientNote =
        (s['description'] ?? '').toString().trim().isNotEmpty
        ? (s['description']).toString().trim()
        : null;
    final String serviceSubtitle =
        [s['category_name'], s['profession'], s['service_name']]
            .map((value) => (value ?? '').toString().trim())
            .firstWhere((value) => value.isNotEmpty, orElse: () => 'Serviço');
    final String providerAddressText =
        _providerAddress?.trim().isNotEmpty == true
        ? _providerAddress!.trim()
        : 'Sua localização atual';
    final String serviceAddressText = _serviceAddress?.trim().isNotEmpty == true
        ? _serviceAddress!.trim()
        : ((s['address'] ?? '').toString().trim().isNotEmpty
              ? (s['address']).toString().trim()
              : 'Endereço do serviço não informado');

    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.black, width: 3),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height * 0.95,
            maxHeight: MediaQuery.of(context).size.height * 0.95,
            maxWidth: MediaQuery.of(context).size.width,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.bellRing,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nova Oferta de Serviço',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Revise os detalhes e responda à solicitação.',
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox.shrink(),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Map
                      if (hasMap)
                        Container(
                          height: 250, // Aumentado de 180 para 250
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: LatLng(lat, lon),
                                initialZoom: 14,
                                interactionOptions: const InteractionOptions(
                                  flags: InteractiveFlag.none,
                                ),
                              ),
                              children: [
                                AppTileLayer.standard(
                                  mapboxToken: SupabaseConfig.mapboxToken,
                                ),
                                PolylineLayer(
                                  polylines: [
                                    if (_routePoints.isNotEmpty)
                                      Polyline(
                                        points: _routePoints,
                                        strokeWidth: 4.0,
                                        color: Colors.blue,
                                      ),
                                  ],
                                ),
                                MarkerLayer(
                                  markers: [
                                    if (_providerPoint != null)
                                      Marker(
                                        point: _providerPoint!,
                                        child: const Icon(
                                          Icons.location_on,
                                          color: Colors.green,
                                          size: 30,
                                        ),
                                      ),
                                    if (_servicePoint != null)
                                      Marker(
                                        point: _servicePoint!,
                                        child: const Icon(
                                          Icons.location_on,
                                          color: Colors.blue,
                                          size: 30,
                                        ),
                                      )
                                    else
                                      Marker(
                                        point: LatLng(lat, lon),
                                        child: const Icon(
                                          Icons.location_on,
                                          color: Colors.blue,
                                          size: 30,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Title & Description
                      Text(
                        serviceTitle,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        serviceSubtitle,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      if (clientNote != null && clientNote != serviceTitle) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Observação do cliente',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey[700],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                clientNote,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Stats Row
                      Row(
                        children: [
                          Expanded(
                            child: () {
                              final double net = _resolveProviderNetAmount(s);

                              return _buildStatItem(
                                LucideIcons.wallet,
                                'Seu Ganho',
                                'R\$ ${net.toStringAsFixed(2)}',
                                Colors.black,
                                textColor: Colors.black,
                                backgroundColor: AppTheme.primaryYellow,
                                valueFontSize: 28,
                                subtitle: null,
                                subtitleIcon: null,
                              );
                            }(),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatItem(
                              LucideIcons.mapPin,
                              'Distância',
                              _routeDistance,
                              Colors.white, // White background
                              textColor: Colors.black, // Black text
                              backgroundColor: Colors.white,
                              valueFontSize: 16,
                              subtitle:
                                  _routeDuration.isNotEmpty &&
                                      _routeDuration != '--'
                                  ? 'Tempo: $_routeDuration'
                                  : null,
                              subtitleIcon: LucideIcons.clock,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Addresses (provider + service) with distinct markers
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 18,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _isLoadingAddresses &&
                                          _providerAddress == null
                                      ? 'Carregando seu endereço...'
                                      : providerAddressText,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 18,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _isLoadingAddresses && _serviceAddress == null
                                      ? 'Carregando endereço do serviço...'
                                      : serviceAddressText,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Media
                      if (_photoUrls.isNotEmpty) ...[
                        const Text(
                          'Fotos:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 80,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _photoUrls.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, i) => ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: _photoUrls[i],
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                memCacheWidth: 200,
                                maxWidthDiskCache: 400,
                                placeholder: (context, url) =>
                                    BaseSkeleton(width: 80, height: 80),
                                errorWidget: (context, url, error) =>
                                    const Icon(Icons.error),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      if (_audioKeys.isNotEmpty) ...[
                        const Text(
                          'Áudio:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ..._audioKeys.asMap().entries.map(
                          (e) => _buildAudioPlayer(e.value, e.key),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),

              const Divider(height: 1),

              // Actions
              Padding(
                padding: const EdgeInsets.all(16),
                child: _isLoadingAction
                    ? const Center(child: CircularProgressIndicator())
                    : Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _rejectService,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black,
                                side: const BorderSide(
                                  color: Colors.black,
                                  width: 2,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              child: const Text('RECUSAR'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                debugPrint(
                                  'ServiceOfferModal: ACCEPT Button Pressed!',
                                );
                                _acceptService();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.blue[600], // Premium Blue
                                foregroundColor: Colors.white, // White text
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                elevation: 0,
                              ),
                              child: Container(
                                height: 56,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    const Align(
                                      alignment: Alignment.center,
                                      child: Text(
                                        'Aceitar',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: SizedBox(
                                        width: 32,
                                        height: 32,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            CircularProgressIndicator(
                                              value: _initialTimeoutSeconds <= 0
                                                  ? 0
                                                  : (_secondsRemaining /
                                                            _initialTimeoutSeconds)
                                                        .clamp(0.0, 1.0),
                                              strokeWidth: 3,
                                              color: Colors.white,
                                              backgroundColor: Colors.white24,
                                            ),
                                            Text(
                                              '${_secondsRemaining}s',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(
    IconData icon,
    String label,
    String value,
    Color color, {
    double valueFontSize = 16,
    Color? backgroundColor,
    Color? textColor,
    String? subtitle,
    IconData? subtitleIcon,
  }) {
    final effectiveTextColor = textColor ?? color;
    final effectiveBgColor = backgroundColor ?? color.withOpacity(0.1);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: effectiveBgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: effectiveTextColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(color: effectiveTextColor, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: effectiveTextColor,
              fontWeight: FontWeight.bold,
              fontSize: valueFontSize,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (subtitleIcon != null) ...[
                  Icon(
                    subtitleIcon,
                    size: 12,
                    color: effectiveTextColor.withOpacity(0.8),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  subtitle,
                  style: TextStyle(
                    color: effectiveTextColor.withOpacity(0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAudioPlayer(String key, int index) {
    final isPlaying = _playingAudioKey == key && _isAudioPlaying;
    final isLoading = _loadingAudioKey == key;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              isLoading
                  ? Icons.hourglass_empty
                  : (isPlaying ? Icons.pause : Icons.play_arrow),
            ),
            onPressed: () => _toggleAudioPlay(key),
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
            color: Colors.black87,
          ),
          const SizedBox(width: 8),
          Text('Áudio ${index + 1}'),
          if (isPlaying) ...[
            const Spacer(),
            Text(
              '${_audioPosition.inSeconds}/${_audioDuration.inSeconds}s',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }
}
