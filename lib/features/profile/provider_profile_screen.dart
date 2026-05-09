import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/api_service.dart';
import '../../core/theme/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

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

  // Mapbox controller
  mapbox.MapboxMap? _mapboxMap;

  bool _looksLikeRawCoordinateAddress(String? value) {
    final text = (value ?? '').trim().toLowerCase();
    if (text.isEmpty) return true;
    return text.startsWith('loc.:') ||
        RegExp(r'^-?\d+\.\d+\s*,\s*-?\d+\.\d+$').hasMatch(text);
  }

  String _formatReadableAddress(Map<String, dynamic> data) {
    final displayName = (data['display_name'] ?? '').toString().trim();
    if (displayName.isNotEmpty) return displayName;

    final parts = <String>[
      if ((data['street'] ?? '').toString().trim().isNotEmpty)
        (data['street']).toString().trim(),
      if ((data['house_number'] ?? '').toString().trim().isNotEmpty)
        (data['house_number']).toString().trim(),
      if ((data['neighborhood'] ??
              data['suburb'] ??
              data['neighbourhood'] ??
              '')
          .toString()
          .trim()
          .isNotEmpty)
        (data['neighborhood'] ?? data['suburb'] ?? data['neighbourhood'])
            .toString()
            .trim(),
      if ((data['city'] ?? '').toString().trim().isNotEmpty)
        (data['city']).toString().trim(),
      if ((data['state_code'] ?? data['state'] ?? '')
          .toString()
          .trim()
          .isNotEmpty)
        (data['state_code'] ?? data['state']).toString().trim(),
    ];

    return parts.join(', ').trim();
  }

  Future<void> _resolveProfileAddressIfNeeded() async {
    final profile = _profile;
    if (profile == null) return;

    final currentAddress = (profile['address'] ?? '').toString().trim();
    if (!_looksLikeRawCoordinateAddress(currentAddress)) return;

    final lat = double.tryParse('${profile['latitude'] ?? ''}');
    final lon = double.tryParse('${profile['longitude'] ?? ''}');
    if (lat == null || lon == null) return;

    try {
      final reverse = await _api.reverseGeocode(lat, lon);
      final resolvedAddress = _formatReadableAddress(reverse);
      if (!mounted || resolvedAddress.isEmpty) return;
      setState(() {
        _profile = {...?_profile, 'address': resolvedAddress};
      });
    } catch (_) {}
  }

  Map<String, dynamic>? _findScheduleByDay(List schedules, int dayOfWeek) {
    for (final item in schedules) {
      if (item is Map && item['day_of_week'] == dayOfWeek) {
        return Map<String, dynamic>.from(item);
      }
    }
    return null;
  }

  double _contentBottomInset(BuildContext context) {
    final media = MediaQuery.of(context);
    return media.viewPadding.bottom + 132;
  }

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
    if (_userPosition != null && _profile != null) {
      try {
        final pLat = double.tryParse(_profile?['latitude']?.toString() ?? '');
        final pLon = double.tryParse(_profile?['longitude']?.toString() ?? '');

        if (pLat == null || pLon == null) return;

        final distMeters = Geolocator.distanceBetween(
          _userPosition!.latitude,
          _userPosition!.longitude,
          pLat,
          pLon,
        );

        setState(() {
          if (distMeters < 1000) {
            distanceText = '${distMeters.round()} m';
          } else {
            distanceText = '${(distMeters / 1000).toStringAsFixed(1)} km';
          }
          // Simple estimate: 2 mins per km
          final mins = (distMeters / 1000) * 2;
          if (mins < 1) {
            timeInfo = 'Menos de 1 min';
          } else {
            timeInfo = '${mins.round()} min de viagem';
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
        unawaited(_resolveProfileAddressIfNeeded());
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao carregar perfil: $e')));
      }
    }
  }

  void _onMapCreated(mapbox.MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    if (_profile != null &&
        _profile?['latitude'] != null &&
        _profile?['longitude'] != null) {
      try {
        final lat = double.tryParse(_profile?['latitude']?.toString() ?? '');
        final lon = double.tryParse(_profile?['longitude']?.toString() ?? '');

        if (lat == null || lon == null) return;

        _mapboxMap?.setCamera(
          mapbox.CameraOptions(
            center: mapbox.Point(coordinates: mapbox.Position(lon, lat)),
            zoom: 15.0,
          ),
        );
      } catch (_) {}
    }
  }

  void _openRoute() {
    if (_profile == null ||
        _profile?['latitude'] == null ||
        _profile?['longitude'] == null) {
      return;
    }
    final lat = _profile?['latitude'];
    final lon = _profile?['longitude'];
    if (lat == null || lon == null) return;

    final url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _updateStatus() {
    if (_profile == null) return;

    final schedules = _profile?['schedules'] as List? ?? [];
    final now = DateTime.now();
    final int currentMinutes = now.hour * 60 + now.minute;

    // Backend: 0=Sun, 1=Mon, ..., 6=Sat
    // Dart: 1=Mon, ..., 7=Sun
    final todayIndex = now.weekday == 7 ? 0 : now.weekday;
    final yesterdayIndex = (todayIndex - 1) < 0 ? 6 : (todayIndex - 1);

    final todaySchedule = _findScheduleByDay(schedules, todayIndex);
    final yesterdaySchedule = _findScheduleByDay(schedules, yesterdayIndex);

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
        (yesterdaySchedule['is_enabled'] == true ||
            yesterdaySchedule['is_enabled'] == 1)) {
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
              newTimeInfo =
                  'Fecha às ${yesterdaySchedule['end_time'].substring(0, 5)}';
            }
          }
        }
      }
    }

    // 2. Check Today's Schedule
    // Only if not already open from yesterday's spillover
    if (!newIsOpen &&
        todaySchedule != null &&
        (todaySchedule['is_enabled'] == true ||
            todaySchedule['is_enabled'] == 1)) {
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
              newTimeInfo =
                  'Fecha amanhã às ${todaySchedule['end_time'].substring(0, 5)}';
            } else {
              newTimeInfo =
                  'Fecha às ${todaySchedule['end_time'].substring(0, 5)}';
            }
          } else {
            minutesRemaining = end - currentMinutes;
            if (minutesRemaining < 60) {
              newTimeInfo = 'Fecha em $minutesRemaining min';
            } else {
              newTimeInfo =
                  'Fecha às ${todaySchedule['end_time'].substring(0, 5)}';
            }
          }
        } else if (currentMinutes < start) {
          // Opens later today
          final diff = start - currentMinutes;
          if (diff < 60) {
            newTimeInfo = 'Abre em $diff min';
          } else {
            newTimeInfo =
                'Abre às ${todaySchedule['start_time'].substring(0, 5)}';
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final isMobile = (_profile?['address'] as String?)?.isEmpty ?? true;
    // Note: We always show 3 tabs now (Info, Services, Reviews) to satisfy user requirements.

    return Scaffold(
      backgroundColor: Colors.white,
      body: _profile == null
          ? const Center(child: CircularProgressIndicator())
          : DefaultTabController(
              length: 3,
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    SliverAppBar(
                      expandedHeight: 180,
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
                            top: isMobile ? 30 : 40,
                            left: 24,
                            right: 24,
                            bottom: 10,
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
                                                ApiService.fixUrl(
                                                  _profile!['avatar_url']
                                                      .toString(),
                                                ),
                                              ),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                    ),
                                    child: _profile?['avatar_url'] == null
                                        ? Center(
                                            child: Icon(
                                              LucideIcons.user,
                                              size: isMobile ? 24 : 30,
                                              color: Colors.black54,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          _profile?['commercial_name'] ??
                                              _profile?['full_name'] ??
                                              'Prestador',
                                          style: const TextStyle(
                                            color: Colors.black87,
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(
                                              LucideIcons.star,
                                              color: Colors.amber,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              (double.tryParse(
                                                        _profile?['rating_avg']
                                                                ?.toString() ??
                                                            '0',
                                                      ) ??
                                                      0.0)
                                                  .toStringAsFixed(1),
                                              style: const TextStyle(
                                                color: Colors.black87,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              ' (${_profile?['rating_count'] ?? 0} avaliações)',
                                              style: const TextStyle(
                                                color: Colors.black54,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              // Badges removed as per user request
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
                            const Tab(text: 'Serviços'),
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
                    _buildServicesTab(),
                    _buildReviewsTab(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInfoTab() {
    final bottomInset = _contentBottomInset(context);
    final schedules = _profile?['schedules'] as List? ?? [];

    // Determine today schedule for header
    final now = DateTime.now();
    final weekday = now.weekday == 7 ? 0 : now.weekday; // 0=Sun
    final todaySchedule = _findScheduleByDay(schedules, weekday);
    final todayText =
        (todaySchedule != null && (todaySchedule['is_enabled'] == true))
        ? '${todaySchedule['start_time'].substring(0, 5)} - ${todaySchedule['end_time'].substring(0, 5)}'
        : 'Fechado';

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Metric Cards removed as per user request
          const SizedBox(height: 8),

          // Open/Closed Status
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isOpen
                  ? Colors.green.withOpacity(0.1)
                  : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isOpen
                    ? Colors.green.withOpacity(0.3)
                    : Colors.red.withOpacity(0.3),
              ),
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
                          style: TextStyle(
                            color: isOpen ? Colors.green[700] : Colors.red[700],
                            fontSize: 12,
                          ),
                        ),
                      if (distanceText != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Aprox. $distanceText • $timeInfo',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // NEW: Small Map Section
          if (_profile!['latitude'] != null &&
              _profile!['longitude'] != null) ...[
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  mapbox.MapWidget(
                    key: const ValueKey('provider_mini_map'),
                    onMapCreated: _onMapCreated,
                  ),
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: ElevatedButton.icon(
                      onPressed: _openRoute,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      icon: const Icon(LucideIcons.navigation, size: 16),
                      label: const Text(
                        'Ver Rota',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),

          const Text(
            'Sobre',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _profile?['bio'] ?? 'Nenhuma descrição fornecida.',
            style: TextStyle(color: Colors.grey[700], height: 1.5),
          ),
          const SizedBox(height: 24),
          const Text(
            'Localização',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              final addr = _profile!['address'];
              if (addr != null && addr != 'Endereço não informado') {
                final url =
                    'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(addr)}';
                launchUrl(Uri.parse(url));
              }
            },
            child: Row(
              children: [
                Icon(
                  LucideIcons.mapPin,
                  color: AppTheme.primaryPurple,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _profile?['address'] ?? 'Endereço não disponível',
                    style: TextStyle(
                      color: Colors.grey[800],
                      decoration: TextDecoration.underline,
                    ),
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
                  color: Colors.black.withOpacity(0.05),
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
                        color: Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isOpen
                            ? Colors.green.withOpacity(0.1)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isOpen ? 'ABERTO AGORA' : 'FECHADO',
                        style: TextStyle(
                          color: isOpen ? Colors.green : Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Hoje: $todayText',
                  style: TextStyle(
                    color: isOpen ? Colors.green[700] : Colors.grey[600],
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Column(
                  children: schedules.isNotEmpty
                      ? schedules.map((s) {
                          final days = [
                            'Domingo',
                            'Segunda',
                            'Terça',
                            'Quarta',
                            'Quinta',
                            'Sexta',
                            'Sábado',
                          ];
                          final dayIndex = (s['day_of_week'] as int);
                          final day = (dayIndex >= 0 && dayIndex < days.length)
                              ? days[dayIndex]
                              : 'Dia';

                          final isToday = dayIndex == weekday;

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  day,
                                  style: TextStyle(
                                    color: isToday
                                        ? Colors.black87
                                        : Colors.grey[600],
                                    fontWeight: isToday
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  (s['is_enabled'] == true)
                                      ? '${s['start_time'].substring(0, 5)} - ${s['end_time'].substring(0, 5)}'
                                      : 'Fechado',
                                  style: TextStyle(
                                    color: isToday
                                        ? Colors.black87
                                        : Colors.grey[600],
                                    fontWeight: isToday
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList()
                      : [
                          const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text(
                              'Nenhum horário cadastrado',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesTab() {
    final bottomInset = _contentBottomInset(context);
    final services = (_profile?['services'] as List? ?? [])
        .map((s) => Map<String, dynamic>.from(s as Map))
        .toList();

    if (services.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum serviço customizado disponível.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset),
      child: Column(
        children: services.map((service) {
          final duration =
              int.tryParse(
                (service['duration'] ??
                        service['duration_minutes'] ??
                        service['estimated_duration'] ??
                        '30')
                    .toString(),
              ) ??
              30;
          final price = NumberFormat.currency(
            locale: 'pt_BR',
            symbol: 'R\$',
          ).format(double.tryParse(service['price'].toString()) ?? 0);

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
                          '$duration min • $price',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _handleBooking(service),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: Colors.black.withOpacity(0.3),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 0,
                      ),
                      minimumSize: const Size(0, 36), // Compact button
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Agendar',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
    final bottomInset = _contentBottomInset(context);
    final reviews = _profile!['reviews'] as List? ?? [];

    if (reviews.isEmpty) {
      return const Center(
        child: Text(
          'Nenhuma avaliação ainda.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset),
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
                        ? const Icon(
                            LucideIcons.user,
                            size: 18,
                            color: Colors.grey,
                          )
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
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
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
                    DateFormat(
                      'dd/MM/yyyy',
                    ).format(DateTime.parse(review['created_at'])),
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 48),
                child: Text(
                  review['comment'] ?? '',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleBooking(Map<String, dynamic> service) async {
    final profile = Map<String, dynamic>.from(_profile ?? const {});
    final providerPayload = <String, dynamic>{
      'id': widget.providerId,
      'commercial_name': profile['name'] ?? profile['commercial_name'],
      'full_name': profile['name'] ?? profile['full_name'],
      'address': profile['address'],
      'latitude': profile['latitude'],
      'longitude': profile['longitude'],
      'avatar_url': profile['avatar_url'] ?? profile['photo'],
      'rating': profile['rating'],
      'reviews_count': profile['review_count'] ?? profile['rating_count'],
      'service_type': 'at_provider',
    };

    if (!mounted) return;
    context.push(
      '/beauty-booking',
      extra: {
        'q': service['name']?.toString() ?? 'Serviço de beleza',
        'service': service,
        'profession': service['category']?.toString(),
        'price': service['price'],
        'pre_selected_provider': providerPayload,
      },
    );
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
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: Colors.white, child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

class _BookingSlotPicker extends StatefulWidget {
  final int providerId;
  final Map<String, dynamic> service;
  final ApiService api;

  const _BookingSlotPicker({
    required this.providerId,
    required this.service,
    required this.api,
  });

  @override
  State<_BookingSlotPicker> createState() => _BookingSlotPickerState();
}

class _BookingSlotPickerState extends State<_BookingSlotPicker> {
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _slots = [];
  bool _loadingSlots = false;

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    setState(() => _loadingSlots = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final duration =
          int.tryParse(widget.service['duration']?.toString() ?? '') ?? 30;
      final slots = await widget.api.getProviderAvailableSlots(
        widget.providerId,
        date: dateStr,
        requiredDurationMinutes: duration,
      );
      if (mounted) {
        setState(() {
          _slots = slots.where((s) => s['is_selectable'] == true).toList();
          _loadingSlots = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Selecione o Horário',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Date Selector
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedDate = _selectedDate.subtract(
                      const Duration(days: 1),
                    );
                    _loadSlots();
                  });
                },
                icon: const Icon(LucideIcons.chevronLeft),
              ),
              Text(
                DateFormat('dd/MM (EEEE)', 'pt_BR').format(_selectedDate),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedDate = _selectedDate.add(const Duration(days: 1));
                    _loadSlots();
                  });
                },
                icon: const Icon(LucideIcons.chevronRight),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loadingSlots
                ? const Center(child: CircularProgressIndicator())
                : _slots.isEmpty
                ? const Center(
                    child: Text('Nenhum horário disponível para este dia.'),
                  )
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 2.5,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                    itemCount: _slots.length,
                    itemBuilder: (ctx, idx) {
                      final slot = _slots[idx];
                      final startStr = slot['start_time'].toString();
                      final start = DateTime.parse(startStr).toLocal();
                      return InkWell(
                        onTap: () => Navigator.pop(context, slot),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.primaryPurple),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            DateFormat('HH:mm').format(start),
                            style: TextStyle(
                              color: AppTheme.primaryPurple,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
