import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/realtime_service.dart';
import '../../services/data_gateway.dart';
import '../../widgets/proof_video_player.dart';
import 'widgets/dispatch_tracking_timeline.dart';

class TrackingScreen extends StatefulWidget {
  final String serviceId;
  final ApiService? apiService;
  final RealtimeService? realtimeService;

  const TrackingScreen({
    super.key,
    required this.serviceId,
    this.apiService,
    this.realtimeService,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with WidgetsBindingObserver {
  late final ApiService _api;
  late final RealtimeService _realtime;

  bool _isLoading = true;
  Map<String, dynamic>? _service;
  Map<String, dynamic>? _provider;
  String _status = 'pending';
  final ScrollController _timelineController = ScrollController();
  StreamSubscription? _serviceSubscription;
  Timer? _pollingTimer;
  Timer? _searchTickTimer;
  int _searchCountdown = 20;
  
  // Distance and time tracking
  double? _distanceKm;
  int? _estimatedMinutes;
  Timer? _distanceUpdateTimer;

  String _getDynamicSearchMessage() {
    if (_searchCountdown > 15) return "Notificando prestador...";
    if (_searchCountdown > 5) return "Aguardando resposta...";
    return "Buscando próximo prestador...";
  }

  void _startSearchTimer() {
    _searchTickTimer?.cancel();
    _searchCountdown = 20;
    _searchTickTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_searchCountdown > 0) {
          _searchCountdown--;
        } else {
          _searchCountdown = 20;
          _loadService(silent: true); // Force a reload on loop
        }
      });
    });
  }

  bool _isNavigatingToPayment = false;
  bool _hasNavigatedToReview = false;

  bool _hasShownArrivalModal = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = widget.apiService ?? ApiService();
    _realtime = widget.realtimeService ?? RealtimeService();
    _loadService();
    _setupRealtime();
    _startPolling();
    _startSearchTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadService();
      _realtime.connect();
    }
  }

  void _startPolling() {
    // Polling reduced to every 10 seconds as insurance, since we now have robust Real-time Sync
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadService(silent: true);
    });
  }

  void _setupRealtime() {
    // Listen to Service Updates (Status changes, etc.) via Gateway
    _serviceSubscription = DataGateway().watchService(widget.serviceId).listen((data) {
      if (data.isNotEmpty) {
        // Enriched stream data allows us to update UI without full reload
        setState(() {
          _service = {...?_service, ...data};
          _status = data['status'] ?? _status;
          
          // If metadata changed, we might need a full reload or just update here
          // For now, let's just use the enriched data
          if (data['arrived_at'] != null && _service?['arrived_at'] == null) {
              _handleProviderArrivedEvent(data);
          }
        });
      }
    });

    // Listen specifically for provider_arrived event for immediate feedback
    _realtime.onEvent('provider_arrived', _handleProviderArrivedEvent);
  }

  void _handleProviderArrivedEvent(dynamic data) {
    if (!mounted) return;

    // Safety check: Providers shouldn't see this modal
    if (_api.role == 'provider') return;

    final sId = data['service_id'] ?? data['id'];
    // Convert to string for comparison to be safe
    if (sId?.toString() == widget.serviceId && !_hasShownArrivalModal) {
      setState(() => _hasShownArrivalModal = true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Prestador chegou ao local!',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.blue[600],
          duration: const Duration(seconds: 5),
        ),
      );

      _showArrivalPaymentDialog(data is Map<String, dynamic> ? data : null);
    }
  }

  @override
  void dispose() {
    _realtime.offEvent('provider_arrived', _handleProviderArrivedEvent);
    _serviceSubscription?.cancel();
    _pollingTimer?.cancel();
    _searchTickTimer?.cancel();
    _distanceUpdateTimer?.cancel();
    _timelineController.dispose();
    super.dispose();
  }

  /// Calculate distance between two coordinates using Haversine formula
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadiusKm = 6371.0;
    
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
        cos(_degreesToRadians(lat2)) *
        sin(dLon / 2) *
        sin(dLon / 2);
    
    final c = 2 * asin(sqrt(a));
    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (3.141592653589793 / 180.0);
  }

  /// Start tracking distance and time updates
  void _startDistanceTracking() {
    _updateDistanceAndTime();
    
    // Update every 10 seconds
    _distanceUpdateTimer?.cancel();
    _distanceUpdateTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _updateDistanceAndTime();
    });
  }

  /// Update distance and estimated time
  Future<void> _updateDistanceAndTime() async {
    if (_service == null || _provider == null) return;
    
    try {
      // Get service location
      final serviceLat = _service!['latitude'];
      final serviceLon = _service!['longitude'];
      
      if (serviceLat == null || serviceLon == null) return;
      
      // Get provider location from service data (updated by backend)
      final providerLat = _service!['provider_latitude'];
      final providerLon = _service!['provider_longitude'];
      
      if (providerLat == null || providerLon == null) return;
      
      // Calculate distance
      final distance = _calculateDistance(
        double.parse(providerLat.toString()),
        double.parse(providerLon.toString()),
        double.parse(serviceLat.toString()),
        double.parse(serviceLon.toString()),
      );
      
      // Estimate time (assuming average speed of 30 km/h in urban areas)
      const averageSpeedKmh = 30.0;
      final estimatedHours = distance / averageSpeedKmh;
      final estimatedMins = (estimatedHours * 60).ceil();
      
      if (mounted) {
        setState(() {
          _distanceKm = distance;
          _estimatedMinutes = estimatedMins;
        });
      }
    } catch (e) {
      debugPrint('Error calculating distance: $e');
    }
  }

  Future<void> _fetchFullProviderProfile(int providerId) async {
    try {
      final profile = await _api.getProviderProfile(providerId);
      if (mounted) {
        setState(() {
          if (_provider != null) {
             // Prioritize profile data over existing generic data
             final name = profile['name'] ?? profile['full_name'];
             if (name != null && name.toString().isNotEmpty) {
                _provider!['name'] = name;
             }
             
             final avatar = profile['avatar_url'] ?? profile['photo'] ?? profile['avatar'];
             if (avatar != null && avatar.toString().isNotEmpty) {
                _provider!['avatar_url'] = avatar;
             }
             
             if (profile['rating'] != null) {
                _provider!['rating'] = profile['rating'];
             }
             if (profile['rating_count'] != null) {
                _provider!['reviews_count'] = profile['rating_count'];
             }
          }
        });
      }
    } catch (e) {
      debugPrint('⚠️ [Tracking] Error fetching full provider profile: $e');
    }
  }

  Future<void> _loadService({bool silent = false}) async {
    try {
      final data = await DataGateway().getServiceDetails(widget.serviceId);
      if (!mounted) return;

      debugPrint('🔍 [TrackingScreen] Validating Provider Data: $data');


      final oldArrivedAt = _service?['arrived_at'];
      final newArrivedAt = data['arrived_at'];
      final locationType = data['location_type'] ?? 'client';

      // Check for provider arrival (Flow A)
      if (locationType == 'client' &&
          oldArrivedAt == null &&
          newArrivedAt != null &&
          !_hasShownArrivalModal) {
        setState(() => _hasShownArrivalModal = true);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Prestador chegou ao local!',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.blue[600],
            duration: const Duration(seconds: 5),
          ),
        );

        // Auto-prompt payment for Flow A
        if (data['payment_remaining_status'] != 'paid') {
          _showArrivalPaymentDialog(data);
        }
      }

      if (data['status'] == 'waiting_client_confirmation') {
        if (!_hasNavigatedToReview && mounted) {
          _hasNavigatedToReview = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.push('/review/${widget.serviceId}');
          });
        }
      }

      setState(() {
        _service = data;
        _status = data['status'] ?? 'pending';

        // Auto-navigate to payment if service started and not paid
        if (_status == 'in_progress' &&
            data['payment_remaining_status'] != 'paid' &&
            !_isNavigatingToPayment) {
          _isNavigatingToPayment = true;
          // Delay slightly to ensure UI build
          Future.delayed(Duration.zero, () {
            _handlePayRemaining().then((_) {
              if (mounted) {
                setState(() => _isNavigatingToPayment = false);
              }
            });
          });
        }

        // Handle both nested and flat provider data
        if (data['provider'] != null) {
          final p = data['provider'];
          _provider = {
            'id': p['id'],
            'name': p['name'] ?? 'Prestador',
            'avatar_url': p['avatar'] ?? p['avatar_url'],
            'rating': p['rating'] ?? 5.0,
            'reviews_count': p['reviews'] ?? p['rating_count'] ?? 0,
            'phone': p['phone'],
          };
        } else if (data['provider_id'] != null) {
          _provider = {
            'id': data['provider_id'],
            'name': data['provider_name'] ?? 'Prestador',
            'phone': data['provider_phone'],
            'avatar_url': data['provider_avatar_url'] ?? data['provider_avatar'],
            'rating': data['provider_rating'] ?? 5.0,
            'reviews_count': data['provider_rating_count'] ?? data['provider_reviews'] ?? 0,
          };
        } else {
          _provider = null;
        }

        // Parse Service Location
        if (data['latitude'] != null && data['longitude'] != null) {
          // Parse coordinates if needed for future logic, but not used in current vertical UI
        }

        // Start Tracking if Provider Assigned
        if (_provider != null) {
          final pId = _provider!['id'];
          final provIdInt = pId is int ? pId : int.tryParse(pId.toString());
          if (provIdInt != null) {
            // Enhanced: Fetch full profile if name is generic or missing
            if (_provider!['name'] == 'Prestador') {
               _fetchFullProviderProfile(provIdInt);
            }

            // Calculate distance and time if we have coordinates
            _startDistanceTracking();
          }
        }
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollTimelineToCurrentStep();
      });
    } catch (e) {
      debugPrint('Error loading service: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showArrivalPaymentDialog([Map<String, dynamic>? data]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Prestador Chegou!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'O prestador confirmou a chegada. Por favor, realize o pagamento do valor restante para liberar o início do serviço.',
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Agora não'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _handlePayRemaining();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Pagar Agora'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'O prestador recebe o valor somente após a conclusão do serviço.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleContest() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Contestar Serviço'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Motivo da contestação',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Enviar'),
            ),
          ],
        );
      },
    );

    if (reason != null && reason.isNotEmpty) {
      try {
        await _api.contestService(widget.serviceId, reason);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Contestação enviada!')));
          _loadService();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao enviar contestação: $e')),
          );
        }
      }
    }
  }

  Future<void> _handleArrive() async {
    try {
      await _api.arriveService(widget.serviceId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Chegada confirmada!')));

        // If Flow B (Client going to provider), automatically open payment
        final locationType = _service?['location_type'] ?? 'client';
        if (locationType == 'provider') {
          _handlePayRemaining();
        } else {
          _loadService();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao confirmar chegada: $e')),
        );
      }
    }
  }

  Future<void> _handlePayRemaining() async {
    // Navigate to payment screen for remaining amount
    double total = 0.0;
    double deposit = 0.0;

    if (_service != null) {
      total =
          double.tryParse(_service!['price_estimated']?.toString() ?? '0') ??
          0.0;
      deposit =
          double.tryParse(_service!['price_upfront']?.toString() ?? '0') ?? 0.0;
    }

    // Remaining is Total - Deposit (if deposit was paid)
    // If we want to be safe, we can just pass the total and let the backend/logic handle it,
    // but usually we want to show the user what they are paying.
    double amountToPay = total > deposit ? (total - deposit) : total;
    if (amountToPay <= 0) amountToPay = 50.0; // Fallback

    await context.push(
      '/payment/${widget.serviceId}',
      extra: {
        'serviceId': widget.serviceId,
        'type': 'remaining',
        'amount': amountToPay,
        'total': total,
      },
    );
    // Reload after returning from payment
    if (mounted) {
      setState(() => _isLoading = true);
    }
    _loadService();
  }

  Future<void> _handleConfirm() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.black, width: 1.5),
        ),
        title: const Text('Confirmar Conclusão?'),
        content: const Text('Ao confirmar, você atesta que o serviço foi realizado com sucesso e o pagamento será liberado para o prestador.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
            ),
            child: const Text('CONFIRMAR'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: const Center(child: CircularProgressIndicator()),
        ),
      );

      await _api.confirmServiceCompletion(widget.serviceId);

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Serviço confirmado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        context.push('/review/${widget.serviceId}');
      }
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop(); // Close loading
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _scrollTimelineToCurrentStep() {
    if (!_timelineController.hasClients) return;

    const stepWidth = 140.0;
    int index = 0;

    if (_status == 'accepted') {
      index = 1;
    } else if (_status == 'waiting_remaining_payment') {
      index = 2;
    } else if ([
      'in_progress',
      'waiting_client_confirmation',
      'on_way',
      'awaiting_confirmation',
    ].contains(_status)) {
      index = 3;
    } else if (_status == 'completed') {
      index = 4;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final targetCenter = index * stepWidth;
    double offset = targetCenter - (screenWidth / 2 - stepWidth / 2);

    final max = _timelineController.position.maxScrollExtent;
    if (offset < 0) offset = 0;
    if (offset > max) offset = max;

    _timelineController.animateTo(
      offset,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  Widget _buildValidationCodeCard() {
    final validationCode = _service?['validation_code'];
    final completionCode = _service?['completion_code'];
    final code = completionCode ?? validationCode;

    // Only show if we have a code AND the status suggests it's needed for confirmation or in progress
    if (code == null || !['in_progress', 'awaiting_confirmation', 'waiting_client_confirmation', 'waiting_remaining_payment'].contains(_status)) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue[600],
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.shieldCheck, color: Colors.white, size: 24),
              const SizedBox(width: 8),
              const Text(
                'Código de Validação',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            code.toString(),
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Informe este código ao prestador para finalizar o serviço',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProofSection() {
    final photoUrl = _service?['proof_photo'];
    final videoUrl = _service?['proof_video'];

    if (photoUrl == null && videoUrl == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Provas de Conclusão',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (videoUrl != null) ...[
            const Text('Vídeo do Serviço (Prova Material)', style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            ProofVideoPlayer(videoUrl: _api.getMediaUrl(videoUrl)),
            const SizedBox(height: 16),
          ],
          if (photoUrl != null) ...[
            const Text('Foto do Serviço', style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: _api.getMediaUrl(photoUrl),
                placeholder: (context, url) => Container(height: 200, color: Colors.grey[200]),
                errorWidget: (context, url, error) => const Icon(Icons.error),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_service == null) return const SizedBox.shrink();

    final status = _status;
    final locationType = _service!['location_type'] ?? 'client';
    final arrivedAt = _service!['arrived_at'];
    final paymentStatus = _service!['payment_remaining_status'];

    // Flow B: Client goes to provider
    if (locationType == 'provider') {
      if (status == 'accepted') {
        if (arrivedAt == null) {
          return SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(LucideIcons.mapPin),
              label: const Text('Cheguei no Local'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _handleArrive,
            ),
          );
        } else if (paymentStatus != 'paid') {
          return SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(LucideIcons.creditCard),
              label: const Text('Pagar Restante'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _handlePayRemaining,
            ),
          );
        } else {
          return const Center(
            child: Text(
              'Pagamento realizado. Aguardando início...',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          );
        }
      }
    }
    // Flow A: Provider comes to client
    else {
      if ([
        'accepted',
        'waiting_remaining_payment',
        'in_progress',
      ].contains(status)) {
        if (arrivedAt != null && paymentStatus != 'paid') {
          return SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(LucideIcons.creditCard),
              label: const Text('Pagar Restante'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _handlePayRemaining,
            ),
          );
        } else if (arrivedAt != null) {
          return const SizedBox.shrink(); // Moved to status banner
        }
      }
    }

    // Completion actions
    if (status == 'completed' || status == 'waiting_client_confirmation') {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(LucideIcons.checkCircle),
              label: const Text('Confirmar Conclusão'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600], // Premium Blue
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _handleConfirm,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            icon: const Icon(LucideIcons.alertTriangle),
            label: const Text('Contestar Serviço'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: _handleContest,
          ),
        ],
      );
    }

    // Default: Chat button if accepted/in_progress
    if ((_isAccepted() || _isInProgress()) && _provider != null) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: const Icon(LucideIcons.messageCircle),
          label: const Text('Enviar Mensagem'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[600],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: () {
            context.push(
              '/chat/${widget.serviceId}',
              extra: {
                'serviceId': widget.serviceId,
                'otherName': _provider!['name'],
                'otherAvatar': _provider!['avatar_url'],
              },
            );
          },
        ),
      );
    }

    if (_status == 'pending') {
      return const Center(
        child: Text(
          'Aguardando um prestador aceitar...',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(LucideIcons.chevronLeft),
            onPressed: () => context.go('/home'),
          ),
          title: const Text('Acompanhamento do serviço'),
        ),
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryPurple),
        ),
      );
    }

    if (_service == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Erro')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Não foi possível carregar o serviço.'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadService,
                child: const Text('Tentar Novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => context.go('/home'),
        ),
        title: const Text('Acompanhamento do serviço'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Título principal e destaque do serviço
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryPurple.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryPurple.withValues(alpha: 0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _service?['category']?.toString() ?? 'Serviço',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _service?['description']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Distance and Time Card (only show if provider is assigned and we have data)
              if (_provider != null && (_distanceKm != null || _estimatedMinutes != null))
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Distance
                      Expanded(
                        child: Column(
                          children: [
                            Icon(LucideIcons.mapPin, color: Colors.blue[600], size: 24),
                            const SizedBox(height: 8),
                            const Text(
                              'Distância',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _distanceKm != null ? '${_distanceKm!.toStringAsFixed(2)} km' : '--',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 60,
                        color: Colors.grey[300],
                      ),
                      // Time
                      Expanded(
                        child: Column(
                          children: [
                            Icon(LucideIcons.clock, color: Colors.blue[600], size: 24),
                            const SizedBox(height: 8),
                            const Text(
                              'Tempo',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _estimatedMinutes != null ? '$_estimatedMinutes min' : '--',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // --- Tracking Timeline Widget (v12) ---
              if (_status == 'pending' || _status == 'searching')
                Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: DispatchTrackingTimeline(
                    serviceId: widget.serviceId,
                    onProviderFound: () {
                      _loadService(); // Reload to show provider details
                    },
                  ),
                )
              else 
                // Vertical Timeline implementation
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _buildVerticalTimelineItem(
                        label: 'Serviço solicitado',
                        subtitle: 'Seu pedido foi recebido e está sendo processado',
                        isActive: true,
                        isCompleted: true,
                        isFirst: true,
                      ),
                      _buildVerticalTimelineItem(
                        label: 'Prestador aceitou',
                        subtitle: _isAccepted() ? 'Profissional confirmado e se deslocando' : 'Buscando o profissional mais próximo de você',
                        isActive: _isAccepted(),
                        isCompleted: _isAccepted(),
                      ),
                      _buildVerticalTimelineItem(
                        label: 'Entrada (30%) paga',
                        subtitle: 'Confirmado o sinal para reserva do horário',
                        isActive: true, // Já que estamos nesta tela, o sinal foi pago
                        isCompleted: true,
                      ),
                      _buildVerticalTimelineItem(
                        label: 'Pagamento restante',
                        subtitle: _isRemainingPaid() 
                            ? 'Pagamento final confirmado pela plataforma' 
                            : (_isWaitingRemainingPayment() ? 'Aguardando pagamento do valor final' : 'A ser pago após a chegada do prestador'),
                        isActive: _isWaitingRemainingPayment() || _isRemainingPaid(),
                        isCompleted: _isRemainingPaid(),
                      ),
                      _buildVerticalTimelineItem(
                        label: 'Serviço em andamento',
                        subtitle: _isInProgress() ? 'O profissional já iniciou os trabalhos no local' : 'O serviço iniciará após o pagamento final',
                        isActive: _isInProgress(),
                        isCompleted: _status == 'completed' || _status == 'awaiting_confirmation',
                      ),
                      _buildVerticalTimelineItem(
                        label: 'Serviço concluído',
                        subtitle: _isCompleted() ? 'Serviço entregue e finalizado com sucesso' : 'Seu serviço será concluído em breve',
                        isActive: _isCompleted(),
                        isCompleted: _isCompleted(),
                        isLast: true,
                      ),
                    ],
                  ),
                ),

              _buildStatusBanner(),

              const SizedBox(height: 8),

              // Resumo financeiro 30% + 70%
              if (_service != null &&
                  _service!['price_estimated'] != null) ...[
                _buildPaymentSummary(),
                const SizedBox(height: 24),
              ],



              // Card do prestador ou mensagem de espera
              if (_provider != null)
                _buildProviderCard()
              else
                _buildWaitingCard(),

              const SizedBox(height: 24),

              // Código de validação (Consolidado)
              _buildValidationCodeCard(),

              const SizedBox(height: 16),

              // Provas / fotos do serviço
              _buildProofSection(),

              // Ações principais (ex: falar com prestador, confirmar conclusão)
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }


  bool _isAccepted() {
    return [
      'accepted',
      'waiting_remaining_payment',
      'in_progress',
      'waiting_client_confirmation',
      'on_way',
      'awaiting_confirmation',
      'completed',
    ].contains(_status);
  }

  bool _isInProgress() {
    return [
      'in_progress',
      'waiting_client_confirmation',
      'on_way',
      'awaiting_confirmation',
      'completed',
    ].contains(_status);
  }

  bool _isWaitingRemainingPayment() {
    if (_status == 'waiting_remaining_payment') return true;
    final remainingStatus = _service?['payment_remaining_status']?.toString();
    return remainingStatus != null && remainingStatus != 'paid';
  }

  bool _isCompleted() {
    return ['completed', 'awaiting_confirmation'].contains(_status);
  }

  bool _isRemainingPaid() {
    return _service?['payment_remaining_status'] == 'paid' || 
           ['in_progress', 'completed', 'awaiting_confirmation'].contains(_status);
  }

  Widget _buildStatusBanner() {
    String message = "";
    bool showBanner = false;

    final arrivedAt = _service?['arrived_at'];
    final isWaiting = _status == 'awaiting_confirmation' || _status == 'waiting_client_confirmation';

    if (_status == 'accepted') {
      message = arrivedAt != null ? "Prestador chegou ao local!" : "Prestador a caminho do seu endereço";
      showBanner = true;
    } else if (_status == 'waiting_remaining_payment') {
      message = "Aguardando pagamento para iniciar o serviço";
      showBanner = true;
    } else if (_status == 'in_progress') {
      message = "Profissional trabalhando no local...";
      showBanner = true;
    } else if (isWaiting) {
      message = "Serviço Finalizado. Toque em 'Confirmar' abaixo.";
      showBanner = true;
    } else if (_status == 'completed') {
      message = "Serviço concluído com sucesso!";
      showBanner = true;
    }

    if (!showBanner) return const SizedBox.shrink();

    final bannerColor = isWaiting ? Colors.black : Colors.green;
    final bannerBg = isWaiting ? Colors.white : Colors.green[50];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: bannerBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bannerColor.withValues(alpha: isWaiting ? 0.1 : 0.3)),
      ),
      child: Row(
        children: [
          Icon(isWaiting ? LucideIcons.info : Icons.info_outline, color: bannerColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: bannerColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalTimelineItem({
    required String label,
    required String subtitle,
    required bool isActive,
    required bool isCompleted,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Column(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? AppTheme.primaryPurple
                      : (isActive ? Colors.white : Colors.grey[200]),
                  border: Border.all(
                    color: isActive ? AppTheme.primaryPurple : Colors.grey[300]!,
                    width: 2,
                  ),
                  shape: BoxShape.circle,
                ),
                child: isCompleted
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : (isActive ? Center(child: Container(width: 8, height: 8, decoration: BoxDecoration(color: AppTheme.primaryPurple, shape: BoxShape.circle))) : null),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isCompleted ? AppTheme.primaryPurple : Colors.grey[200],
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.black87 : Colors.grey,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isActive ? Colors.grey[600] : Colors.grey[400],
                  ),
                ),
                if (!isLast) const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderCard() {
    final name = _provider?['name']?.toString() ?? 'Prestador';
    final displayName = name.isNotEmpty ? name : 'Prestador';
    final avatarUrl = _provider?['avatar_url']?.toString();
    final rating = double.tryParse(_provider?['rating']?.toString() ?? '5.0') ?? 5.0;
    final reviewsCount = int.tryParse(_provider?['reviews_count']?.toString() ?? '0') ?? 0;

    return InkWell(
      onTap: () {
        final providerId = _provider?['id'];
        final pIdInt = providerId is int ? providerId : int.tryParse(providerId?.toString() ?? '');
        if (pIdInt != null) {
          context.push('/provider-profile', extra: pIdInt);
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryPurple.withValues(alpha: 0.1),
              image: avatarUrl != null && avatarUrl.isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(ApiService.fixUrl(avatarUrl)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: avatarUrl == null || avatarUrl.isEmpty
                ? Center(
                    child: Text(
                      displayName.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        color: AppTheme.primaryPurple,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (reviewsCount > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '($reviewsCount)',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          InkWell(
            onTap: () {
              final id = _service?['id']?.toString() ?? widget.serviceId;
              // Passa ID na ROTA e Metadados no EXTRA
              context.push(
                '/chat/$id', 
                extra: {
                   'serviceId': id,
                   'otherName': displayName,
                   'otherAvatar': avatarUrl,
                }
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.chat_bubble_outline, color: Colors.blue[600], size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingCard() {
    final String dynamicMsg = _getDynamicSearchMessage();
    final Color statusColor = Colors.blue[600]!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: statusColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dynamicMsg,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Aguarde enquanto conectamos você.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(
                  value: _searchCountdown / 20,
                  strokeWidth: 4,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              Text(
                '${_searchCountdown}s',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentSummary() {
    final totalValue =
        double.tryParse(_service!['price_estimated'].toString()) ?? 0.0;
    final upfrontValue = totalValue * 0.30;
    final remainingRaw = totalValue - upfrontValue;
    final remaining = remainingRaw < 0 ? 0.0 : remainingRaw;

    String formatBRL(double v) {
      final s = v.toStringAsFixed(2);
      return 'R\$ ${s.replaceAll('.', ',')}';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pagamento do serviço',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Valor total', style: TextStyle(color: Colors.grey)),
              Text(
                formatBRL(totalValue),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Entrada (30%)', style: TextStyle(color: Colors.grey)),
              Text(
                formatBRL(upfrontValue),
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Restante (70%)',
                style: TextStyle(color: Colors.grey),
              ),
              Text(
                formatBRL(remaining),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.secondaryOrange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _getPaymentStatusMessage(_status),
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }



  String _getPaymentStatusMessage(String status) {
    switch (status) {
      case 'in_progress':
        return 'Aguardando conclusão do serviço. A plataforma irá liberar o pagamento ao prestador após a confirmação da conclusão.';
      case 'completed':
        return 'Serviço concluído. Pagamento total realizado e liberado para o prestador.';
      case 'on_way':
        return 'Prestador a caminho. O pagamento restante será solicitado na chegada do prestador.';
      case 'waiting_remaining_payment':
         return 'Prestador chegou! Realize o pagamento do restante para iniciar o serviço.';
      default:
        return 'Você já pagou 30% na abertura do pedido. Os 70% restantes são liberados somente após a conclusão do serviço.';
    }
  }

}
