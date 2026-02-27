import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../services/api_service.dart';
import '../../../services/notification_service.dart';

class ScheduledNotificationModal extends StatefulWidget {
  final String serviceId;
  final Map<String, dynamic>? initialData;

  const ScheduledNotificationModal({
    super.key,
    required this.serviceId,
    this.initialData,
  });

  @override
  State<ScheduledNotificationModal> createState() =>
      _ScheduledNotificationModalState();
}

class _ScheduledNotificationModalState
    extends State<ScheduledNotificationModal> {
  final _api = ApiService();
  final MapController _mapController = MapController();
  final AudioPlayer _notificationPlayer = AudioPlayer();

  Map<String, dynamic>? _serviceData;
  bool _isLoadingDetails = true;
  bool _isLoadingAction = false;
  bool _isMuted = false;

  List<LatLng> _routePoints = [];
  String _routeDistance = '--';
  String _routeDuration = '--';

  @override
  void initState() {
    super.initState();
    _playNotificationSound();
    _serviceData = widget.initialData;
    if (_serviceData != null && _serviceData!.containsKey('latitude')) {
      _isLoadingDetails = false;
      _loadRoute();
    } else {
      _loadDetails();
    }
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    _notificationPlayer.stop();
    _notificationPlayer.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    try {
      final data = await _api.getServiceDetails(widget.serviceId);
      if (mounted) {
        setState(() {
          _serviceData = data;
          _isLoadingDetails = false;
        });
        _loadRoute();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  }

  Future<void> _playNotificationSound() async {
    try {
      await _notificationPlayer.setReleaseMode(ReleaseMode.loop);
      await _notificationPlayer.setSource(AssetSource('sounds/chamado.mp3'));
      await _notificationPlayer.play(
        AssetSource('sounds/chamado.mp3'),
        volume: 1.0,
      );
    } catch (e) {
      debugPrint('[ScheduledNotificationModal] Error playing sound: $e');
    }
  }

  void _muteSound() {
    _notificationPlayer.stop();
    setState(() => _isMuted = true);
  }

  Future<void> _loadRoute() async {
    try {
      final s = _serviceData!;
      final destLat =
          double.tryParse(s['latitude']?.toString() ?? '0') ?? 0;
      final destLng =
          double.tryParse(s['longitude']?.toString() ?? '0') ?? 0;

      double provLat =
          double.tryParse(s['provider_lat']?.toString() ?? '0') ?? 0;
      double provLon =
          double.tryParse(s['provider_lon']?.toString() ?? '0') ?? 0;

      if (provLat == 0 || provLon == 0) {
        try {
          final pos = await Geolocator.getLastKnownPosition(
            forceAndroidLocationManager: true,
          );
          if (pos != null) {
            provLat = pos.latitude;
            provLon = pos.longitude;
          }
        } catch (_) {}
      }

      if (destLat == 0 || destLng == 0) {
        if (mounted) _mapController.move(LatLng(destLat, destLng), 14);
        return;
      }

      if (provLat == 0 || provLon == 0) {
        if (mounted) _mapController.move(LatLng(destLat, destLng), 14);
        return;
      }

      final url = Uri.parse(
        'http://router.project-osrm.org/route/v1/driving/$provLon,$provLat;$destLng,$destLat?overview=full&geometries=geojson',
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final coordinates =
              (route['geometry']['coordinates'] as List);
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

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _routePoints.isNotEmpty) {
                try {
                  final bounds = LatLngBounds.fromPoints(_routePoints);
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
    } catch (e) {
      debugPrint('[ScheduledNotificationModal] Error loading route: $e');
    }
  }

  Future<void> _confirmSchedule() async {
    if (_isLoadingAction) return;

    _notificationPlayer.stop();
    setState(() => _isLoadingAction = true);

    try {
      // Comportamento idêntico ao aceitar serviço normal
      await _api.logServiceEvent(
        widget.serviceId,
        'ACCEPTED',
        'Scheduled Modal - Provider Confirmed Schedule',
      );
      // Sprint 2: Usar Supabase SDK em vez do backend legado
      await Supabase.instance.client
          .from('service_requests_new')
          .update({'status': 'accepted', 'accepted_at': DateTime.now().toIso8601String()})
          .eq('id', widget.serviceId);

      NotificationService().stopPersistentNotification(widget.serviceId);
      await NotificationService().cancelAll();

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Agendamento confirmado!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao confirmar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingAction = false);
    }
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    Color backgroundColor = Colors.white,
    Color textColor = Colors.black,
    double valueFontSize = 20,
    String? subtitle,
    IconData? subtitleIcon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: textColor.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: textColor.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: valueFontSize,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (subtitleIcon != null) ...[
                  Icon(subtitleIcon, size: 11, color: textColor.withValues(alpha: 0.6)),
                  const SizedBox(width: 4),
                ],
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: textColor.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingDetails) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Carregando agendamento...'),
            ],
          ),
        ),
      );
    }

    final s = _serviceData ?? widget.initialData ?? {};
    final lat = double.tryParse(s['latitude']?.toString() ?? '0') ?? 0;
    final lon = double.tryParse(s['longitude']?.toString() ?? '0') ?? 0;
    final hasMap = lat != 0 && lon != 0;

    final double netAmount =
        double.tryParse(s['provider_amount']?.toString() ?? s['price']?.toString() ?? '0') ?? 0;
    final String description = s['description'] ?? s['profession'] ?? s['category_name'] ?? 'Serviço Agendado';
    final String address = s['address'] ?? 'Endereço não informado';

    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.amber, width: 3),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
            maxWidth: MediaQuery.of(context).size.width,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.calendarCheck,
                        color: Colors.amber,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Agendamento - Hora de Sair!',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Confirme para iniciar o atendimento',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (!_isMuted)
                      IconButton(
                        icon: const Icon(LucideIcons.volume2),
                        onPressed: _muteSound,
                        tooltip: 'Silenciar',
                      )
                    else
                      const Icon(LucideIcons.volumeX, color: Colors.grey),
                  ],
                ),
              ),
              const Divider(height: 1),

              // ── Scrollable Content ───────────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Mapa com rota
                      if (hasMap)
                        Container(
                          height: 220,
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
                                TileLayer(
                                  urlTemplate:
                                      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                                  subdomains: const ['a', 'b', 'c', 'd'],
                                  userAgentPackageName: 'com.play101.app',
                    tileSize: 512,
                    zoomOffset: -1,
                    maxZoom: 22,
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
                                      child: const Icon(
                                        Icons.location_on,
                                        color: Colors.red,
                                        size: 34,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Título e descrição do serviço
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s['category_name'] ?? 'Serviço',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 16),

                      // Linha: Preço | Distância + Tempo
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              icon: LucideIcons.wallet,
                              label: 'Seu Ganho Líquido',
                              value: 'R\$ ${netAmount.toStringAsFixed(2)}',
                              backgroundColor: const Color(0xFFFFD700),
                              textColor: Colors.black,
                              valueFontSize: 24,
                              subtitle: 'Aguardando Início',
                              subtitleIcon: LucideIcons.checkCircle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              icon: LucideIcons.mapPin,
                              label: 'Distância',
                              value: _routeDistance,
                              valueFontSize: 18,
                              subtitle: _routeDuration != '--'
                                  ? 'Tempo: $_routeDuration'
                                  : null,
                              subtitleIcon: LucideIcons.clock,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Endereço
                      Row(
                        children: [
                          const Icon(
                            LucideIcons.map,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              address,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Botão CONFIRMAR AGENDAMENTO
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isLoadingAction ? null : _confirmSchedule,
                          icon: _isLoadingAction
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(LucideIcons.checkCircle2,
                                  color: Colors.white),
                          label: Text(
                            _isLoadingAction
                                ? 'CONFIRMANDO...'
                                : 'CONFIRMAR AGENDAMENTO',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

