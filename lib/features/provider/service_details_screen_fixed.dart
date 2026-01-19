import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/custom_alert.dart';
import '../../services/api_service.dart';
import '../../services/realtime_service.dart';
import '../../widgets/skeleton_loader.dart';
import 'finish_service_screen.dart';
import '../../widgets/proof_video_player.dart';

class ServiceDetailsScreen extends StatefulWidget {
  final String serviceId;
  final int? timeoutSeconds;
  final Map<String, dynamic>? initialService;

  const ServiceDetailsScreen({
    super.key,
    required this.serviceId,
    this.timeoutSeconds,
    this.initialService,
  });

  @override
  State<ServiceDetailsScreen> createState() => _ServiceDetailsScreenState();
}

class _ServiceDetailsScreenState extends State<ServiceDetailsScreen>
    with WidgetsBindingObserver {
  final _api = ApiService();
  final _realtime = RealtimeService();
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _service;
  Timer? _refreshTimer;

  // Route & Map State
  final MapController _mapController = MapController();
  LatLng? _currentPosition;
  List<LatLng> _routePoints = [];
  String _routeDistance = '--';
  String _routeDuration = '--';
  bool _isRouteLoading = false; // New loading state for route

  // Media State
  List<String> _photoUrls = [];
  List<String> _audioKeys = [];
  VideoPlayerController? _videoController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAudioPlaying = false; // Tracks if player is actually playing
  String? _playingAudioKey; // Tracks which audio is current
  String? _loadingAudioKey; // Tracks which audio is loading
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;
  Timer? _timeoutTimer;

  bool _isNavigatingToPayment = false;
  bool _hasShownPaymentDialog = false;

  void _checkClientAutoNavigation() {
    // Safety check: Only run for clients
    if (_api.role != 'client') return;

    if (_service != null) {
      final status = _service!['status'];
      // Never show payment dialog for canceled services
      if (status == 'canceled' || status == 'cancelled') return;

      final paymentStatus = _service!['payment_remaining_status'];

      // Check if we need to pay remaining 70%
      if (status == 'in_progress' && paymentStatus != 'paid') {
        final total =
            double.tryParse(_service!['price_estimated']?.toString() ?? '0') ??
            0.0;
        final upfront =
            double.tryParse(_service!['price_upfront']?.toString() ?? '0') ??
            (total * 0.3);
        final remaining = total - upfront;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isNavigatingToPayment && !_hasShownPaymentDialog) {
            _hasShownPaymentDialog = true;
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Pagamento Restante'),
                content: Text(
                  'O serviço está em andamento. Deseja realizar o pagamento do valor restante (R\$ ${remaining.toStringAsFixed(2)}) agora?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Depois'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _navigateToPayment(remaining, total);
                    },
                    child: const Text('Pagar Agora'),
                  ),
                ],
              ),
            );
          }
        });
      }
    }
  }

  void _navigateToPayment(double remaining, double total) {
    if (!_isNavigatingToPayment) {
      _isNavigatingToPayment = true;
      context
          .push(
            '/payment/${widget.serviceId}',
            extra: {
              'serviceId': widget.serviceId,
              'type': 'remaining',
              'amount': remaining,
              'total': total,
            },
          )
          .then((_) {
            _isNavigatingToPayment = false;
            _loadDetails(); // Reload when coming back
          });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialService != null) {
      _service = widget.initialService;
      _isLoading = false;
    }
    _setupAudioPlayer();
    _setupRealtime();
    _loadDetails();
    if (widget.timeoutSeconds != null) {
      _startTimeoutTimer();
    }
    // Redundancy: refresh every 30s
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _loadDetails();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadDetails();
      _realtime.connect(); // Ensure socket is connected
    }
  }

  void _startTimeoutTimer() {
    _timeoutTimer = Timer(Duration(seconds: widget.timeoutSeconds!), () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Oferta expirada! Encaminhando para próximo prestador...',
            ),
          ),
        );
        Navigator.pop(context);
      }
    });
  }

  void _setupRealtime() {
    _realtime.connect();
    _realtime.joinService(widget.serviceId);
    _realtime.on('service_updated', _handleServiceUpdate);
    _realtime.on('service.updated', _handleServiceUpdate);
  }

  void _handleServiceUpdate(dynamic data) {
    if (mounted && data['id'].toString() == widget.serviceId) {
      _loadDetails();
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _timeoutTimer?.cancel();
    _audioPlayer.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _loadRoute() async {
    setState(() => _isRouteLoading = true);
    try {
      // 1. Get current position (Request permission if needed)
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _isRouteLoading = false);
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium, // Reduce accuracy requirement speed
        ),
      );

      if (!mounted) return;
      debugPrint('[ROUTE] Current Position: ${position.latitude}, ${position.longitude}');
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });

      // 2. Get service position
      if (_service != null) {
        final destLat = double.tryParse(_service!['latitude']?.toString() ?? '0') ?? 0;
        final destLng = double.tryParse(_service!['longitude']?.toString() ?? '0') ?? 0;
        
        debugPrint('[ROUTE] Destination: $destLat, $destLng');

        if (destLat == 0 && destLng == 0) {
           debugPrint('[ROUTE] Aborting: Destination is 0,0');
           return;
        }

        // 3. Fetch route from OSRM
        final url = Uri.parse(
          'http://router.project-osrm.org/route/v1/driving/${position.longitude},${position.latitude};$destLng,$destLat?overview=full&geometries=geojson',
        );
        debugPrint('[ROUTE] Fetching: $url');

        final response = await http.get(url);
        debugPrint('[ROUTE] Response: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
            final route = data['routes'][0];
            final geometry = route['geometry'];
            final coordinates = geometry['coordinates'] as List;

            // Extract points
            final points = coordinates
                .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
                .toList();

            // Extract distance and duration
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

              // Fit bounds to show entire route
              if (points.isNotEmpty) {
                final bounds = LatLngBounds.fromPoints(points);
                
                // Check if bounds represent a single point (degenerate)
                // to avoid 'zoom.isFinite' assertion error in flutter_map
                if (bounds.north == bounds.south && bounds.east == bounds.west) {
                  _mapController.move(bounds.center, 15.0);
                } else {
                  _mapController.fitCamera(
                    CameraFit.bounds(
                      bounds: bounds,
                      padding: const EdgeInsets.all(40),
                    ),
                  );
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading route: $e');
    } finally {
      if (mounted) {
        setState(() => _isRouteLoading = false);
      }
    }
  }

  Future<void> _loadDetails() async {
    // Only show full loading state if we don't have any data
    if (_service == null) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final data = await _api.getServiceDetails(widget.serviceId);
      if (mounted) {
        setState(() {
          _service = data;
          _isLoading = false;
        });
        // Load route after loading details
        _loadRoute();
        _loadMedia(data);
        _checkClientAutoNavigation();
      }
    } catch (e) {
      if (mounted) {
        // If we have data (e.g. from notification), keep showing it but warn user
        if (_service != null) {
          debugPrint('Error updating service details: $e');
          // Optional: Show snackbar
          // ScaffoldMessenger.of(context).showSnackBar(
          //   SnackBar(content: Text('Não foi possível atualizar os detalhes do serviço')),
          // );
        } else {
          setState(() {
            _error = e.toString();
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _loadMedia(Map<String, dynamic> data) async {
    try {
      // 1. Photos
    if (data['photos'] != null && (data['photos'] as List).isNotEmpty) {
      final keys = List<String>.from(data['photos']);
      final urls = <String>[];
      final tempDir = await getTemporaryDirectory();

      for (final key in keys) {
        try {
          final file = File('${tempDir.path}/service_photo_${key.hashCode}.jpg');
          if (await file.exists()) {
            urls.add(file.path);
          } else {
            final bytes = await _api.getMediaBytes(key);
            await file.writeAsBytes(bytes);
            urls.add(file.path);
          }
        } catch (_) {
          // Fallback to URL if bytes fail or other error
          try {
            final url = await _api.getMediaViewUrl(key);
            urls.add(url);
          } catch (__) {}
        }
      }
      if (mounted) {
        setState(() {
          _photoUrls = urls;
        });
      }
    }

      // 2. Video
    if (data['video'] != null && data['video'].toString().isNotEmpty) {
      try {
        final videoKey = data['video'].toString();
        final videoUrl = await _api.getMediaViewUrl(videoKey);

        final controller = VideoPlayerController.networkUrl(
          Uri.parse(videoUrl),
        );
        await controller.initialize();

        if (mounted) {
          if (_videoController != null) {
            await _videoController!.dispose();
          }
          setState(() {
            _videoController = controller;
          });
        } else {
          await controller.dispose();
        }
      } catch (e) {
          debugPrint('Error loading video: $e');
        }
      }

      // 3. Audio
      // Check for multiple audios first, then single
      if (data['audios'] != null && (data['audios'] as List).isNotEmpty) {
        if (mounted) {
          setState(() {
            _audioKeys = List<String>.from(data['audios']);
          });
        }
      } else if (data['audio'] != null && data['audio'].toString().isNotEmpty) {
        if (mounted) {
          setState(() {
            _audioKeys = [data['audio'].toString()];
          });
        }
      }
    } catch (e) {
      debugPrint('Error processing media: $e');
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'in_progress':
        return Colors.purple;
      case 'waiting_client_confirmation':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'canceled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Pendente';
      case 'accepted':
        return 'Aceito';
      case 'in_progress':
        return 'Em Andamento';
      case 'waiting_client_confirmation':
        return 'Aguardando Validação';
      case 'completed':
        return 'Concluído';
      case 'canceled':
        return 'Cancelado';
      default:
        return status;
    }
  }

  Future<void> _rejectService() async {
    final confirm = await CustomAlert.show(
      context: context,
      title: 'Recusar Serviço',
      content:
          'Tem certeza que deseja recusar este serviço? Ele não aparecerá mais para você.',
      confirmText: 'Recusar',
      cancelText: 'Cancelar',
      isDestructive: true,
      icon: LucideIcons.xCircle,
    );

    if (confirm == true) {
      try {
        await _api.rejectService(widget.serviceId);
        if (mounted) {
          context.pop(true); // Return true to indicate change
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Erro ao recusar: $e')));
        }
      }
    }
  }

  Future<void> _acceptService() async {
    setState(() => _isLoading = true);
    try {
      await _api.acceptService(widget.serviceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Serviço aceito com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        // Close screen after accepting, so provider goes back to home/list
        if (mounted) {
          context.pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao aceitar: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _startService() async {
    if (_service == null) return;

    setState(() => _isLoading = true);

    try {
      // 1. Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Permissão de localização negada. Necessário para iniciar o serviço.';
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw 'Permissões de localização permanentemente negadas. Habilite nas configurações.';
      }

      // 2. Get current position
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      // 3. Check distance
      final requireLocationCheck =
          _service!['config_require_location_start'] == true;

      if (requireLocationCheck) {
        final serviceLat =
            double.tryParse(_service!['latitude']?.toString() ?? '0') ?? 0;
        final serviceLng =
            double.tryParse(_service!['longitude']?.toString() ?? '0') ?? 0;

        if (serviceLat == 0 && serviceLng == 0) {
          throw 'Localização do serviço inválida.';
        }

        final distanceInMeters = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          serviceLat,
          serviceLng,
        );

        debugPrint('Distance to service: $distanceInMeters meters');

      final precision = position.accuracy;
      final tolerance = precision > 50 ? precision * 1.5 : 100.0;

      // Tolerance based on precision (min 100m)
      if (distanceInMeters > tolerance) {
        throw 'Você está a ${distanceInMeters.round()}m do local. Aproxime-se mais (limite de ${tolerance.round()}m para sua precisão atual de ${precision.round()}m).';
      }
    }

    await _api.updateServiceStatus(widget.serviceId, 'in_progress');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Serviço iniciado com sucesso!')),
      );
      _loadDetails();
    }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao iniciar: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _notifyArrival() async {
     setState(() => _isLoading = true);
    try {
      await _api.arriveService(widget.serviceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cliente notificado da sua chegada!')),
        );
        _loadDetails();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao notificar chegada: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startNavigationToClient() async {
    setState(() => _isLoading = true);
    try {
      // 1. Update status to 'on_way'
      await _api.updateServiceStatus(widget.serviceId, 'on_way');
      
      // 2. Start location tracking
      if (_api.userId != null) {
        _realtime.startLocationUpdates(_api.userId!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Status atualizado para: A Caminho. Compartilhamento de local ativado.')),
        );
        _loadDetails();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao iniciar deslocamento: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestCompletion() async {
    if (_service == null) return;
    _showCompletionDialog();
  }

  Future<void> _showCompletionDialog() async {
    // Stop tracking when finishing
    _realtime.stopLocationUpdates();

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FinishServiceScreen(serviceId: widget.serviceId),
      ),
    );

    if (result == true) {
      _loadDetails();
    }
  }



  Future<void> _toggleAudioPlay(String key) async {
    if (_loadingAudioKey != null) return;

    try {
      // Toggle existing
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

      // Play new
      await _audioPlayer.stop();
      setState(() {
        _isAudioPlaying = false;
        _playingAudioKey = null;
        _loadingAudioKey = key;
        _audioPosition = Duration.zero;
        _audioDuration = Duration.zero;
    });

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/service_audio_${key.hashCode}.m4a');

    if (!await file.exists()) {
      final bytes = await _api.getMediaBytes(key);
      await file.writeAsBytes(bytes);
    }

    await _audioPlayer.play(DeviceFileSource(file.path));
      setState(() {
        _playingAudioKey = key;
        _isAudioPlaying = true;
        _loadingAudioKey = null;
      });
    } catch (e) {
      debugPrint('Error playing audio: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao reproduzir áudio: $e')));
        setState(() {
          _loadingAudioKey = null;
          _playingAudioKey = null;
          _isAudioPlaying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Detalhes do Serviço'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              // Fallback if opened via deep link/notification (go)
              final role = _api.role;
              if (role == 'provider') {
                context.go(_api.isMedical ? '/medical-home' : '/provider-home');
              } else {
                context.go('/home');
              }
            }
          },
        ),
        actions: [
          if (_service != null &&
              _api.role == 'provider' &&
              _service!['status'] != 'pending')
            IconButton(
              icon: const Icon(LucideIcons.messageCircle),
              onPressed: () {
                final client = _service!['client'];
                final otherName = _service!['client_name'] ??
                    (client is Map ? client['name'] : null) ??
                    'Cliente';
                final otherAvatar = _service!['client_avatar'] ??
                    (client is Map
                        ? (client['avatar'] ?? client['photo'])
                        : null);

                context.push(
                  '/chat/${widget.serviceId}',
                  extra: {
                    'serviceId': widget.serviceId,
                    'otherName': otherName,
                    'otherAvatar': otherAvatar,
                  },
                );
              },
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.alertCircle, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Erro ao carregar detalhes:\n$_error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDetails,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Tentar Novamente'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.pop(),
              child: const Text('Voltar'),
            ),
          ],
        ),
      );
    }

    if (_service == null) {
      return const Center(child: Text('Serviço não encontrado'));
    }

    final s = _service!;
    final status = s['status'] ?? 'pending';
    final lat = s['latitude'] != null
        ? double.tryParse(s['latitude'].toString())
        : null;
    final lon = s['longitude'] != null
        ? double.tryParse(s['longitude'].toString())
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _getStatusColor(status).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _getStatusColor(status)),
            ),
            child: Text(
              _getStatusText(status).toUpperCase(),
              style: TextStyle(
                color: _getStatusColor(status),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title/Description
          Text(
            s['description'] ?? 'Sem descrição',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            s['profession'] ?? s['category_name'] ?? 'Categoria não informada',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),

          const SizedBox(height: 16),

          // Address
          _buildInfoRow(
            LucideIcons.mapPin,
            'Endereço',
            s['address'] ?? 'Endereço não informado',
          ),
          const SizedBox(height: 16),

          Row(
          children: [
            Expanded(
              child: _buildInfoRow(
                LucideIcons.navigation,
                'Distância',
                _isRouteLoading ? 'Calculando...' : _routeDistance,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildInfoRow(
                LucideIcons.clock,
                'Tempo de deslocamento',
                _isRouteLoading ? 'Calculando...' : _routeDuration,
              ),
            ),
          ],
        ),
          const SizedBox(height: 24),

          // Map Preview
          if (lat != null && lon != null)
            Container(
              height: 200,
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
                    initialZoom: 15,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=\${dotenv.env[\'MAPBOX_TOKEN\'] ?? \'\'}',
                      userAgentPackageName: 'com.app.mobile_app',
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
                        Marker(
                          point: LatLng(lat, lon),
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                        if (_currentPosition != null)
                          Marker(
                            point: _currentPosition!,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.my_location,
                              color: Colors.blue,
                              size: 40,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),

          // Proof Section
          _buildProofSection(),

          const SizedBox(height: 24),

          // Action Button (Moved below map)
          if (_service != null) _buildBottomAction() ?? const SizedBox.shrink(),

          const SizedBox(height: 24),

          // Media Section
          _buildMediaSection(),

          const SizedBox(height: 24),

          // Contest Evidence Section
          _buildContestEvidenceSection(),

          const SizedBox(height: 24),

          // Customer Info (if provider)
          if (_api.role == 'provider') ...[
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Cliente',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Theme.of(
                  context,
                ).primaryColor.withValues(alpha: 0.1),
                backgroundImage: s['client_avatar'] != null
                    ? NetworkImage(s['client_avatar'])
                    : null,
                child: s['client_avatar'] == null
                    ? Text((s['client_name'] ?? 'C')[0].toUpperCase())
                    : null,
              ),
              title: Text(s['client_name'] ?? 'Cliente'),
              // Remove subtitle if no relevant info, or use another field if available
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildProofSection() {
    if (_service == null) return const SizedBox.shrink();
    final completionCode = _service!['completion_code'] ?? _service!['proof_code'];
    final proofPhoto = _service!['proof_photo'];
    final proofVideo = _service!['proof_video'];

    if (completionCode == null && proofPhoto == null && proofVideo == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Prova de Conclusão',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        if (completionCode != null && _api.role != 'provider')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[600],
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  'Código de Validação',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  completionCode.toString(),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        if (proofPhoto != null) ...[
          const SizedBox(height: 12),
          const Text('Foto da Conclusão', style: TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: _api.getMediaUrl(proofPhoto),
              placeholder: (context, url) => Container(height: 200, width: double.infinity, color: Colors.grey[200]),
              errorWidget: (context, url, error) => const Icon(Icons.error),
            ),
          ),
        ],
        if (proofVideo != null) ...[
          const SizedBox(height: 12),
          const Text('Vídeo da Conclusão (Prova Material)', style: TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 8),
          ProofVideoPlayer(
            videoUrl: _api.getMediaUrl(proofVideo),
            height: 250,
          ),
        ],
      ],
    );
  }

  Widget _buildContestEvidenceSection() {
    return const SizedBox.shrink();
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMediaSection() {
    bool hasPhotos = _photoUrls.isNotEmpty;
    bool hasVideo =
        _videoController != null && _videoController!.value.isInitialized;
    bool hasAudio = _audioKeys.isNotEmpty;

    if (!hasPhotos && !hasVideo && !hasAudio) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mídia do Serviço',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        if (hasPhotos) ...[
          SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photoUrls.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
              final path = _photoUrls[index];
              final isLocal = !path.startsWith('http');
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: isLocal
                    ? Image.file(
                        File(path),
                        height: 120,
                        width: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 120,
                          color: Colors.grey[200],
                          child: const Icon(Icons.broken_image),
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: path,
                        height: 120,
                        width: 120,
                        fit: BoxFit.cover,
                        memCacheWidth: 240,
                        maxWidthDiskCache: 480,
                        placeholder: (context, url) => BaseSkeleton(width: 120, height: 120),
                        errorWidget: (context, url, error) => Container(
                          width: 120,
                          color: Colors.grey[200],
                          child: const Icon(Icons.broken_image),
                        ),
                      ),
              );
            },
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (hasVideo) ...[
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio,
                    child: VideoPlayer(_videoController!),
                  ),
                  IconButton(
                    icon: Icon(
                      _videoController!.value.isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      color: Colors.white,
                      size: 50,
                    ),
                    onPressed: () {
                      setState(() {
                        if (_videoController!.value.isPlaying) {
                          _videoController!.pause();
                        } else {
                          _videoController!.play();
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (hasAudio)
          ..._audioKeys.asMap().entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: _buildAudioPlayer(entry.value, entry.key),
            );
          }),
      ],
    );
  }

  Widget _buildAudioPlayer(String key, int index) {
    final isPlaying = _playingAudioKey == key && _isAudioPlaying;
    final isLoading = _loadingAudioKey == key;
    final isCurrent = _playingAudioKey == key;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          if (isLoading)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () => _toggleAudioPlay(key),
              color: AppTheme.primaryPurple,
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Áudio ${index + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (isCurrent) ...[
                  Slider(
                    value: _audioPosition.inSeconds.toDouble().clamp(
                      0.0,
                      _audioDuration.inSeconds.toDouble(),
                    ),
                    max: _audioDuration.inSeconds.toDouble() > 0
                        ? _audioDuration.inSeconds.toDouble()
                        : 1.0,
                    onChanged: (v) {
                      _audioPlayer.seek(Duration(seconds: v.toInt()));
                    },
                    activeColor: Theme.of(context).primaryColor,
                    inactiveColor: Colors.grey[300],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(_audioPosition),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          _formatDuration(_audioDuration),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else
                  const Padding(
                    padding: EdgeInsets.only(top: 8, left: 12),
                    child: Text(
                      'Toque para reproduzir',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Widget? _buildBottomAction() {
    final status = _service!['status'];
    final arrivedAt = _service!['arrived_at'];

    if (status == 'pending') {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _acceptService,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'ACEITAR SERVIÇO',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _rejectService,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  foregroundColor: Colors.red,
                ),
                child: const Text('RECUSAR SERVIÇO'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    }

    if (status == 'waiting_payment_remaining') {
      if (_api.role == 'client') {
        final total =
            double.tryParse(_service!['price_estimated']?.toString() ?? '0') ??
            0.0;
        final upfront =
            double.tryParse(_service!['price_upfront']?.toString() ?? '0') ??
            (total * 0.3);
        final remaining = total - upfront;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _navigateToPayment(remaining, total),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600], // Premium Blue action
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'REALIZE PAGAMENTO',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text(
              'AGUARDANDO PAGAMENTO SEGURO',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      );
    }

    if (status == 'waiting_client_confirmation') {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.blue[600],
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withValues(alpha: 0.2),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            const Icon(LucideIcons.clock, color: Colors.white, size: 32),
            const SizedBox(height: 12),
            const Text(
              'Aguardando Confirmação do Cliente',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'O cliente já recebeu a prova de conclusão. Caso ele não confirme em até 24 horas, o sistema fará a confirmação automática para liberar seu pagamento.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.9), height: 1.4),
            ),
          ],
        ),
      );
    }

    if (status == 'accepted') {
      final isFlowB = _service!['location_type'] == 'provider';
      final isPaid = _service!['payment_remaining_status'] == 'paid';

      if (isFlowB && !isPaid) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'AGUARDANDO CLIENTE/PAGAMENTO',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        );
      }

      if (!isFlowB) {
        if (status == 'accepted') {
             return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ElevatedButton.icon(
                  onPressed: _startNavigationToClient, // New method
                  icon: const Icon(LucideIcons.navigation),
                  label: const Text('INICIAR DESLOCAMENTO', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
                const SizedBox(height: 12),
                 ElevatedButton(
                  onPressed: _startService,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                     minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text(
                    'JÁ ESTOU NO LOCAL (INICIAR)',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        }
           
        if (status == 'on_way') {
           return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                 Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!)
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Compartilhando localização...', style: TextStyle(color: Colors.blue[800]))),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _notifyArrival,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600], // Premium Blue arrival
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text(
                    'CHEGUEI NO LOCAL',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _startService,
                   style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: Colors.purple),
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text(
                    'Pular e Iniciar Serviço',
                     style: TextStyle(color: Colors.purple),
                  ),
                ),
              ],
            ),
          );
        }
        
        if (arrivedAt == null && status != 'on_way' && status != 'accepted') {
          // Fallback
           return const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Confirme sua chegada na aba "Meus Serviços" da tela inicial.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          );
        }
      }
      
      // Keep existing logic for Flow B or paid checks...
      if (!isFlowB && !isPaid) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'AGUARDANDO CLIENTE/PAGAMENTO',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          );
        }

      return Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _startService,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text(
            'INICIAR SERVIÇO',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    if (status == 'awaiting_confirmation') {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _showCompletionDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('INSERIR CÓDIGO DE VALIDAÇÃO',
                style: TextStyle(color: Colors.white)),
          ),
        ),
      );
    }

    if (status == 'in_progress') {
      final isPaid = _service!['payment_remaining_status'] == 'paid';

      if (!isPaid) {
        if (_api.role == 'client') {
          final total =
              double.tryParse(
                _service!['price_estimated']?.toString() ?? '0',
              ) ??
              0.0;
          final upfront =
              double.tryParse(_service!['price_upfront']?.toString() ?? '0') ??
              (total * 0.3);
          final remaining = total - upfront;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: () => _navigateToPayment(remaining, total),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                'PAGAR RESTANTE (70%)',
                style: TextStyle(color: Colors.white),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey,
              disabledBackgroundColor: Colors.grey,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text(
              'AGUARDANDO PAGAMENTO (70%)',
              style: TextStyle(color: Colors.white),
            ),
          ),
        );
      }


      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _requestCompletion,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'CONCLUIR SERVIÇO',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return null;
  }
}

