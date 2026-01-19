import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter/cupertino.dart';

import '../../../../core/theme/app_theme.dart';

class ProviderServiceCard extends StatefulWidget {
  final Map<String, dynamic> service;
  final VoidCallback? onNavigate;
  final VoidCallback? onArrive;
  final VoidCallback? onStart;
  final VoidCallback? onFinish;
  final VoidCallback? onViewDetails;
  final Function(DateTime scheduledAt, String message)? onSchedule;
  final VoidCallback? onConfirmSchedule;
  final Map<String, String>? travelInfo;

  const ProviderServiceCard({
    super.key,
    required this.service,
    this.onNavigate,
    this.onArrive,
    this.onStart,
    this.onFinish,
    this.onViewDetails,
    this.onSchedule,
    this.onConfirmSchedule,
    this.travelInfo,
  });

  @override
  State<ProviderServiceCard> createState() => _ProviderServiceCardState();
}

class _ProviderServiceCardState extends State<ProviderServiceCard> with TickerProviderStateMixin {
  bool _isExpanded = false;
  bool _isScheduling = false;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  final TextEditingController _messageController = TextEditingController();
  final MapController _mapController = MapController();
  LatLng? _providerLocation;
  List<LatLng> _routePoints = [];
  bool _isLoadingRoute = false;

  @override
  void initState() {
    super.initState();
    _updateDynamicMessage();
    _loadProviderLocation();
  }

  Future<void> _loadProviderLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() {
          _providerLocation = LatLng(position.latitude, position.longitude);
        });
        
        // Fetch Route if destination exists
        final s = widget.service;
        if (s['latitude'] != null && s['longitude'] != null) {
           final dest = LatLng(
             double.tryParse(s['latitude'].toString()) ?? 0,
             double.tryParse(s['longitude'].toString()) ?? 0,
           );
           _fetchRoute(_providerLocation!, dest);
        }
      }
    } catch (e) {
      debugPrint('Error getting provider location: $e');
    }
  }

  Future<void> _fetchRoute(LatLng start, LatLng end) async {
    if (!mounted) return;
    setState(() => _isLoadingRoute = true);

    try {
      // OSRM Public API (For demo purposes)
      final url = Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson');

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
              _isLoadingRoute = false;
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
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  void _fitBounds() {
    if (_routePoints.isEmpty || !mounted) return;
    
    // flutter_map 6+ (using fitCamera)
    try {
      final bounds = LatLngBounds.fromPoints(_routePoints);
      _mapController.fitCamera(CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(32),
      ));
    } catch (e) {
      debugPrint('Error fitting bounds: $e');
    }
  }

  void _updateDynamicMessage() {
    final s = widget.service;
    final title = (s['title'] ?? s['description'] ?? s['profession'] ?? s['category_name'] ?? 'Serviço')
        .toString().replaceAll('Serviço: ', '').trim();
    
    final day = _getDayName(_selectedDate);
    final dateStr = '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}';
    final timeStr = '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

    setState(() {
      _messageController.text = 'Olá! Gostaria de agendar o serviço "$title" para $day ($dateStr) às $timeStr. Aguardo sua confirmação.';
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.service;
    final status = s['status'];
    final price = s['provider_amount'] ?? s['price_estimated'] ?? 0;
    
    // Determine colors based on status
    Color statusColor = Colors.grey;
    if (status == 'accepted' || status == 'confirmed') statusColor = Colors.blue;
    if (status == 'scheduled') statusColor = Colors.cyan.shade600;
    if (status == 'in_progress') statusColor = Colors.green;
    if (status == 'pending') statusColor = Colors.orange;
    if (status == 'waiting_client_confirmation') statusColor = Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
        border: Border.all(color: _isExpanded ? AppTheme.primaryPurple : Colors.transparent),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            // Disable expansion for completed/cancelled services
            final st = status?.toString().toLowerCase();
            if (st == 'completed' || st == 'cancelled' || st == 'canceled') return;

            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                            (s['title'] ?? s['description'] ?? s['profession'] ?? s['category_name'] ?? 'Serviço').toString().replaceAll('Serviço: ', '').trim(),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s['address'] ?? 'Endereço não disponível',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                            maxLines: _isExpanded ? null : 1,
                            overflow: _isExpanded ? null : TextOverflow.ellipsis,
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
                             style: const TextStyle(fontSize: 12, color: Colors.grey),
                           ),
                        // Rating display for finalized services
                        if ((status == 'completed' || status == 'cancelled' || status == 'canceled') && s['service_rating'] != null)
                           Padding(
                             padding: const EdgeInsets.only(top: 4.0),
                             child: Row(
                               mainAxisSize: MainAxisSize.min,
                               children: List.generate(5, (index) {
                                 final ratingValue = (s['service_rating'] as num).toDouble();
                                 return Icon(
                                   index < ratingValue ? Icons.star : Icons.star_border,
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
                if (status == 'scheduled' && s['scheduled_at'] != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                        const Icon(LucideIcons.calendarCheck, color: Colors.white, size: 20),
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

                if (status == 'schedule_proposed' && s['scheduled_at'] != null) ...[
                  const SizedBox(height: 12),
                  Builder(builder: (_) {
                    final proposedBy = s['schedule_proposed_by']?.toString();
                    final providerId = s['provider_id']?.toString();
                    final isClientProposal = proposedBy != null && proposedBy != providerId;
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isClientProposal ? Colors.blue[600] : Colors.orange[600],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isClientProposal ? LucideIcons.calendarClock : LucideIcons.clock,
                            color: Colors.white, size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isClientProposal
                                ? 'Cliente propôs: ${_formatScheduledDate(s['scheduled_at'].toString())}'
                                : 'Aguardando confirmação do cliente',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],

                // EXPANDED CONTENT
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: _isExpanded
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                             const SizedBox(height: 16),
                             const Divider(),
                             const SizedBox(height: 12),
                            
                             // Info Grid
                             Row(
                               mainAxisAlignment: MainAxisAlignment.spaceBetween,
                               children: [
                                 _buildInfoItem(LucideIcons.mapPin, 'Distância', '${widget.travelInfo?['distance'] ?? '--'} km'),
                                 _buildInfoItem(LucideIcons.clock, 'Tempo', '${widget.travelInfo?['duration'] ?? '--'} min'),
                               ],
                             ),
                             
                             const SizedBox(height: 16),
                             
                             // Mini Map (Only shown if coords exist)
                             if (s['latitude'] != null && s['longitude'] != null)
                               Container(
                                 height: 150,
                                 decoration: BoxDecoration(
                                   borderRadius: BorderRadius.circular(12),
                                   border: Border.all(color: Colors.grey[200]!),
                                 ),
                                 clipBehavior: Clip.antiAlias,
                                 child: FlutterMap(
                                   options: MapOptions(
                                     onMapReady: () {
                                        if (_routePoints.isNotEmpty) _fitBounds();
                                     },
                                     initialCenter: LatLng(
                                       double.tryParse(s['latitude'].toString()) ?? 0,
                                       double.tryParse(s['longitude'].toString()) ?? 0,
                                     ),
                                     initialZoom: 14, // Zoom out slightly to see more context
                                     interactionOptions: const InteractionOptions(flags: InteractiveFlag.all), // Allow interaction
                                   ),
                                   children: [
                                     TileLayer(
                                       urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=\${dotenv.env[\'MAPBOX_TOKEN\'] ?? \'\'}',
                                       userAgentPackageName: 'com.play101.app',
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
                                                    double.tryParse(s['latitude'].toString()) ?? 0,
                                                    double.tryParse(s['longitude'].toString()) ?? 0,
                                                  ),
                                                ],
                                                strokeWidth: 3.0,
                                                color: Colors.grey.withValues(alpha: 0.5),
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
                                                  color: Colors.green.withValues(alpha: 0.2),
                                                  shape: BoxShape.circle,
                                                  border: Border.all(color: Colors.white, width: 2),
                                                ),
                                                child: const Icon(Icons.person_pin_circle, color: Colors.green, size: 30),
                                              ),
                                            ),
                                          Marker(
                                            point: LatLng(
                                              double.tryParse(s['latitude'].toString()) ?? 0,
                                              double.tryParse(s['longitude'].toString()) ?? 0,
                                           ),
                                           width: 40,
                                           height: 40,
                                           child: Container(
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryPurple.withValues(alpha: 0.2),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.location_on, color: Colors.blue, size: 30),
                                            ),
                                         ),
                                       ],
                                     ),
                                   ],
                                 ),
                               ),

                             const SizedBox(height: 16),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),

                // Actions (Always visible)
                if (status == 'accepted' || status == 'in_progress' || status == 'waiting_payment_remaining') ...[
                  const SizedBox(height: 16),
                  if (status == 'accepted' && s['arrived_at'] == null)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: widget.onArrive,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[600],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Cheguei no Local'),
                      ),
                    ),
                  
                  if (status == 'waiting_payment_remaining' || (status == 'accepted' && (s['arrived_at'] != null || s['client_arrived'] == true || s['client_arrived'] == 'true')))
                    Builder(builder: (context) {
                      final bool clientArrived = s['arrived_at'] != null || s['client_arrived'] == true || s['client_arrived'] == 'true';
                      
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: clientArrived ? AppTheme.primaryBlue.withOpacity(0.1) : Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: clientArrived ? AppTheme.primaryBlue : Colors.orange),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              clientArrived ? LucideIcons.userCheck : LucideIcons.hourglass, 
                              color: clientArrived ? AppTheme.primaryBlue : Colors.orange, 
                              size: 24
                            ),
                            const SizedBox(height: 8),
                            Text(
                              clientArrived ? 'CLIENTE NO LOCAL 📍' : 'Aguardando Pagamento Seguro',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: clientArrived ? AppTheme.primaryBlue : Colors.orange[800],
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              clientArrived 
                                ? 'O cliente informou que já chegou ao seu estabelecimento.'
                                : 'O cliente foi notificado para realizar o pagamento.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      );
                    }),
                  
                  if (status == 'in_progress')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: widget.onFinish,
                        icon: const Icon(LucideIcons.checkCircle, size: 18),
                        label: const Text('FINALIZAR SERVIÇO'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  
                ],

                if (status == 'waiting_client_confirmation') ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[600],
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(LucideIcons.clock, color: Colors.white, size: 28),
                        const SizedBox(height: 12),
                        const Text(
                          'Aguardando Confirmação do Cliente',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'O cliente foi notificado para confirmar a conclusão do serviço. Se ele não confirmar em até 24h, o serviço será confirmado automaticamente pela plataforma.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.9)),
                        ),
                      ],
                    ),
                  ),
                ],

                // EXPANDED SCHEDULE BLOCK: depends on who proposed
                if (status == 'schedule_proposed' && !_isScheduling) ...[
                  const SizedBox(height: 16),
                  Builder(builder: (_) {
                    final proposedBy = s['schedule_proposed_by']?.toString();
                    final providerId = s['provider_id']?.toString();
                    final isClientProposal = proposedBy != null && proposedBy != providerId;
                    
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
                              color: Colors.blue.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            const Icon(LucideIcons.calendarClock, color: Colors.white, size: 28),
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
                                _formatScheduledDate(s['scheduled_at'].toString()),
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
                                style: TextStyle(fontSize: 16, color: Colors.white70),
                              ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: widget.onConfirmSchedule,
                                icon: const Icon(LucideIcons.checkCircle, size: 18),
                                label: const Text('ACEITAR AGENDAMENTO', style: TextStyle(fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.blue[700],
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                          color: Colors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.clock, color: Colors.orange, size: 20),
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
                  }),
                ],

                // SCHEDULING ACTION (only for open_for_schedule, NOT for schedule_proposed to avoid infinite loop)
                if (status == 'open_for_schedule') ...[
                  const SizedBox(height: 16),
                  if (!_isScheduling)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => setState(() => _isScheduling = true),
                        icon: const Icon(LucideIcons.calendar, size: 18),
                        label: Text(status == 'schedule_proposed' ? 'ALTERAR AGENDAMENTO' : 'AGENDAR SERVIÇO'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[600],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 7,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final date = DateTime.now().add(Duration(days: index));
              final isSelected = _selectedDate.day == date.day && _selectedDate.month == date.month;
              
              final dayName = index == 0 ? 'Hoje' : index == 1 ? 'Amanhã' : _getDayName(date);
              final dayNum = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

              return InkWell(
                onTap: () {
                  setState(() => _selectedDate = date);
                  _updateDynamicMessage();
                },
                child: Container(
                  width: 70,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue[600] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isSelected ? Colors.blue[700]! : Colors.grey[300]!),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        dayName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            InkWell(
              onTap: _showTimePickerModal,
              child: _buildTimeDisplay(_selectedTime.hour.toString().padLeft(2, '0')),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(':', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            InkWell(
              onTap: _showTimePickerModal,
              child: _buildTimeDisplay(_selectedTime.minute.toString().padLeft(2, '0')),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => setState(() => _isScheduling = false),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: () {
                  final finalDate = DateTime(
                    _selectedDate.year,
                    _selectedDate.month,
                    _selectedDate.day,
                    _selectedTime.hour,
                    _selectedTime.minute,
                  );
                  widget.onSchedule?.call(finalDate, '');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('ENVIAR PARA CLIENTE', style: TextStyle(fontWeight: FontWeight.bold)),
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
        TimeOfDay tempTime = _selectedTime;
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
                      initialDateTime: DateTime(2024, 1, 1, _selectedTime.hour, _selectedTime.minute),
                      use24hFormat: true,
                      onDateTimeChanged: (DateTime newDate) {
                        tempTime = TimeOfDay(hour: newDate.hour, minute: newDate.minute);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() => _selectedTime = tempTime);
                        _updateDynamicMessage();
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
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
      const days = ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo'];
      final dayName = days[dt.weekday - 1];
      final date = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
