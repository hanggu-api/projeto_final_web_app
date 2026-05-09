import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/constants/trip_statuses.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/maps/app_tile_layer.dart';
import '../../../../services/api_service.dart';
import '../../../../services/app_config_service.dart';
import '../../../../services/data_gateway.dart';

class ProviderServiceCard extends StatefulWidget {
  final Map<String, dynamic> service;
  final VoidCallback? onNavigate;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onArrive;
  final VoidCallback? onStart;
  final VoidCallback? onFinish;
  final VoidCallback? onViewDetails;
  final Function(DateTime scheduledAt, String message)? onSchedule;
  final VoidCallback? onConfirmSchedule;
  final Map<String, String>? travelInfo;
  final bool isFocusMode;

  const ProviderServiceCard({
    super.key,
    required this.service,
    this.onNavigate,
    this.onAccept,
    this.onReject,
    this.onArrive,
    this.onStart,
    this.onFinish,
    this.onViewDetails,
    this.onSchedule,
    this.onConfirmSchedule,
    this.travelInfo,
    this.isFocusMode = false,
  });

  @override
  State<ProviderServiceCard> createState() => _ProviderServiceCardState();
}

class _ProviderServiceCardState extends State<ProviderServiceCard>
    with TickerProviderStateMixin {
  bool _isExpanded = false;
  bool _isScheduling = false;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  final TextEditingController _messageController = TextEditingController();
  final MapController _mapController = MapController();
  LatLng? _providerLocation;
  List<LatLng> _routePoints = [];
  DateTime? _lastLocationPermissionLogAt;
  Timer? _confirmationCountdownTimer;
  DateTime _countdownNow = DateTime.now();

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

    final cfg = AppConfigService();
    final net = cfg.calculateNetGain(gross);
    if (net > 0) return double.parse(net.toStringAsFixed(2));
    return double.parse((gross * 0.85).toStringAsFixed(2));
  }

  double _focusMapHeight(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final preferred = screenHeight * 0.40;
    return preferred.clamp(220.0, 340.0);
  }

  @override
  void initState() {
    super.initState();
    final minimumSchedule = _minimumScheduleDateTime();
    _selectedDate = DateTime(
      minimumSchedule.year,
      minimumSchedule.month,
      minimumSchedule.day,
    );
    _selectedTime = TimeOfDay.fromDateTime(minimumSchedule);
    if (widget.isFocusMode) {
      _isExpanded = true;
    }
    _updateDynamicMessage();
    _loadProviderLocation();
    _startConfirmationCountdownTicker();
  }

  void _startConfirmationCountdownTicker() {
    _confirmationCountdownTimer?.cancel();
    _confirmationCountdownTimer = Timer.periodic(const Duration(minutes: 1), (
      _,
    ) {
      if (!mounted) return;
      setState(() => _countdownNow = DateTime.now());
    });
  }

  DateTime _minimumScheduleDateTime() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour, now.minute);
  }

  bool _isSameCalendarDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime _composeSelectedScheduleDateTime({DateTime? date, TimeOfDay? time}) {
    final selectedDate = date ?? _selectedDate;
    final selectedTime = time ?? _selectedTime;
    return DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );
  }

  DateTime _normalizedScheduleDateTimeForSubmit(DateTime candidate) {
    final minimum = _minimumScheduleDateTime();
    if (candidate.isBefore(minimum)) {
      return minimum;
    }
    return candidate;
  }

  void _syncScheduleSelectionWithMinimum() {
    final minimum = _minimumScheduleDateTime();
    final minimumDay = DateTime(minimum.year, minimum.month, minimum.day);

    if (_selectedDate.isBefore(minimumDay)) {
      _selectedDate = minimumDay;
      _selectedTime = TimeOfDay.fromDateTime(minimum);
      return;
    }

    final selectedDateTime = _composeSelectedScheduleDateTime();
    if (_isSameCalendarDay(_selectedDate, minimumDay) &&
        selectedDateTime.isBefore(minimum)) {
      _selectedTime = TimeOfDay.fromDateTime(minimum);
    }
  }

  void _startSchedulingNow() {
    setState(() {
      _isScheduling = true;
      _syncScheduleSelectionWithMinimum();
    });
    _updateDynamicMessage();
  }

  void _applyCurrentScheduleNow() {
    final minimum = _minimumScheduleDateTime();
    setState(() {
      _selectedDate = DateTime(minimum.year, minimum.month, minimum.day);
      _selectedTime = TimeOfDay.fromDateTime(minimum);
    });
    _updateDynamicMessage();
  }

  Future<void> _loadProviderLocation() async {
    try {
      if (!kIsWeb) {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
        if (mounted) {
          setState(() {
            _providerLocation = LatLng(position.latitude, position.longitude);
          });
        }
      }

      if (_providerLocation == null) {
        final providerId = await _resolveCurrentProviderId();
        if (providerId != null) {
          final persisted = await _resolveProviderStartFromDatabase(providerId);
          if (persisted != null && mounted) {
            setState(() => _providerLocation = persisted);
          }
        }
      }

      final s = widget.service;
      if (_providerLocation != null &&
          s['latitude'] != null &&
          s['longitude'] != null) {
        final dest = LatLng(
          double.tryParse(s['latitude'].toString()) ?? 0,
          double.tryParse(s['longitude'].toString()) ?? 0,
        );
        _fetchRoute(_providerLocation!, dest);
      }
    } catch (e) {
      final text = e.toString().toLowerCase();
      final isPermissionDenied =
          text.contains('denied permissions') ||
          text.contains('permission denied') ||
          text.contains('locationpermission.denied') ||
          text.contains('locationpermission.deniedforever');
      if (!isPermissionDenied) {
        debugPrint('Error getting provider location: $e');
        return;
      }

      final now = DateTime.now();
      if (_lastLocationPermissionLogAt != null &&
          now.difference(_lastLocationPermissionLogAt!) <
              const Duration(minutes: 1)) {
        return;
      }
      _lastLocationPermissionLogAt = now;
      debugPrint(
        '⚠️ [ProviderServiceCard] Location permission denied. Usando fallback silencioso.',
      );
    }
  }

  Future<int?> _resolveCurrentProviderId() async {
    final api = ApiService();
    int? providerId = api.userIdInt;
    if (providerId != null) return providerId;
    try {
      final authUid = Supabase.instance.client.auth.currentUser?.id;
      if (authUid != null && authUid.trim().isNotEmpty) {
        providerId = await DataGateway().resolveUserIdByAuthUid(authUid);
      }
    } catch (e) {
      debugPrint('Erro resolvendo providerId atual: $e');
    }
    return providerId;
  }

  Future<void> _fetchRoute(LatLng start, LatLng end) async {
    if (!mounted) return;

    try {
      // OSRM Public API (For demo purposes)
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final geometry = data['routes'][0]['geometry'];
          final coords = geometry['coordinates'] as List;
          final points = coords
              .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
              .toList();

          if (mounted) {
            setState(() {
              _routePoints = points;
            });

            // Try to fit bounds if map is visible
            try {
              _fitBounds();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching route: $e');
    }
  }

  void _fitBounds() {
    if (_routePoints.isEmpty || !mounted) return;

    // flutter_map 6+ (using fitCamera)
    try {
      final bounds = LatLngBounds.fromPoints(_routePoints);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(32)),
      );
    } catch (e) {
      // flutter_map throws if MapController is used before the FlutterMap renders.
      // This can happen during route fetch. We'll rely on MapOptions.onMapReady
      // to call _fitBounds once the map is ready.
      final msg = e.toString();
      if (msg.contains('FlutterMap widget rendered at least once') ||
          msg.contains('rendered at least once')) {
        return;
      }
      debugPrint('Error fitting bounds: $e');
    }
  }

  void _updateDynamicMessage() {
    final s = widget.service;
    final title =
        (s['title'] ??
                s['description'] ??
                s['profession'] ??
                s['category_name'] ??
                'Serviço')
            .toString()
            .replaceAll('Serviço: ', '')
            .trim();

    final day = _getDayName(_selectedDate);
    final dateStr =
        '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}';
    final timeStr =
        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

    setState(() {
      _messageController.text =
          'Olá! Gostaria de agendar o serviço "$title" para $day ($dateStr) às $timeStr. Aguardo sua confirmação.';
    });
  }

  @override
  void dispose() {
    _confirmationCountdownTimer?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  DateTime? _parseServiceDate(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  DateTime? _resolveClientConfirmationBase(Map<String, dynamic> service) {
    return _parseServiceDate(service['finished_at']) ??
        _parseServiceDate(service['status_updated_at']) ??
        _parseServiceDate(service['completed_at']) ??
        _parseServiceDate(service['updated_at']) ??
        _parseServiceDate(service['created_at']);
  }

  Duration? _remainingClientConfirmationWindow(Map<String, dynamic> service) {
    final base = _resolveClientConfirmationBase(service);
    if (base == null) return null;
    final deadline = base.add(const Duration(hours: 12));
    return deadline.difference(_countdownNow);
  }

  String _formatRemainingClientConfirmation(Duration remaining) {
    if (remaining.inSeconds <= 0) {
      return 'menos de 1 minuto';
    }
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    if (hours <= 0) {
      return '$minutes min';
    }
    if (minutes <= 0) {
      return '${hours}h';
    }
    return '${hours}h ${minutes}min';
  }

  Future<LatLng?> _resolveProviderStartFromDatabase(int providerUserId) async {
    try {
      final row = await DataGateway().loadProviderStartLocation(providerUserId);
      final lat = (row?['latitude'] as num?)?.toDouble();
      final lon = (row?['longitude'] as num?)?.toDouble();
      if (lat != null && lon != null) return LatLng(lat, lon);
    } catch (e) {
      debugPrint('Fallback de localização do prestador falhou: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final status = s['status'];
    final statusLower = normalizeServiceStatus(status?.toString());
    final isAcceptedPhase =
        statusLower == TripStatuses.accepted ||
        statusLower == 'provider_near' ||
        statusLower == TripStatuses.scheduled;
    final isWaitingSecurePayment = ServiceStatusSets.paymentRemaining.contains(
      statusLower,
    );
    final hasArrived =
        s['arrived_at'] != null ||
        s['client_arrived'] == true ||
        s['client_arrived'] == 'true';
    final paymentRemainingStatus = (s['payment_remaining_status'] ?? '')
        .toString()
        .toLowerCase();
    final remainingPaidStatuses = {
      'paid',
      'paid_manual',
      'approved',
      'completed',
      'succeeded',
    };
    final isRemainingPaid = remainingPaidStatuses.contains(
      paymentRemainingStatus,
    );
    final hasServiceStarted = s['started_at'] != null;
    final price = _resolveProviderNetAmount(s);
    final providerId = s['provider_id'];
    final providerIdText = (providerId ?? '').toString().trim().toLowerCase();
    final isUnassigned =
        providerId == null ||
        providerIdText.isEmpty ||
        providerIdText == 'null' ||
        providerIdText == '0';
    final isAvailable =
        isUnassigned &&
        (statusLower == TripStatuses.pending ||
            statusLower == TripStatuses.openForSchedule ||
            statusLower == TripStatuses.searching);
    final canShowScheduleAction =
        statusLower == TripStatuses.openForSchedule &&
        widget.onSchedule != null;
    final serviceTitle =
        (s['task_name'] ??
                s['task_title'] ??
                s['description'] ??
                s['profession'] ??
                s['category_name'] ??
                s['title'] ??
                'Serviço')
            .toString()
            .replaceAll('Serviço: ', '')
            .trim();
    final serviceDescription = (s['description'] ?? '').toString().trim();
    final isAwaitingClientConfirmation = ServiceStatusSets.providerConcluding
        .contains(statusLower);
    final remainingClientConfirmation = isAwaitingClientConfirmation
        ? _remainingClientConfirmationWindow(s)
        : null;
    final remainingClientConfirmationLabel = remainingClientConfirmation == null
        ? null
        : _formatRemainingClientConfirmation(remainingClientConfirmation);
    final hideMapInFocusMode =
        widget.isFocusMode &&
        (hasArrived ||
            isWaitingSecurePayment ||
            statusLower == TripStatuses.inProgress ||
            statusLower == ServiceStatusAliases.awaitingConfirmation ||
            statusLower == ServiceStatusAliases.waitingClientConfirmation ||
            statusLower == TripStatuses.completed);
    final readyToStartExecution =
        (isWaitingSecurePayment && isRemainingPaid) ||
        (statusLower == TripStatuses.inProgress && !hasServiceStarted);
    final canShowFinishAction =
        statusLower == TripStatuses.inProgress && hasServiceStarted;

    // Determine colors based on status
    return Container(
      margin: EdgeInsets.only(bottom: widget.isFocusMode ? 6 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(widget.isFocusMode ? 12 : 16),
        boxShadow: widget.isFocusMode
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
        border: Border.all(
          color: widget.isFocusMode
              ? Colors.transparent
              : (_isExpanded ? AppTheme.primaryPurple : Colors.transparent),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            if (widget.isFocusMode) return;
            // Disable expansion for completed/cancelled services
            final st = normalizeServiceStatus(status?.toString());
            if (st == TripStatuses.completed ||
                st == TripStatuses.cancelled ||
                st == TripStatuses.canceled) {
              return;
            }

            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(widget.isFocusMode ? 12 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // HEADER
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            serviceTitle,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          if (widget.isFocusMode &&
                              serviceDescription.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              serviceDescription,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 4),
                          if (!widget.isFocusMode)
                            Text(
                              s['address'] ?? 'Endereço não disponível',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                              maxLines: _isExpanded ? null : 1,
                              overflow: _isExpanded
                                  ? null
                                  : TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'R\$ $price',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                          ),
                        ),
                        if (widget.travelInfo != null)
                          Text(
                            '${widget.travelInfo!['distance']} km',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        // Rating display for finalized services
                        if ((status == 'completed' ||
                                status == 'cancelled' ||
                                status == 'canceled') &&
                            s['service_rating'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(5, (index) {
                                final ratingValue = (s['service_rating'] as num)
                                    .toDouble();
                                return Icon(
                                  index < ratingValue
                                      ? Icons.star
                                      : Icons.star_border,
                                  size: 14,
                                  color: Colors.amber,
                                );
                              }),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                // SCHEDULE BUTTON-LIKE INFO (always visible)
                if (statusLower == TripStatuses.scheduled &&
                    s['scheduled_at'] != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.cyan.shade600, Colors.cyan.shade800],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.cyan.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          LucideIcons.calendarCheck,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            'Agendado para ${_formatScheduledDate(s['scheduled_at'].toString())}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (statusLower == ServiceStatusAliases.scheduleProposed &&
                    s['scheduled_at'] != null) ...[
                  const SizedBox(height: 12),
                  Builder(
                    builder: (_) {
                      final proposedBy =
                          s['schedule_proposed_by_user_id']?.toString() ??
                          s['schedule_proposed_by']?.toString();
                      final providerId = s['provider_id']?.toString();
                      final isClientProposal =
                          proposedBy != null && proposedBy != providerId;
                      final expiresAt = s['schedule_expires_at']?.toString();
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isClientProposal
                              ? Colors.blue[600]
                              : Colors.orange[600],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isClientProposal
                                  ? LucideIcons.calendarClock
                                  : LucideIcons.clock,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isClientProposal
                                        ? 'Cliente propôs: ${_formatScheduledDate(s['scheduled_at'].toString())}'
                                        : 'Aguardando confirmação do cliente',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (expiresAt != null &&
                                      expiresAt.trim().isNotEmpty)
                                    Text(
                                      'Expira em ${_formatScheduledDate(expiresAt)}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],

                // EXPANDED CONTENT
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: _isExpanded
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: widget.isFocusMode ? 8 : 16),
                            if (!widget.isFocusMode) ...[
                              const Divider(),
                              const SizedBox(height: 12),
                            ],

                            // Info Grid
                            if (!widget.isFocusMode)
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildInfoItem(
                                    LucideIcons.mapPin,
                                    'Distância',
                                    '${widget.travelInfo?['distance'] ?? '--'} km',
                                  ),
                                  _buildInfoItem(
                                    LucideIcons.clock,
                                    'Tempo',
                                    '${widget.travelInfo?['duration'] ?? '--'} min',
                                  ),
                                ],
                              ),

                            SizedBox(height: widget.isFocusMode ? 8 : 16),

                            // Mini Map (Only shown if coords exist)
                            if (!hideMapInFocusMode &&
                                s['latitude'] != null &&
                                s['longitude'] != null)
                              Container(
                                height: widget.isFocusMode
                                    ? _focusMapHeight(context)
                                    : 150,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: widget.isFocusMode
                                      ? null
                                      : Border.all(color: Colors.grey[200]!),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: FlutterMap(
                                  mapController: _mapController,
                                  options: MapOptions(
                                    onMapReady: () {
                                      if (_routePoints.isNotEmpty) _fitBounds();
                                    },
                                    initialCenter: LatLng(
                                      double.tryParse(
                                            s['latitude'].toString(),
                                          ) ??
                                          0,
                                      double.tryParse(
                                            s['longitude'].toString(),
                                          ) ??
                                          0,
                                    ),
                                    initialZoom:
                                        14, // Zoom out slightly to see more context
                                    interactionOptions:
                                        const InteractionOptions(
                                          flags: InteractiveFlag.all,
                                        ), // Allow interaction
                                  ),
                                  children: [
                                    AppTileLayer.standard(
                                      mapboxToken: SupabaseConfig.mapboxToken,
                                    ),
                                    if (_providerLocation != null)
                                      PolylineLayer(
                                        polylines: [
                                          // Route Line (if fetched)
                                          if (_routePoints.isNotEmpty)
                                            Polyline(
                                              points: _routePoints,
                                              strokeWidth: 5.0,
                                              color: Colors.blue.shade600,
                                            ),

                                          // Fallback Straight Line (Dashed, if no route yet)
                                          if (_routePoints.isEmpty)
                                            Polyline(
                                              points: [
                                                LatLng(
                                                  _providerLocation!.latitude,
                                                  _providerLocation!.longitude,
                                                ),
                                                LatLng(
                                                  double.tryParse(
                                                        s['latitude']
                                                            .toString(),
                                                      ) ??
                                                      0,
                                                  double.tryParse(
                                                        s['longitude']
                                                            .toString(),
                                                      ) ??
                                                      0,
                                                ),
                                              ],
                                              strokeWidth: 3.0,
                                              color: Colors.grey.withOpacity(
                                                0.5,
                                              ),
                                            ),
                                        ],
                                      ),
                                    MarkerLayer(
                                      markers: [
                                        if (_providerLocation != null)
                                          Marker(
                                            point: LatLng(
                                              _providerLocation!.latitude,
                                              _providerLocation!.longitude,
                                            ),
                                            width: 40,
                                            height: 40,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.green.withOpacity(
                                                  0.2,
                                                ),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 2,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.person_pin_circle,
                                                color: Colors.green,
                                                size: 30,
                                              ),
                                            ),
                                          ),
                                        Marker(
                                          point: LatLng(
                                            double.tryParse(
                                                  s['latitude'].toString(),
                                                ) ??
                                                0,
                                            double.tryParse(
                                                  s['longitude'].toString(),
                                                ) ??
                                                0,
                                          ),
                                          width: 40,
                                          height: 40,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryPurple
                                                  .withOpacity(0.2),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.location_on,
                                              color: Colors.blue,
                                              size: 30,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                            SizedBox(height: widget.isFocusMode ? 8 : 16),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),

                // Actions (Always visible)
                if (isAvailable &&
                    (widget.onAccept != null || widget.onReject != null)) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (widget.onAccept != null) ...[
                        Expanded(
                          child: ElevatedButton(
                            onPressed: widget.onAccept,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[600],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 2,
                              shadowColor: Colors.black.withOpacity(0.18),
                            ),
                            child: const Text('ACEITAR'),
                          ),
                        ),
                        if (widget.onReject != null) const SizedBox(width: 12),
                      ],
                      if (widget.onReject != null)
                        Expanded(
                          child: TextButton(
                            onPressed: widget.onReject,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red[700],
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'RECUSAR',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (isAcceptedPhase ||
                    statusLower == 'in_progress' ||
                    isWaitingSecurePayment) ...[
                  SizedBox(height: widget.isFocusMode ? 8 : 16),
                  if ((isAcceptedPhase ||
                          isWaitingSecurePayment ||
                          statusLower == 'client_arrived') &&
                      s['arrived_at'] == null)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: widget.onArrive,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.isFocusMode
                              ? AppTheme.primaryYellow
                              : Colors.blue[600],
                          foregroundColor: widget.isFocusMode
                              ? Colors.black
                              : Colors.white,
                          padding: EdgeInsets.symmetric(
                            vertical: widget.isFocusMode ? 18 : 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              widget.isFocusMode ? 14 : 8,
                            ),
                          ),
                          textStyle: TextStyle(
                            fontSize: widget.isFocusMode ? 24 : 16,
                            fontWeight: FontWeight.w800,
                          ),
                          elevation: widget.isFocusMode ? 8 : 2,
                          shadowColor: Colors.black.withOpacity(0.25),
                        ),
                        child: Text(
                          widget.isFocusMode
                              ? 'CHEGUEI NO SERVIÇO'
                              : 'CHEGUEI NO LOCAL',
                        ),
                      ),
                    ),

                  if (isWaitingSecurePayment ||
                      (statusLower == TripStatuses.inProgress &&
                          !hasServiceStarted) ||
                      (isAcceptedPhase &&
                          (s['arrived_at'] != null ||
                              s['client_arrived'] == true ||
                              s['client_arrived'] == 'true')))
                    Builder(
                      builder: (context) {
                        final waitingSecurePayment =
                            isWaitingSecurePayment && !isRemainingPaid;
                        final securePaymentDone =
                            (isWaitingSecurePayment && isRemainingPaid) ||
                            (statusLower == TripStatuses.inProgress &&
                                !hasServiceStarted);
                        final bool clientArrived =
                            s['arrived_at'] != null ||
                            s['client_arrived'] == true ||
                            s['client_arrived'] == 'true';

                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: waitingSecurePayment
                                ? Colors.orange.withOpacity(0.1)
                                : securePaymentDone
                                ? Colors.green.withOpacity(0.1)
                                : clientArrived
                                ? AppTheme.primaryBlue.withOpacity(0.1)
                                : Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: waitingSecurePayment
                                  ? Colors.orange
                                  : securePaymentDone
                                  ? Colors.green
                                  : clientArrived
                                  ? AppTheme.primaryBlue
                                  : Colors.orange,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                waitingSecurePayment
                                    ? LucideIcons.shield
                                    : securePaymentDone
                                    ? LucideIcons.badgeCheck
                                    : clientArrived
                                    ? LucideIcons.userCheck
                                    : LucideIcons.hourglass,
                                color: waitingSecurePayment
                                    ? Colors.orange
                                    : securePaymentDone
                                    ? Colors.green
                                    : clientArrived
                                    ? AppTheme.primaryBlue
                                    : Colors.orange,
                                size: 24,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                waitingSecurePayment
                                    ? 'AGUARDANDO PAGAMENTO SEGURO'
                                    : securePaymentDone
                                    ? 'PAGAMENTO SEGURO REALIZADO'
                                    : clientArrived
                                    ? 'CLIENTE NO LOCAL 📍'
                                    : 'Aguardando Pagamento Seguro',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: waitingSecurePayment
                                      ? Colors.orange[800]
                                      : securePaymentDone
                                      ? Colors.green[800]
                                      : clientArrived
                                      ? AppTheme.primaryBlue
                                      : Colors.orange[800],
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                waitingSecurePayment
                                    ? 'Aguardando o cliente pagar os 70% via PIX.'
                                    : securePaymentDone
                                    ? 'Pagamento confirmado. Você já pode iniciar o serviço.'
                                    : clientArrived
                                    ? 'O cliente informou que já chegou ao seu estabelecimento.'
                                    : 'O cliente foi notificado para realizar o pagamento.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                  if (readyToStartExecution)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: widget.onStart,
                        icon: const Icon(LucideIcons.playCircle, size: 18),
                        label: const Text('INICIAR SERVIÇO'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),

                  if (canShowFinishAction) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Quando terminar, pressione o botão abaixo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: widget.onFinish,
                        icon: const Icon(LucideIcons.checkCircle, size: 18),
                        label: const Text(
                          'SERVIÇO CONCLUÍDO',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            height: 1.2,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                          elevation: 6,
                          shadowColor: AppTheme.primaryBlue.withOpacity(0.28),
                          minimumSize: const Size.fromHeight(58),
                          padding: const EdgeInsets.symmetric(
                            vertical: 18,
                            horizontal: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],

                if (isAwaitingClientConfirmation) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[600],
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          LucideIcons.clock,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Pendente - aguardando confirmação do cliente',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          remainingClientConfirmationLabel == null
                              ? 'O cliente foi notificado para confirmar a conclusão do serviço. Se ele não registrar reclamação ou queixa em até 12h, o pagamento será liberado automaticamente. Se houver reclamação, o pagamento entra em análise.'
                              : 'O cliente foi notificado para confirmar a conclusão do serviço. Se ele não registrar reclamação ou queixa, o pagamento será realizado em $remainingClientConfirmationLabel, contado dentro da janela de 12h após o serviço.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                        if (remainingClientConfirmationLabel != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                              ),
                            ),
                            child: Text(
                              'Pagamento automático em $remainingClientConfirmationLabel',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // EXPANDED SCHEDULE BLOCK: depends on who proposed
                if (statusLower == ServiceStatusAliases.scheduleProposed &&
                    !_isScheduling) ...[
                  const SizedBox(height: 16),
                  Builder(
                    builder: (_) {
                      final proposedBy =
                          s['schedule_proposed_by_user_id']?.toString() ??
                          s['schedule_proposed_by']?.toString();
                      final providerId = s['provider_id']?.toString();
                      final isClientProposal =
                          proposedBy != null && proposedBy != providerId;

                      if (isClientProposal) {
                        // CLIENT counter-proposed: show date + ACCEPT button
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue[600],
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                LucideIcons.calendarClock,
                                color: Colors.white,
                                size: 28,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'CONTRA-PROPOSTA DO CLIENTE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (s['scheduled_at'] != null)
                                Text(
                                  _formatScheduledDate(
                                    s['scheduled_at'].toString(),
                                  ),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                )
                              else
                                const Text(
                                  'Data a definir',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white70,
                                  ),
                                ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: widget.onConfirmSchedule,
                                  icon: const Icon(
                                    LucideIcons.checkCircle,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'ACEITAR AGENDAMENTO',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.blue[700],
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      } else {
                        // PROVIDER proposed: waiting for client confirmation
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                LucideIcons.clock,
                                color: Colors.orange,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Aguardando o cliente confirmar seu agendamento.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                  ),
                ],

                // SCHEDULING ACTION (only for open_for_schedule, NOT for schedule_proposed to avoid infinite loop)
                if (canShowScheduleAction) ...[
                  const SizedBox(height: 16),
                  if (!_isScheduling)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _startSchedulingNow,
                        icon: const Icon(LucideIcons.calendar, size: 18),
                        label: Text(
                          statusLower == ServiceStatusAliases.scheduleProposed
                              ? 'ALTERAR AGENDAMENTO'
                              : 'AGENDAR SERVIÇO',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[600],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    )
                  else
                    _buildSchedulingForm(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSchedulingForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Selecione o dia:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 7,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final now = DateTime.now();
              final date = DateTime(now.year, now.month, now.day + index);
              final isSelected =
                  _selectedDate.day == date.day &&
                  _selectedDate.month == date.month;

              final dayName = index == 0
                  ? 'Hoje'
                  : index == 1
                  ? 'Amanhã'
                  : _getDayName(date);
              final dayNum =
                  '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

              return InkWell(
                onTap: () {
                  setState(() {
                    _selectedDate = date;
                    _syncScheduleSelectionWithMinimum();
                  });
                  _updateDynamicMessage();
                },
                child: Container(
                  width: 70,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue[600] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? Colors.blue[700]! : Colors.grey[300]!,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        dayName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected ? Colors.white : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dayNum,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Horário:',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            InkWell(
              onTap: _showTimePickerModal,
              child: _buildTimeDisplay(
                _selectedTime.hour.toString().padLeft(2, '0'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                ':',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            InkWell(
              onTap: _showTimePickerModal,
              child: _buildTimeDisplay(
                _selectedTime.minute.toString().padLeft(2, '0'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: _applyCurrentScheduleNow,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue[700],
                  side: BorderSide(color: Colors.blue[200]!),
                  backgroundColor: Colors.blue[50],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Agora',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => setState(() => _isScheduling = false),
                child: const Text(
                  'CANCELAR',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: () {
                  final finalDate = _normalizedScheduleDateTimeForSubmit(
                    _composeSelectedScheduleDateTime(),
                  );
                  setState(() {
                    _selectedDate = DateTime(
                      finalDate.year,
                      finalDate.month,
                      finalDate.day,
                    );
                    _selectedTime = TimeOfDay.fromDateTime(finalDate);
                  });
                  _updateDynamicMessage();
                  widget.onSchedule?.call(finalDate, '');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'ENVIAR PARA CLIENTE',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeDisplay(String value) {
    return Container(
      width: 60,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showTimePickerModal() {
    showDialog(
      context: context,
      builder: (context) {
        final minimum = _minimumScheduleDateTime();
        final selectedDateTime = _composeSelectedScheduleDateTime();
        final selectedIsToday = _isSameCalendarDay(_selectedDate, minimum);
        final initialDateTime =
            selectedIsToday && selectedDateTime.isBefore(minimum)
            ? minimum
            : selectedDateTime;
        TimeOfDay tempTime = TimeOfDay.fromDateTime(initialDateTime);
        return Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Selecione o Horário',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.time,
                      initialDateTime: DateTime(
                        2024,
                        1,
                        1,
                        initialDateTime.hour,
                        initialDateTime.minute,
                      ),
                      minimumDate: selectedIsToday
                          ? DateTime(2024, 1, 1, minimum.hour, minimum.minute)
                          : null,
                      use24hFormat: true,
                      onDateTimeChanged: (DateTime newDate) {
                        HapticFeedback.selectionClick();
                        SystemSound.play(SystemSoundType.click);
                        tempTime = TimeOfDay(
                          hour: newDate.hour,
                          minute: newDate.minute,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _selectedTime = tempTime;
                          _syncScheduleSelectionWithMinimum();
                        });
                        _updateDynamicMessage();
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _getDayName(DateTime date) {
    const days = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
    return days[date.weekday - 1];
  }

  String _formatScheduledDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      const days = [
        'Segunda',
        'Terça',
        'Quarta',
        'Quinta',
        'Sexta',
        'Sábado',
        'Domingo',
      ];
      final dayName = days[dt.weekday - 1];
      final date =
          '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      final time =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      return '$dayName, $date às $time';
    } catch (_) {
      return isoDate;
    }
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppTheme.primaryPurple),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
