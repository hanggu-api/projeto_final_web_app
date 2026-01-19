import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/api_service.dart';
import '../../core/theme/app_theme.dart';
import 'package:intl/intl.dart';

class ProviderProfileScreen extends StatefulWidget {
  final int providerId;

  const ProviderProfileScreen({super.key, required this.providerId});

  @override
  State<ProviderProfileScreen> createState() => _ProviderProfileScreenState();
}

class _ProviderProfileScreenState extends State<ProviderProfileScreen> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  
  // State variables
  bool isOpen = false;
  String statusText = 'Carregando...';
  String timeInfo = '';
  String? distanceText;
  Position? _userPosition;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _checkLocation();
  }

  Future<void> _checkLocation() async {
    try {
      // Check permission first
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _userPosition = pos;
        });
        _calculateDistance();
      }
    } catch (_) {}
  }

  void _calculateDistance() {
    if (_userPosition != null && _profile != null && _profile!.containsKey('latitude') && _profile!['latitude'] != null) {
      try {
        final pLat = double.parse(_profile!['latitude'].toString());
        final pLon = double.parse(_profile!['longitude'].toString());
        
        final distMeters = Geolocator.distanceBetween(
          _userPosition!.latitude, 
          _userPosition!.longitude, 
          pLat, 
          pLon
        );
        
        setState(() {
          if (distMeters < 1000) {
            distanceText = '${distMeters.round()} m';
          } else {
            distanceText = '${(distMeters / 1000).toStringAsFixed(1)} km';
          }
        });
      } catch (_) {}
    }
  }

  Future<void> _loadProfile() async {
    try {
      final data = await _api.getProviderProfile(widget.providerId);
      if (mounted) {
        setState(() {
          _profile = data;
          _isLoading = false;
        });
        _updateStatus();
        _calculateDistance();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar perfil: $e')),
        );
      }
    }
  }

  void _updateStatus() {
    if (_profile == null) return;
    
    final schedules = _profile!['schedules'] as List? ?? [];
    final now = DateTime.now();
    final int currentMinutes = now.hour * 60 + now.minute;
    
    // Backend: 0=Sun, 1=Mon, ..., 6=Sat
    // Dart: 1=Mon, ..., 7=Sun
    final todayIndex = now.weekday == 7 ? 0 : now.weekday;
    final yesterdayIndex = (todayIndex - 1) < 0 ? 6 : (todayIndex - 1);

    final todaySchedule = schedules.firstWhere(
      (s) => s['day_of_week'] == todayIndex,
      orElse: () => null,
    );
    
    final yesterdaySchedule = schedules.firstWhere(
      (s) => s['day_of_week'] == yesterdayIndex,
      orElse: () => null,
    );

    bool newIsOpen = false;
    String newStatusText = 'Fechado';
    String newTimeInfo = '';

    // Helper: Parse "HH:mm" to minutes (0-1439)
    int? parseMinutes(String? t) {
      if (t == null) return null;
      try {
        final parts = t.split(':');
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      } catch (_) {
        return null;
      }
    }

    // 1. Check Yesterday's Spillover
    // If yesterday was 18:00 - 02:00, and it's 01:00 today.
    if (yesterdaySchedule != null && 
        (yesterdaySchedule['is_enabled'] == true || yesterdaySchedule['is_enabled'] == 1)) {
      final start = parseMinutes(yesterdaySchedule['start_time']);
      final end = parseMinutes(yesterdaySchedule['end_time']);

      if (start != null && end != null) {
        // Check if yesterday was an overnight shift
        if (end < start) {
           // We are in the "morning block" of yesterday's shift
           if (currentMinutes < end) {
             newIsOpen = true;
             newStatusText = 'Aberto agora';
             final diff = end - currentMinutes;
             if (diff < 60) {
               newTimeInfo = 'Fecha em $diff min';
             } else {
               newTimeInfo = 'Fecha às ${yesterdaySchedule['end_time'].substring(0, 5)}';
             }
           }
        }
      }
    }

    // 2. Check Today's Schedule
    // Only if not already open from yesterday's spillover
    if (!newIsOpen && todaySchedule != null && 
        (todaySchedule['is_enabled'] == true || todaySchedule['is_enabled'] == 1)) {
      final start = parseMinutes(todaySchedule['start_time']);
      final end = parseMinutes(todaySchedule['end_time']);

      if (start != null && end != null) {
        bool isOpenToday = false;

        // Special Case: 24h (Start == End, e.g. 00:00 to 00:00)
        // Assume if enabled and equal, it's 24 hours.
        if (start == end) {
           isOpenToday = true;
        } 
        // Overnight Shift (e.g. 18:00 - 02:00)
        else if (end < start) {
           if (currentMinutes >= start) {
             isOpenToday = true;
           }
        } 
        // Standard Shift (e.g. 08:00 - 18:00)
        else {
           if (currentMinutes >= start && currentMinutes < end) {
             isOpenToday = true;
           }
        }

        if (isOpenToday) {
          newIsOpen = true;
          newStatusText = 'Aberto agora';
          
          int minutesRemaining;
          if (start == end) {
            minutesRemaining = 9999; // Always open
            newTimeInfo = 'Aberto 24h';
          } else if (end < start) {
             // Closes tomorrow at 'end'
             // Time = (1440 - current) + end
             minutesRemaining = (1440 - currentMinutes) + end;
             final diffHours = (minutesRemaining / 60).floor();
             if (diffHours >= 12) {
               newTimeInfo = 'Fecha amanhã às ${todaySchedule['end_time'].substring(0, 5)}';
             } else {
               newTimeInfo = 'Fecha às ${todaySchedule['end_time'].substring(0, 5)}';
             }
          } else {
             minutesRemaining = end - currentMinutes;
             if (minutesRemaining < 60) {
               newTimeInfo = 'Fecha em $minutesRemaining min';
             } else {
               newTimeInfo = 'Fecha às ${todaySchedule['end_time'].substring(0, 5)}';
             }
          }

        } else if (currentMinutes < start) {
           // Opens later today
           final diff = start - currentMinutes;
           if (diff < 60) {
             newTimeInfo = 'Abre em $diff min';
           } else {
             newTimeInfo = 'Abre às ${todaySchedule['start_time'].substring(0, 5)}';
           }
        }
      }
    }

    // 3. Fallback Status Text
    if (!newIsOpen) {
       newStatusText = 'Fechado agora';
       if (newTimeInfo.isEmpty) {
         // Attempt to find next open day
         // Simple fallback: "Abre amanhã"
         newTimeInfo = 'Abre amanhã';
       }
    }

    setState(() {
      isOpen = newIsOpen;
      statusText = newStatusText;
      timeInfo = newTimeInfo;
    });
  }



  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final isMobile = (_profile?['address'] as String?)?.isEmpty ?? true;
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: _profile == null
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: isMobile ? 2 : 3, // 2 tabs for Mobile, 3 for Fixed
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    SliverAppBar(
                      expandedHeight: isMobile ? 180 : 280,
                      pinned: true,
                      backgroundColor: AppTheme.primaryYellow,
                      foregroundColor: Colors.black,
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.black),
                        onPressed: () => context.pop(),
                      ),
                      flexibleSpace: FlexibleSpaceBar(
                        background: Container(
                          color: AppTheme.primaryYellow,
                          padding: EdgeInsets.only(
                            top: isMobile ? 60 : 80, 
                            left: 24, 
                            right: 24, 
                            bottom: isMobile ? 10 : 20
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: isMobile ? 50 : 64,
                                    height: isMobile ? 50 : 64,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      image: _profile!['avatar_url'] != null
                                          ? DecorationImage(
                                              image: CachedNetworkImageProvider(
                                                ApiService.fixUrl(_profile!['avatar_url'].toString()),
                                              ),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                    ),
                                    child: _profile!['avatar_url'] == null
                                        ? Center(
                                            child: Icon(LucideIcons.user, size: isMobile ? 24 : 30, color: Colors.black54),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          _profile!['commercial_name'] ?? _profile!['full_name'] ?? 'Prestador',
                                          style: TextStyle(
                                            color: Colors.black87,
                                            fontSize: isMobile ? 18 : 22,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(LucideIcons.star, color: Colors.amber, size: 16),
                                            const SizedBox(width: 4),
                                            Text(
                                              (double.tryParse(_profile!['rating_avg']?.toString() ?? '0') ?? 0.0)
                                                  .toStringAsFixed(1),
                                              style: const TextStyle(
                                                color: Colors.black87,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              ' (${_profile!['rating_count'] ?? 0} avaliações)',
                                              style: const TextStyle(color: Colors.black54, fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: isMobile ? 12 : 20),
                              Row(
                                children: [
                                  _buildHeaderBadge(
                                    icon: LucideIcons.calendar,
                                    text: _getMemberSinceText(),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildHeaderBadge(
                                    icon: LucideIcons.briefcase,
                                    text: '${_profile!['services_completed'] ?? 0} serviços',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _SliverAppBarDelegate(
                        TabBar(
                          // controller: _tabController, // Removed as DefaultTabController manages it
                          isScrollable: true,
                          indicatorColor: AppTheme.primaryPurple,
                          labelColor: AppTheme.primaryPurple,
                          unselectedLabelColor: Colors.grey,
                          tabs: [
                            const Tab(text: 'Informações'),
                            if (!isMobile) const Tab(text: 'Serviços'),
                            const Tab(text: 'Avaliações'),
                          ],
                        ),
                      ),
                    ),
                  ];
                },
                body: TabBarView(
                  children: [
                    _buildInfoTab(),
                    if (!isMobile) _buildServicesTab(),
                    _buildReviewsTab(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInfoTab() {
    final schedules = _profile!['schedules'] as List? ?? [];
    final specialties = _profile!['specialties'] as List? ?? [];
    
    // Determine today schedule for header
    final now = DateTime.now();
    final weekday = now.weekday == 7 ? 0 : now.weekday; // 0=Sun
    final todaySchedule = schedules.firstWhere(
      (s) => s['day_of_week'] == weekday,
      orElse: () => null,
    );
    final todayText = (todaySchedule != null && (todaySchedule['is_enabled'] == true))
       ? '${todaySchedule['start_time'].substring(0, 5)} - ${todaySchedule['end_time'].substring(0, 5)}'
       : 'Fechado';

    final isMobile = (_profile?['address'] as String?)?.isEmpty ?? true;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Specialties Section (New)
          if (specialties.isNotEmpty) ...[
             Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   const Text(
                    'Profissões',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: specialties.map((s) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryYellow,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        s.toString(),
                        style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    )).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // Metric Cards (New)
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  LucideIcons.star,
                  Colors.amber,
                  (double.tryParse(_profile!['rating_avg']?.toString() ?? '0') ?? 0.0).toStringAsFixed(1),
                  '${_profile!['rating_count'] ?? 0} avaliações',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  LucideIcons.briefcase,
                  Colors.blue,
                  '${_profile!['services_completed'] ?? 0}',
                  'Serviços feitos',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // Sections for Fixed Providers ONLY
          if (!isMobile) ...[
            // Open/Closed Status
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isOpen ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isOpen ? Colors.green.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    isOpen ? Icons.check_circle : Icons.cancel,
                    color: isOpen ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          statusText,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isOpen ? Colors.green : Colors.red,
                          ),
                        ),
                        if (timeInfo.isNotEmpty)
                          Text(
                            timeInfo,
                            style: TextStyle(color: isOpen ? Colors.green[700] : Colors.red[700], fontSize: 12),
                          ),
                        if (distanceText != null) ...[
                           const SizedBox(height: 4),
                           Text(
                             'Aprox. $distanceText de você',
                             style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.bold),
                           )
                        ]
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          
          const Text(
            'Sobre',
            style: TextStyle(
                color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _profile!['bio'] ?? 'Nenhuma descrição fornecida.',
            style: TextStyle(color: Colors.grey[700], height: 1.5),
          ),
          const SizedBox(height: 24),

          // Location and Hours for Fixed Providers ONLY
          if (!isMobile) ...[
            const Text(
              'Localização',
              style: TextStyle(
                  color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            InkWell(
               onTap: () {
                 final addr = _profile!['address'];
                 if (addr != null && addr != 'Endereço não informado') {
                   final url = 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(addr)}';
                   launchUrl(Uri.parse(url));
                 }
               },
               child: Row(
                children: [
                  Icon(LucideIcons.mapPin, color: AppTheme.primaryPurple, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _profile!['address'] ?? 'Endereço não disponível',
                      style: TextStyle(color: Colors.grey[800], decoration: TextDecoration.underline),
                    ),
                  ),
                  const Icon(Icons.open_in_new, size: 14, color: Colors.grey),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Static Hours Section (Always Visible)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Row(
                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                     children: [
                       const Text(
                        'Horário de Funcionamento',
                        style: TextStyle(
                            color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Hoje: $todayText',
                         style: TextStyle(
                            color: isOpen ? Colors.green : Colors.grey, 
                            fontWeight: FontWeight.bold,
                            fontSize: 13
                         ),
                      ),
                     ],
                   ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Column(
                    children: schedules.isNotEmpty 
                    ? schedules.map((s) {
                      final days = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];
                      final dayIndex = (s['day_of_week'] as int);
                      final day = (dayIndex >= 0 && dayIndex < days.length) ? days[dayIndex] : 'Dia';
                      
                      final isToday = dayIndex == weekday;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              day, 
                              style: TextStyle(
                                color: isToday ? Colors.black87 : Colors.grey[600],
                                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13
                              )
                            ),
                            Text(
                              (s['is_enabled'] == true) 
                                ? '${s['start_time'].substring(0, 5)} - ${s['end_time'].substring(0, 5)}'
                                : 'Fechado',
                              style: TextStyle(
                                color: isToday ? Colors.black87 : Colors.grey[600],
                                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList()
                    : [const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('Nenhum horário cadastrado', style: TextStyle(color: Colors.grey)),
                      )],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildServicesTab() {
    final services = _profile!['services'] as List? ?? [];

    if (services.isEmpty) {
      return Center(
        child: Text(
          'Nenhum serviço customizado disponível.\n(DEBUG: List is empty)',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: services.map((service) {
          final price = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
              .format(double.tryParse(service['price'].toString()) ?? 0);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service['name']?.toString() ?? 'Serviço sem nome',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${service['duration']?.toString() ?? '--'} min • $price',
                          style: TextStyle(color: Colors.grey[700], fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _handleBooking(service),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryYellow,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      minimumSize: const Size(0, 36), // Compact button
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Agendar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildReviewsTab() {
    final reviews = _profile!['reviews'] as List? ?? [];

    if (reviews.isEmpty) {
      return const Center(
        child: Text('Nenhuma avaliação ainda.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: reviews.length,
      itemBuilder: (context, index) {
        final review = reviews[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundImage: review['reviewer_avatar'] != null
                        ? NetworkImage(review['reviewer_avatar'])
                        : null,
                    radius: 18,
                    backgroundColor: Colors.grey[200],
                    child: review['reviewer_avatar'] == null
                        ? const Icon(LucideIcons.user, size: 18, color: Colors.grey)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          review['reviewer_name'] ?? 'Usuário',
                          style: const TextStyle(
                              color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Row(
                          children: List.generate(
                            5,
                            (i) => Icon(
                              LucideIcons.star,
                              size: 12,
                              color: i < (review['rating'] ?? 0)
                                  ? Colors.amber
                                  : Colors.grey[300],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    DateFormat('dd/MM/yyyy')
                        .format(DateTime.parse(review['created_at'])),
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 48),
                child: Text(
                  review['comment'] ?? '',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleBooking(Map<String, dynamic> service) {
    context.push('/create-service', extra: {
      'providerId': widget.providerId,
      'service': service,
      'provider': _profile,
    });
  }


  Widget _buildMetricCard(
    IconData icon,
    Color color,
    String value,
    String label,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildHeaderBadge({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.3),  // Changed to white transparent for Yellow background
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.black87),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _getMemberSinceText() {
    final created = _profile!['member_since'];
    if (created == null) return 'Membro novo';
    try {
      final dt = DateTime.parse(created.toString());
      final now = DateTime.now();
      final diff = now.difference(dt).inDays;
      
      if (diff < 30) return 'Novo membro';
      if (diff < 365) return '${(diff / 30).floor()} meses';
      return '${(diff / 365).floor()} anos';
    } catch (_) {
      return 'Membro';
    }
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);

  final TabBar _tabBar;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
