import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/utils/navigation_helper.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';

class ScheduledServiceScreen extends StatefulWidget {
  final String serviceId;

  const ScheduledServiceScreen({super.key, required this.serviceId});

  @override
  State<ScheduledServiceScreen> createState() => _ScheduledServiceScreenState();
}

class _ScheduledServiceScreenState extends State<ScheduledServiceScreen> {
  final ApiService _api = ApiService();
  bool _isLoading = true;
  Map<String, dynamic>? _service;

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadService();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _loadService(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadService({bool silent = false}) async {
    try {
      final data = await _api.getServiceDetails(widget.serviceId);
      debugPrint(
        '🔍 [ScheduledService] Data loaded: ${data['id']} - Status: ${data['status']}',
      );
      if (mounted) {
        setState(() {
          _service = data;
          if (!silent) _isLoading = false;
        });

        // Fetch full profile if provider name is generic
        final pName = _service?['provider_name'];
        final pId = _service?['provider_id'];
        if ((pName == null || pName == 'Prestador') && pId != null) {
          final pIdInt = int.tryParse(pId.toString());
          if (pIdInt != null) {
            _fetchFullProviderProfile(pIdInt);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading service: $e');
      if (mounted && !silent) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar agendamento: $e')),
        );
      }
    }
  }

  Future<void> _fetchFullProviderProfile(int providerId) async {
    try {
      final profile = await _api.getProviderProfile(providerId);
      if (mounted && _service != null) {
        setState(() {
          final name = profile['name'] ?? profile['full_name'];
          if (name != null && name.toString().isNotEmpty) {
            _service!['provider_name'] = name;
          }

          final avatar =
              profile['avatar_url'] ?? profile['photo'] ?? profile['avatar'];
          if (avatar != null && avatar.toString().isNotEmpty) {
            _service!['provider_avatar'] = avatar;
          }

          if (profile['rating'] != null) {
            _service!['provider_rating'] = profile['rating'];
          }
          if (profile['rating_count'] != null) {
            _service!['provider_rating_count'] = profile['rating_count'];
          }
        });
      }
    } catch (e) {
      debugPrint(
        '⚠️ [ScheduledService] Error fetching full provider profile: $e',
      );
    }
  }

  Future<void> _openMap() async {
    final providerLat =
        _service?['provider_lat'] ?? _service?['provider']?['latitude'];
    final providerLon =
        _service?['provider_lon'] ?? _service?['provider']?['longitude'];

    if (providerLat == null || providerLon == null) return;

    await NavigationHelper.openNavigation(
      latitude: double.tryParse(providerLat.toString()) ?? 0,
      longitude: double.tryParse(providerLon.toString()) ?? 0,
    );
  }

  Future<void> _cancelService() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar Agendamento?'),
        content: const Text('Tem certeza que deseja cancelar este serviço?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Não'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sim, Cancelar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _api.cancelService(widget.serviceId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Agendamento cancelado.')),
          );
          context.pop(); // Back to home
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Erro ao cancelar: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalhes do Agendamento')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_service == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalhes do Agendamento')),
        body: const Center(child: Text('Agendamento não encontrado.')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Agendamento'),
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadService(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            vertical: 16,
          ), // Removida margem horizontal geral para permitir cards largos
          child: Column(
            children: [
              _buildStatusCard(),
              _buildMapSection(),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _buildProviderInfo(),
                    const SizedBox(height: 24),
                    _buildActions(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final scheduledAtStr = _service?['scheduled_at'];
    DateTime? scheduledAt;
    if (scheduledAtStr != null) {
      scheduledAt = DateTime.tryParse(scheduledAtStr);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          0,
        ), // Removido border radius lateral para alargar o card
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryYellow.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.calendarCheck,
              size: 40,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Agendamento Confirmado',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (scheduledAt != null)
            Text(
              '${scheduledAt.day}/${scheduledAt.month} às ${scheduledAt.hour.toString().padLeft(2, '0')}:${scheduledAt.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          const SizedBox(height: 24),
          // Time to leave calculation
          _buildTimeToLeave(scheduledAt),
        ],
      ),
    );
  }

  Widget _buildTimeToLeave(DateTime? scheduledAt) {
    if (scheduledAt == null) return const SizedBox.shrink();

    final clientLat = double.tryParse(_service?['latitude']?.toString() ?? '');
    final clientLon = double.tryParse(_service?['longitude']?.toString() ?? '');
    final providerLat = double.tryParse(
      _service?['provider_lat']?.toString() ?? '',
    );
    final providerLon = double.tryParse(
      _service?['provider_lon']?.toString() ?? '',
    );

    int travelTime = 30; // Default fallback

    if (clientLat != null &&
        clientLon != null &&
        providerLat != null &&
        providerLon != null) {
      // Calcula distância em KM
      final distanceKm = const Distance().as(
        LengthUnit.Kilometer,
        LatLng(clientLat, clientLon),
        LatLng(providerLat, providerLon),
      );

      // Travel Time = (Distância / Velocidade Média) * 60 minutos
      // Velocidade Média = 25 km/h
      travelTime = ((distanceKm / 25) * 60).round();

      // Mínimo de 5 minutos se a distância for muito curta
      if (travelTime < 5) travelTime = 5;
    } else {
      // Fallback para o valor do backend se disponível
      travelTime =
          int.tryParse(_service?['travel_time_min']?.toString() ?? '30') ?? 30;
    }

    final leaveAt = scheduledAt.subtract(Duration(minutes: travelTime));
    final now = DateTime.now();

    final isLate = now.isAfter(leaveAt);
    final timeStr =
        '${leaveAt.hour.toString().padLeft(2, '0')}:${leaveAt.minute.toString().padLeft(2, '0')}';

    final bgColor = isLate ? Colors.red[50] : Colors.blue[50];
    final textColor = isLate ? Colors.red : Colors.blue;
    final message = isLate
        ? 'Saia agora! ($timeStr)'
        : 'Saia de casa às $timeStr';
    final icon = isLate ? LucideIcons.alertTriangle : LucideIcons.clock;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 20),
          const SizedBox(width: 8),
          Text(
            message,
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMapSection() {
    final clientLat = double.tryParse(_service?['latitude']?.toString() ?? '');
    final clientLon = double.tryParse(_service?['longitude']?.toString() ?? '');
    final providerLat = double.tryParse(
      _service?['provider_lat']?.toString() ?? '',
    );
    final providerLon = double.tryParse(
      _service?['provider_lon']?.toString() ?? '',
    );

    // Se não tiver pelo menos o destino, não mostra o mapa
    if (providerLat == null || providerLon == null) {
      return const SizedBox.shrink();
    }

    final centerLat = clientLat != null
        ? (clientLat + providerLat) / 2
        : providerLat;
    final centerLon = clientLon != null
        ? (clientLon + providerLon) / 2
        : providerLon;

    // Distância calculada se tivermos os dois pontos
    final distanceKm = (clientLat != null && clientLon != null)
        ? const Distance()
              .as(
                LengthUnit.Kilometer,
                LatLng(clientLat, clientLon),
                LatLng(providerLat, providerLon),
              )
              .toStringAsFixed(1)
        : '---';

    return InkWell(
      onTap: _openMap,
      child: Column(
        children: [
          IgnorePointer(
            ignoring:
                true, // Importante: Ignora toques no mapa para que o InkWell os receba
            child: Container(
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(0),
                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(0),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(centerLat, centerLon),
                    initialZoom: (clientLat != null) ? 14 : 16,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/{z}/{x}/{y}@2x?access_token=${dotenv.env['MAPBOX_TOKEN'] ?? ''}',
                      userAgentPackageName: 'com.play101.app',
                      tileDimension: 512,
                      zoomOffset: -1,
                      maxZoom: 22,
                    ),
                    if (clientLat != null && clientLon != null)
                      PolylineLayer(
                        polylines: <Polyline>[
                          Polyline(
                            points: [
                              LatLng(clientLat, clientLon),
                              LatLng(providerLat, providerLon),
                            ],
                            strokeWidth: 3,
                            color: AppTheme.primaryPurple,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (clientLat != null && clientLon != null)
                          Marker(
                            point: LatLng(clientLat, clientLon),
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.person_pin_circle,
                              color: Colors.blue,
                              size: 40,
                            ),
                          ),
                        Marker(
                          point: LatLng(providerLat, providerLon),
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_service?['provider_address'] != null)
            Text(
              _service!['provider_address'],
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.mapPin, size: 16, color: AppTheme.primaryPurple),
              const SizedBox(width: 4),
              Text(
                '$distanceKm km • ~${_service?['travel_time_min'] ?? 30} min',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProviderInfo() {
    final name = _service?['provider_name']?.toString() ?? 'Prestador';
    final avatarUrl = _service?['provider_avatar']?.toString();
    final rating =
        double.tryParse(_service?['provider_rating']?.toString() ?? '0') ?? 0.0;
    final ratingCount =
        int.tryParse(_service?['provider_rating_count']?.toString() ?? '0') ??
        0;
    final providerId = _service?['provider_id'];

    return GestureDetector(
      onTap: () {
        if (providerId != null) {
          context.push(
            '/provider-profile',
            extra: int.tryParse(providerId.toString()),
          );
        }
      },
      child: Container(
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
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: AppTheme.primaryPurple,
              backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                  ? NetworkImage(avatarUrl)
                  : null,
              child: (avatarUrl != null && avatarUrl.isNotEmpty)
                  ? null
                  : Text(
                      name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Profissional',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 14, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(
                        rating > 0 ? rating.toStringAsFixed(1) : 'Novo',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      if (ratingCount > 0)
                        Text(
                          ' ($ratingCount avaliações)',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ver perfil completo',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.primaryPurple,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {
                context.push('/chat/${widget.serviceId}');
              },
              icon: const Icon(LucideIcons.messageCircle, color: Colors.green),
              style: IconButton.styleFrom(
                backgroundColor: Colors.green[50],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    final status = _service?['status'];
    final bool clientHasArrived =
        status == 'client_arrived' ||
        _service?['arrived_at'] != null ||
        _service?['client_arrived'] == true ||
        _service?['client_arrived'] == 'true';

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _openMap,
            icon: const Icon(LucideIcons.map),
            label: const Text('Abrir no Maps'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              elevation: 0,
              side: BorderSide(color: Colors.grey[300]!),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 1. Hora de Sair (Departing)
        if (status == 'accepted' || status == 'scheduled')
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                debugPrint(
                  '🏁 [ScheduledService] Clicking ESTOU A CAMINHO for: ${widget.serviceId}',
                );
                try {
                  await ApiService().markClientDeparting(widget.serviceId);
                  debugPrint(
                    '✅ [ScheduledService] markClientDeparting success',
                  );
                  _loadService();
                } catch (e) {
                  debugPrint(
                    '❌ [ScheduledService] Error marking departure: $e',
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao marcar saída: $e')),
                    );
                  }
                }
              },
              icon: const Icon(LucideIcons.car),
              label: const Text('Estou a Caminho'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),

        // 2. Cheguei (Arrived)
        if (status == 'client_departing' ||
            (status == 'accepted' && !clientHasArrived))
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                debugPrint(
                  '🏁 [ScheduledService] Clicking CHEGUEI NO LOCAL for: ${widget.serviceId}',
                );
                try {
                  await ApiService().markClientArrived(widget.serviceId);
                  debugPrint('✅ [ScheduledService] markClientArrived success');
                  _loadService();
                } catch (e) {
                  debugPrint('❌ [ScheduledService] Error marking arrived: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro ao marcar chegada: $e')),
                    );
                  }
                }
              },
              icon: const Icon(LucideIcons.mapPin),
              label: const Text('Cheguei no Local'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),

        // 3. Pagar Restante (Pay Remaining)
        // If client arrived, show payment button (unless already paid)
        if (clientHasArrived || status == 'client_arrived') ...[
          // If already paid manual or completed, don't show pay button
          if (status != 'completed' &&
              _service?['payment_remaining_status'] != 'paid_manual' &&
              _service?['payment_remaining_status'] != 'paid')
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _payRemaining, // Using existing payment flow
                icon: const Icon(LucideIcons.creditCard),
                label: const Text('PAGAR RESTANTE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
        ],

        if (!clientHasArrived &&
            status != 'client_departing' &&
            status != 'client_arrived') ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: _cancelService,
            style: TextButton.styleFrom(foregroundColor: Colors.red[300]),
            child: const Text('Cancelar Agendamento'),
          ),
        ],
      ],
    );
  }

  void _payRemaining() {
    if (_service == null) return;

    final double? estimatedPrice = double.tryParse(
      _service!['price_estimated']?.toString() ?? '',
    );
    final double? price = double.tryParse(_service!['price']?.toString() ?? '');
    final double total = price ?? estimatedPrice ?? 0.0;

    // Calcula o restante (assumindo depósito de 30% se 'price_deposit' existir)
    double remaining = total;
    final double? deposit = double.tryParse(
      _service!['price_deposit']?.toString() ?? '',
    );
    if (deposit != null && total > deposit) {
      remaining = total - deposit;
    } else if (total > 0) {
      // Fallback: Se não tem depósito explícito, assume que o restante é 70%
      // (supondo fluxo padrão de 30/70) OU simplesmente cobra o total se não foi pago nada.
      // Melhor abordagem: Verificar payment_remaining_status.
      // Se estamos aqui, é porque deve pagar o restante.
      // Vamos assumir que o 'amount' passado para PaymentScreen é o valor A PAGAR AGORA.
      // Se já pagou 30%, faltam 70%.
      if (_service!['payment_status'] == 'partially_paid') {
        remaining = total * 0.7;
      }
    }

    context.push(
      '/payment/${widget.serviceId}',
      extra: {
        'serviceId': widget.serviceId,
        'type': 'remaining',
        'amount': remaining,
        'total': total,
        'providerName': _service!['provider_name'],
        'serviceType': _service!['service_type'],
      },
    );
  }
}
