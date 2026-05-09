// Fluxo fixo canônico usado pela rota `/beauty-booking`.
// Esta é a implementação real do agendamento em estabelecimento
// (`at_provider`). O acompanhamento do cliente continua em
// `scheduled_service_screen.dart`.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import 'models/fixed_booking_pending_pix_state.dart';
import 'models/fixed_booking_provider_search_state.dart';
import 'models/fixed_booking_schedule_state.dart';
import 'widgets/fixed_booking_description_step.dart';
import 'widgets/fixed_booking_expanded_schedule_card.dart';
import 'widgets/fixed_booking_provider_selection_step.dart';
import 'widgets/fixed_booking_schedule_step.dart';
import '../home/widgets/home_search_bar.dart';
import 'fixed_booking_review_screen.dart';
import '../payment/models/pending_fixed_booking_policy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domains/scheduling/scheduling.dart';
import '../../integrations/supabase/scheduling/supabase_scheduling_repository.dart';
import '../../services/api_service.dart';

class ServiceRequestScreenFixed extends StatefulWidget {
  final int? initialProviderId;
  final Map<String, dynamic>? initialService;
  final Map<String, dynamic>? initialProvider;
  final Map<String, dynamic>? initialData; // DADOS VINDOS DA IA (MÓVEL -> FIXO)

  const ServiceRequestScreenFixed({
    super.key,
    this.initialProviderId,
    this.initialService,
    this.initialProvider,
    this.initialData,
    this.onBack,
  });

  final VoidCallback? onBack;

  @override
  State<ServiceRequestScreenFixed> createState() =>
      _ServiceRequestScreenFixedState();
}

class _ServiceRequestScreenFixedState extends State<ServiceRequestScreenFixed>
    with WidgetsBindingObserver {
  static const int _beautyRankingHorizonDays = 14;
  static const int _providerSearchChunkSize = 1;
  static const String _legacyPendingPixPrefsKey =
      'fixed_booking_pending_pix_v1';
  static const String _pendingPixPrefsKey = 'fixed_booking_pending_pix_v2';
  int _currentStep = 1;
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final _api = ApiService();
  late final SchedulingRepository _scheduling = SupabaseSchedulingRepository();
  late final GetProviderNextAvailableSlotUseCase _getNextSlot =
      GetProviderNextAvailableSlotUseCase(_scheduling);
  late final GetProviderAvailableSlotsUseCase _getAvailableSlots =
      GetProviderAvailableSlotsUseCase(_scheduling);
  late final CreateFixedBookingIntentUseCase _createIntent =
      CreateFixedBookingIntentUseCase(_scheduling);
  late final CancelFixedBookingIntentUseCase _cancelIntent =
      CancelFixedBookingIntentUseCase(_scheduling);
  double? _latitude;
  double? _longitude;
  String? _address;
  final double _priceEstimated = 150.00;
  final List<String> _imageKeys = [];
  String? _videoKey;

  int? _aiCategoryId;
  String? _aiProfessionName;
  int? _aiTaskId;
  String? _aiTaskName;
  double? _aiTaskPrice;
  String? _aiServiceType;
  final ScrollController _descScrollController = ScrollController();
  final GlobalKey _scheduleKey = GlobalKey();
  int? _selectedProviderId;
  Timer? _aiDebounce;
  Position? _userPosition;
  final TextEditingController _professionSearchController =
      TextEditingController();

  final Set<dynamic> _fetchedAddresses = {};
  final GlobalKey _pendingPixSectionKey = GlobalKey();

  String? _selectedProfession;
  Map<String, dynamic>? _selectedService;
  final FixedBookingScheduleState _scheduleState = FixedBookingScheduleState();
  bool _changingPendingSchedule = false;
  final FixedBookingProviderSearchState _providerSearchState =
      FixedBookingProviderSearchState();
  final Map<int, GlobalKey> _providerCardKeys = {};
  final Set<int> _loadingProviderAvailability = <int>{};
  final Set<int> _resolvedProviderAvailability = <int>{};
  static const int _providersRevealBatchSize = 1;
  static const Duration _providersRevealCadence = Duration(milliseconds: 110);
  bool _preparingInlinePix = false;
  final FixedBookingPendingPixState _pendingPixState =
      FixedBookingPendingPixState();
  Timer? _pixStatusPollTimer;
  Timer? _providersRevealTimer;
  bool _isAppInForeground = true;

  void _dismissKeyboard() {
    final currentFocus = FocusManager.instance.primaryFocus;
    if (currentFocus != null) {
      currentFocus.unfocus();
    }
  }

  String _effectiveServiceQuery() {
    final candidates = <String?>[
      _aiTaskName,
      _selectedService?['name']?.toString(),
      _selectedService?['title']?.toString(),
      _selectedProfession,
      _aiProfessionName,
      widget.initialData?['q']?.toString(),
      _descriptionController.text,
    ];
    for (final candidate in candidates) {
      final text = candidate?.trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return 'Serviço de beleza';
  }

  Map<String, dynamic> _normalizeProviderRow(Map<String, dynamic> raw) {
    final providerData = raw['providers'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(raw['providers'] as Map<String, dynamic>)
        : raw['providers'] is Map
        ? Map<String, dynamic>.from(raw['providers'] as Map)
        : <String, dynamic>{};
    final normalized = <String, dynamic>{...providerData};
    normalized['id'] = int.tryParse(
      '${raw['id'] ?? providerData['user_id'] ?? ''}',
    );
    normalized['user_id'] = normalized['id'];
    normalized['full_name'] =
        raw['full_name'] ??
        providerData['full_name'] ??
        providerData['commercial_name'];
    normalized['commercial_name'] =
        providerData['commercial_name'] ?? raw['full_name'] ?? 'Salão parceiro';
    normalized['distance_km'] =
        raw['distance_km'] ?? providerData['distance_km'];
    normalized['rating'] = providerData['rating'] ?? raw['rating'];
    normalized['reviews_count'] =
        providerData['reviews_count'] ?? raw['reviews_count'];
    normalized['avatar_url'] = raw['avatar_url'] ?? providerData['avatar_url'];
    normalized['service_type'] =
        providerData['service_type'] ?? raw['service_type'] ?? 'at_provider';
    normalized['latitude'] = providerData['latitude'] ?? raw['latitude'];
    normalized['longitude'] = providerData['longitude'] ?? raw['longitude'];
    normalized['address'] = providerData['address'] ?? raw['address'];
    return normalized;
  }

  DateTime? _slotStartLocal(Map<String, dynamic> slot) {
    final raw = slot['start_time']?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  DateTime get _minimumClientBookingTime =>
      DateTime.now().add(const Duration());

  int get _requiredServiceDurationMinutes {
    final candidates = <dynamic>[
      _selectedService?['duration_minutes'],
      _selectedService?['duration'],
      _selectedService?['estimated_duration'],
      widget.initialData?['duration_minutes'],
      widget.initialData?['duration'],
      widget.initialService?['duration_minutes'],
      widget.initialService?['duration'],
    ];

    for (final candidate in candidates) {
      final parsed = candidate is num
          ? candidate.toInt()
          : int.tryParse('${candidate ?? ''}');
      if (parsed != null && parsed > 0) {
        return parsed.clamp(15, 480).toInt();
      }
    }

    return 60;
  }

  String _formatNextAvailableLabel(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final targetDay = DateTime(value.year, value.month, value.day);
    final timeLabel = DateFormat('HH:mm', 'pt_BR').format(value);

    if (targetDay == today) {
      return 'Hoje às $timeLabel';
    }
    if (targetDay == tomorrow) {
      return 'Amanhã às $timeLabel';
    }
    return DateFormat("dd/MM 'às' HH:mm", 'pt_BR').format(value);
  }

  int get _visibleProviderCapacityLeft {
    final remaining =
        _providersRevealBatchSize - _providerSearchState.providers.length;
    return remaining > 0 ? remaining : 0;
  }

  void _appendProviderChunk(
    List<Map<String, dynamic>> availableChunk,
    List<Map<String, dynamic>> unavailableChunk,
  ) {
    var remainingVisibleCapacity = _visibleProviderCapacityLeft;

    if (remainingVisibleCapacity > 0 && availableChunk.isNotEmpty) {
      final visibleAvailable = availableChunk
          .take(remainingVisibleCapacity)
          .toList();
      _providerSearchState.providers.addAll(visibleAvailable);
      _providerSearchState.pendingProviders.addAll(
        availableChunk.skip(visibleAvailable.length),
      );
      remainingVisibleCapacity -= visibleAvailable.length;
    } else if (availableChunk.isNotEmpty) {
      _providerSearchState.pendingProviders.addAll(availableChunk);
    }

    if (remainingVisibleCapacity > 0 && unavailableChunk.isNotEmpty) {
      final visibleUnavailable = unavailableChunk
          .take(remainingVisibleCapacity)
          .toList();
      _providerSearchState.providers.addAll(visibleUnavailable);
      _providerSearchState.unavailableProviders.addAll(visibleUnavailable);
      _providerSearchState.pendingUnavailableProviders.addAll(
        unavailableChunk.skip(visibleUnavailable.length),
      );
    } else if (unavailableChunk.isNotEmpty) {
      _providerSearchState.pendingUnavailableProviders.addAll(unavailableChunk);
    }
  }

  String _serviceLabelForProvider(Map<String, dynamic> provider) {
    final matchedService = provider['matched_service'] is Map
        ? Map<String, dynamic>.from(provider['matched_service'] as Map)
        : <String, dynamic>{};
    final resolvedService = provider['resolved_service'] is Map
        ? Map<String, dynamic>.from(provider['resolved_service'] as Map)
        : <String, dynamic>{};

    final candidates = <String?>[
      _aiTaskName,
      _selectedService?['name']?.toString(),
      _selectedService?['title']?.toString(),
      matchedService['name']?.toString(),
      matchedService['task_name']?.toString(),
      resolvedService['task_name']?.toString(),
      resolvedService['name']?.toString(),
      _selectedProfession,
      _aiProfessionName,
    ];

    for (final candidate in candidates) {
      final text = candidate?.trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return 'Serviço selecionado';
  }

  Map<String, dynamic>? _firstSelectableSlot(List<Map<String, dynamic>> slots) {
    for (final slot in slots) {
      final status = (slot['status'] ?? '').toString().toLowerCase().trim();
      final isSelectable = slot['is_selectable'] == true;
      final slotStart = _slotStartLocal(slot);
      final isEligible =
          slotStart != null && !slotStart.isBefore(_minimumClientBookingTime);
      if (status == 'free' && isSelectable && isEligible) {
        return slot;
      }
    }
    return null;
  }

  Future<void> _ensureProviderNextAvailability(
    Map<String, dynamic> provider,
  ) async {
    final providerId = int.tryParse('${provider['id'] ?? ''}');
    if (providerId == null || providerId <= 0) return;

    if (_loadingProviderAvailability.contains(providerId) ||
        _resolvedProviderAvailability.contains(providerId)) {
      return;
    }

    _loadingProviderAvailability.add(providerId);
    if (mounted) setState(() {});

    try {
      final nextSlot = await _getNextSlot(
        providerId,
        horizonDays: _beautyRankingHorizonDays,
        requiredDurationMinutes: _requiredServiceDurationMinutes,
      );
      if (!mounted) return;

      if (nextSlot != null) {
        final nextStart = nextSlot['start_time']?.toString();
        if (nextStart != null && nextStart.trim().isNotEmpty) {
          setState(() {
            for (final collection in [
              _providerSearchState.providers,
              _providerSearchState.pendingProviders,
              _providerSearchState.unavailableProviders,
              _providerSearchState.pendingUnavailableProviders,
            ]) {
              for (final row in collection) {
                if ('${row['id']}' == '$providerId') {
                  final currentNextAt = DateTime.tryParse(
                    '${row['next_available_at'] ?? ''}',
                  )?.toLocal();
                  final refreshedNextAt = DateTime.tryParse(
                    nextStart,
                  )?.toLocal();
                  final shouldReplace =
                      refreshedNextAt != null &&
                      (currentNextAt == null ||
                          refreshedNextAt.isBefore(currentNextAt) ||
                          currentNextAt != refreshedNextAt);
                  if (!shouldReplace) {
                    row.remove('unavailability_reason');
                    continue;
                  }
                  row['next_available_slot'] = nextSlot;
                  row['next_available_at'] = nextStart;
                  row.remove('unavailability_reason');
                }
              }
            }
            _sortVisibleProviders();
          });
        }
      }
    } catch (e) {
      debugPrint(
        'Erro ao hidratar próximo horário do prestador $providerId: $e',
      );
    } finally {
      _loadingProviderAvailability.remove(providerId);
      _resolvedProviderAvailability.add(providerId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _fetchProviders(
    String profession, {
    bool preservePendingPixContext = false,
  }) async {
    final requestId = ++_providerSearchState.providersRequestId;
    var keyboardDismissedForRequest = false;
    final preservedExpandedProviderId = _providerSearchState.expandedProviderId;
    final preservedSelectedProviderId = _selectedProviderId;
    final preservedSelectedTimeSlot = _scheduleState.selectedTimeSlot;
    setState(() {
      _providerSearchState.resetForNewSearch(
        preserveExpandedProvider: preservePendingPixContext,
        preservedExpandedProviderId: preservedExpandedProviderId,
      );
      _loadingProviderAvailability.clear();
      _resolvedProviderAvailability.clear();
      if (preservePendingPixContext) {
        _selectedProviderId = preservedSelectedProviderId;
      }
      _scheduleState.realSlots = [];
      _scheduleState.selectedTimeSlot = preservePendingPixContext
          ? preservedSelectedTimeSlot
          : null;
      if (!preservePendingPixContext) {
        _pendingPixState.pendingProviderAutoScrollArmed = false;
      }
    });
    try {
      final effectiveTerm = profession.trim().isNotEmpty
          ? profession.trim()
          : _effectiveServiceQuery();

      await for (final event
          in _api
              .searchFixedProvidersForServiceProgressive(
                query: effectiveTerm,
                lat: _latitude,
                lon: _longitude,
                horizonDays: _beautyRankingHorizonDays,
                chunkSize: _providerSearchChunkSize,
              )
              .timeout(const Duration(seconds: 20))) {
        if (!mounted || requestId != _providerSearchState.providersRequestId)
          return;
        final resolvedService = event['service'] is Map
            ? Map<String, dynamic>.from(event['service'] as Map)
            : <String, dynamic>{};
        setState(() {
          final message = (event['message'] ?? '').toString().trim();
          final detail = (event['detail'] ?? '').toString().trim();
          if (message.isNotEmpty) {
            _providerSearchState.providerSearchMessage = message;
          }
          if (detail.isNotEmpty) {
            _providerSearchState.providerSearchDetail = detail;
          }

          _aiProfessionName =
              (resolvedService['profissao'] ?? _aiProfessionName)?.toString();
          _aiServiceType = (resolvedService['service_type'] ?? _aiServiceType)
              ?.toString();
          _aiCategoryId = int.tryParse(
            '${resolvedService['category_id'] ?? _aiCategoryId ?? ''}',
          );
          _aiTaskId = int.tryParse(
            '${resolvedService['task_id'] ?? _aiTaskId ?? ''}',
          );
          _aiTaskName = (resolvedService['task_name'] ?? _aiTaskName)
              ?.toString();
          final resolvedPrice = double.tryParse(
            '${resolvedService['price'] ?? ''}',
          );
          if (resolvedPrice != null && resolvedPrice > 0) {
            _aiTaskPrice = resolvedPrice;
          }

          final eventType = (event['type'] ?? '').toString();
          final processed = int.tryParse('${event['processed'] ?? 0}') ?? 0;
          final total = int.tryParse('${event['total'] ?? 0}') ?? 0;

          if (eventType == 'chunk') {
            final availableChunk = (event['available'] as List? ?? const [])
                .map(
                  (row) =>
                      _normalizeProviderRow(Map<String, dynamic>.from(row)),
                )
                .where((provider) => provider['id'] != null)
                .toList();
            final unavailableChunk = (event['unavailable'] as List? ?? const [])
                .map(
                  (row) =>
                      _normalizeProviderRow(Map<String, dynamic>.from(row)),
                )
                .where((provider) => provider['id'] != null)
                .toList();

            if (availableChunk.isNotEmpty || unavailableChunk.isNotEmpty) {
              _providerSearchState.providerSearchHasAnyMatch = true;
            }

            _appendProviderChunk(availableChunk, unavailableChunk);

            _sortVisibleProviders();
            _restorePendingProviderCardIfVisible();

            if (!keyboardDismissedForRequest &&
                (availableChunk.isNotEmpty || unavailableChunk.isNotEmpty)) {
              keyboardDismissedForRequest = true;
              _dismissKeyboard();
            }
          }

          if (eventType == 'done') {
            _providerSearchState.providerSearchCompleted = true;
            _providerSearchState.providerSearchMessage =
                _providerSearchState.providers.isNotEmpty
                ? 'Salões carregados.'
                : _providerSearchState.providerSearchHasAnyMatch
                ? 'Encontramos salões, mas sem horário imediato.'
                : 'Busca concluída.';
            _providerSearchState.providerSearchDetail =
                _providerSearchState.providers.isNotEmpty
                ? 'Agora você já pode escolher o melhor salão.'
                : _providerSearchState.providerSearchHasAnyMatch
                ? 'Abra um salão para consultar a próxima disponibilidade.'
                : 'Não encontramos salões parceiros próximos para esse serviço.';
            if (!keyboardDismissedForRequest) {
              keyboardDismissedForRequest = true;
              _dismissKeyboard();
            }
          }

          _providerSearchState.loadingProviders =
              eventType == 'service' && processed == 0;
          _providerSearchState.loadingMoreProviders =
              (total > 0 && processed < total && eventType != 'done') ||
              _providerSearchState.pendingProviders.isNotEmpty ||
              _providerSearchState.pendingUnavailableProviders.isNotEmpty;
        });

        if ((event['type'] ?? '').toString() == 'chunk') {
          _scheduleNextProviderReveal();
        }
      }
    } catch (e) {
      debugPrint('Error fetching providers: $e');
    } finally {
      if (mounted && requestId == _providerSearchState.providersRequestId) {
        setState(() {
          _providerSearchState.loadingProviders = false;
          _providerSearchState.loadingMoreProviders =
              _providerSearchState.pendingProviders.isNotEmpty ||
              _providerSearchState.pendingUnavailableProviders.isNotEmpty;
          _providerSearchState.providerSearchCompleted = true;
          if (_providerSearchState.providers.isNotEmpty) {
            _providerSearchState.providerSearchMessage = 'Salões carregados.';
            _providerSearchState.providerSearchDetail =
                'Agora você já pode escolher o melhor salão.';
          } else if (_providerSearchState.providerSearchHasAnyMatch) {
            _providerSearchState.providerSearchMessage =
                'Encontramos salões, mas sem horário imediato.';
            _providerSearchState.providerSearchDetail =
                'Abra um salão para consultar a próxima disponibilidade.';
          }
        });
        if (preservePendingPixContext) {
          _restorePendingProviderCardIfVisible();
        }
      }
    }
  }

  Future<void> _fetchSlots() async {
    if (_scheduleState.loadingSlots) return;
    if (_selectedProviderId == null) return;

    setState(() => _scheduleState.loadingSlots = true);
    try {
      final date =
          _scheduleState.selectedDate ??
          DateTime.now().toUtc().subtract(const Duration(hours: 3));
      final dateStr =
          "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

      final slots = await _getAvailableSlots(
        _selectedProviderId!,
        date: dateStr,
        requiredDurationMinutes: _requiredServiceDurationMinutes,
      );

      // Filter out past slots if today
      final minimumStartTime = _minimumClientBookingTime;
      if (_scheduleState.selectedDate != null &&
          _scheduleState.selectedDate!.year == minimumStartTime.year &&
          _scheduleState.selectedDate!.month == minimumStartTime.month &&
          _scheduleState.selectedDate!.day == minimumStartTime.day) {
        slots.removeWhere((slot) {
          final startStr = slot['start_time'].toString();
          final slotTime = DateTime.tryParse(startStr)?.toLocal();
          return slotTime != null && slotTime.isBefore(minimumStartTime);
        });
      }

      setState(() {
        _scheduleState.realSlots = slots;
        final nextSlot = _firstSelectableSlot(slots);
        if (nextSlot != null) {
          final nextStart = nextSlot['start_time']?.toString();
          for (final provider in _providerSearchState.providers) {
            if ('${provider['id']}' == '$_selectedProviderId') {
              provider['next_available_slot'] = nextSlot;
              provider['next_available_at'] = nextStart;
              break;
            }
          }
        }
      });
    } catch (e) {
      debugPrint('Error fetching slots: $e');
    } finally {
      if (mounted) setState(() => _scheduleState.loadingSlots = false);
    }
  }

  void _sortVisibleProviders() {
    _providerSearchState.providers.sort((a, b) {
      final aDistance = a['distance_km'] is num
          ? (a['distance_km'] as num).toDouble()
          : double.infinity;
      final bDistance = b['distance_km'] is num
          ? (b['distance_km'] as num).toDouble()
          : double.infinity;
      final byDistance = aDistance.compareTo(bDistance);
      if (byDistance != 0) return byDistance;
      final aSlot = DateTime.tryParse('${a['next_available_at'] ?? ''}');
      final bSlot = DateTime.tryParse('${b['next_available_at'] ?? ''}');
      if (aSlot == null && bSlot == null) return 0;
      if (aSlot == null) return 1;
      if (bSlot == null) return -1;
      return aSlot.compareTo(bSlot);
    });
    _providerSearchState.unavailableProviders.sort((a, b) {
      final aDistance = a['distance_km'] is num
          ? (a['distance_km'] as num).toDouble()
          : double.infinity;
      final bDistance = b['distance_km'] is num
          ? (b['distance_km'] as num).toDouble()
          : double.infinity;
      return aDistance.compareTo(bDistance);
    });
  }

  void _handleProvidersScroll() {
    if (!_descScrollController.hasClients) return;
    final position = _descScrollController.position;
    if (position.pixels >= position.maxScrollExtent - 220) {
      _revealMoreProviders(scheduleFollowUp: false);
    }
  }

  void _scheduleNextProviderReveal() {
    if (_providersRevealTimer?.isActive == true ||
        _providerSearchState.isRevealingMoreProviders ||
        (!mounted) ||
        (_providerSearchState.pendingProviders.isEmpty &&
            _providerSearchState.pendingUnavailableProviders.isEmpty)) {
      return;
    }

    _providersRevealTimer = Timer(_providersRevealCadence, () {
      _providersRevealTimer = null;
      if (!mounted) return;
      _revealMoreProviders();
    });
  }

  void _revealMoreProviders({bool scheduleFollowUp = true}) {
    if (_providerSearchState.isRevealingMoreProviders ||
        (_providerSearchState.pendingProviders.isEmpty &&
            _providerSearchState.pendingUnavailableProviders.isEmpty)) {
      return;
    }
    _providerSearchState.isRevealingMoreProviders = true;
    setState(() {
      if (_providerSearchState.pendingProviders.isNotEmpty) {
        final take = _providerSearchState.pendingProviders
            .take(_providersRevealBatchSize)
            .toList();
        _providerSearchState.providers.addAll(take);
        _providerSearchState.pendingProviders.removeRange(0, take.length);
      } else if (_providerSearchState.pendingUnavailableProviders.isNotEmpty) {
        final take = _providerSearchState.pendingUnavailableProviders
            .take(_providersRevealBatchSize)
            .toList();
        _providerSearchState.providers.addAll(take);
        _providerSearchState.unavailableProviders.addAll(take);
        _providerSearchState.pendingUnavailableProviders.removeRange(
          0,
          take.length,
        );
      }
      _sortVisibleProviders();
      _providerSearchState.loadingMoreProviders =
          _providerSearchState.pendingProviders.isNotEmpty ||
          _providerSearchState.pendingUnavailableProviders.isNotEmpty;
    });
    _providerSearchState.isRevealingMoreProviders = false;

    if (scheduleFollowUp &&
        (_providerSearchState.pendingProviders.isNotEmpty ||
            _providerSearchState.pendingUnavailableProviders.isNotEmpty)) {
      _scheduleNextProviderReveal();
    }
  }

  GlobalKey _providerCardKeyFor(int providerId) {
    return _providerCardKeys.putIfAbsent(providerId, () => GlobalKey());
  }

  void _scrollToExpandedProvider(int providerId) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final key = _providerCardKeys[providerId];
      final contextForCard = key?.currentContext;
      if (contextForCard == null) return;
      await Scrollable.ensureVisible(
        contextForCard,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
        alignment: 0.08,
      );
    });
  }

  void _scrollToPendingPixSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final pixContext = _pendingPixSectionKey.currentContext;
      if (pixContext == null) return;
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      await Scrollable.ensureVisible(
        pixContext,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic,
        alignment: 0.18,
      );
    });
  }

  Future<void> _toggleProviderExpansion(Map<String, dynamic> p) async {
    final providerId = int.tryParse(p['id'].toString());
    if (providerId == null) return;

    if (_providerSearchState.expandedProviderId == providerId) {
      setState(() {
        _providerSearchState.expandedProviderId = null;
        _scheduleState.realSlots = [];
        _scheduleState.selectedTimeSlot = null;
        if (_pendingPixState.visible && _selectedProviderId == providerId) {
          _pendingPixState.visible = false;
        }
      });
      return;
    }

    final nextSlot = p['next_available_slot'] is Map
        ? Map<String, dynamic>.from(p['next_available_slot'] as Map)
        : null;
    final slotStart = nextSlot != null ? _slotStartLocal(nextSlot) : null;

    setState(() {
      _providerSearchState.expandedProviderId = providerId;
      _selectedProviderId = providerId;
      _latitude = double.tryParse(p['latitude']?.toString() ?? '');
      _longitude = double.tryParse(p['longitude']?.toString() ?? '');
      _address = p['address']?.toString();
      _addressController.text = _address ?? '';
      if (slotStart != null) {
        _scheduleState.selectedDate = DateTime(
          slotStart.year,
          slotStart.month,
          slotStart.day,
        );
        _scheduleState.selectedTimeSlot =
            '${slotStart.hour.toString().padLeft(2, '0')}:${slotStart.minute.toString().padLeft(2, '0')}';
      } else {
        final now = DateTime.now();
        _scheduleState.selectedDate = DateTime(now.year, now.month, now.day);
        _scheduleState.selectedTimeSlot = null;
      }
      _scheduleState.realSlots = [];
    });
    _scrollToExpandedProvider(providerId);

    await _fetchSlots();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now();
    _scheduleState.selectedDate = DateTime(now.year, now.month, now.day);
    _descScrollController.addListener(_handleProvidersScroll);

    _loadInitialState();
    unawaited(_restorePendingPixState());
    _fetchUserLocation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = state == AppLifecycleState.resumed;
    _isAppInForeground = isForeground;
    if (isForeground) {
      unawaited(_resumePendingPixWatcherIfNeeded());
      return;
    }
    _stopPendingPixWatcher();
  }

  Future<void> _fetchAddressFromCoordinates(
    Map<String, dynamic> provider,
  ) async {
    if (provider['latitude'] == null || provider['longitude'] == null) return;

    try {
      double lat = double.parse(provider['latitude'].toString());
      double lon = double.parse(provider['longitude'].toString());

      List<Placemark> placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String address =
            "${place.street ?? ''}, ${place.subLocality ?? ''} - ${place.subAdministrativeArea ?? ''}";
        if (place.street == null || place.street!.isEmpty) {
          address =
              "${place.subLocality ?? ''}, ${place.subAdministrativeArea ?? ''}";
        }

        setState(() {
          provider['address'] = address
              .replaceAll(RegExp(r'^, | - $'), '')
              .trim();
        });
      }
    } catch (e) {
      debugPrint("Error fetching address for provider: $e");
    }
  }

  Future<void> _fetchUserLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _userPosition = pos);
      if ((_currentStep == 1 || _currentStep == 2) &&
          _effectiveServiceQuery().trim().isNotEmpty) {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        unawaited(_fetchProviders(_effectiveServiceQuery()));
      }
    } catch (e) {
      debugPrint('Error getting user location: $e');
    }
  }

  void _loadInitialState() {
    // 1. DADOS VINDOS DA IA (MÓVEL -> FIXO)
    if (widget.initialData != null) {
      final d = widget.initialData!;
      final shouldFocusPendingPix = d['pending_fixed_payment_focus'] == true;
      final pendingIntentId = (d['pending_fixed_booking_intent_id'] ?? '')
          .toString()
          .trim();
      final rawService = d['service'];
      final selectedService = rawService is Map
          ? Map<String, dynamic>.from(rawService)
          : null;

      _selectedService = selectedService;
      _descriptionController.text =
          (d['description'] ?? d['q'] ?? selectedService?['name'] ?? '')
              .toString();
      _selectedProfession =
          (d['profession'] ??
                  selectedService?['profession'] ??
                  selectedService?['category'] ??
                  selectedService?['name'])
              ?.toString();
      _aiProfessionName = _selectedProfession;
      _aiTaskName =
          (d['task_name'] ??
                  selectedService?['name'] ??
                  selectedService?['title'])
              ?.toString();
      _aiTaskId = int.tryParse(
        '${d['task_id'] ?? selectedService?['id'] ?? ''}',
      );
      _aiTaskPrice = double.tryParse(
        '${d['price'] ?? selectedService?['price'] ?? selectedService?['unit_price'] ?? ''}',
      );
      _aiCategoryId = int.tryParse(
        '${d['category_id'] ?? selectedService?['category_id'] ?? ''}',
      );
      _aiServiceType =
          (d['service_type'] ??
                  selectedService?['service_type'] ??
                  'at_provider')
              .toString();
      _latitude = double.tryParse('${d['lat'] ?? d['latitude'] ?? ''}');
      _longitude = double.tryParse('${d['lon'] ?? d['longitude'] ?? ''}');

      if (shouldFocusPendingPix && pendingIntentId.isNotEmpty) {
        final rawProvider = d['pre_selected_provider'];
        final provider = rawProvider is Map
            ? Map<String, dynamic>.from(rawProvider)
            : <String, dynamic>{};
        final pendingSeed = <String, dynamic>{
          'id': pendingIntentId,
          'intent_id': pendingIntentId,
          'provider_id': provider['id'],
          'provider': provider,
          'provider_name':
              provider['commercial_name'] ??
              provider['full_name'] ??
              d['provider_name'],
          'address': provider['address'] ?? d['address'],
          'latitude': provider['latitude'] ?? d['latitude'],
          'longitude': provider['longitude'] ?? d['longitude'],
          'task_name':
              d['task_name'] ??
              d['description'] ??
              selectedService?['name'] ??
              d['q'],
          'profession_name':
              d['profession'] ??
              selectedService?['profession'] ??
              selectedService?['category'],
          'category_id': d['category_id'] ?? selectedService?['category_id'],
          'task_id': d['task_id'] ?? selectedService?['id'],
          'task_price':
              d['price'] ??
              selectedService?['price'] ??
              selectedService?['unit_price'],
        };
        unawaited(
          _restorePendingPixFromData(pendingSeed, persistRecoveredState: false),
        );
        return;
      }

      if (d['pre_selected_provider'] != null) {
        final p = d['pre_selected_provider'];
        _selectedProviderId = int.tryParse(p['id']?.toString() ?? '');
        _providerSearchState.providers = [p];
        _providerSearchState.unavailableProviders = [];

        // Pega localização do prestador
        _latitude = double.tryParse(p['latitude']?.toString() ?? '');
        _longitude = double.tryParse(p['longitude']?.toString() ?? '');
        _address = p['address']?.toString();
        _addressController.text = _address ?? '';

        _currentStep = 3; // Pula para Agenda (Calendário)
        _fetchSlots();
      } else {
        final searchTerm = _effectiveServiceQuery();
        if (searchTerm.trim().isNotEmpty) {
          _fetchProviders(searchTerm);
        }
        _currentStep = 1; // Abre na âncora fixa com busca + listagem
      }
    }

    // 2. DADOS VINDOS DE UM PERFIL ESPECÍFICO (BOTÃO AGENDAR)
    if (widget.initialProviderId != null) {
      _selectedProviderId = widget.initialProviderId;
      if (widget.initialProvider != null) {
        _providerSearchState.providers = [widget.initialProvider!];
        _providerSearchState.unavailableProviders = [];

        final p = widget.initialProvider!;
        _latitude = double.tryParse(p['latitude']?.toString() ?? '');
        _longitude = double.tryParse(p['longitude']?.toString() ?? '');
        _address = p['address']?.toString();
        _addressController.text = _address ?? '';
      }

      if (widget.initialService != null) {
        _selectedService = widget.initialService;
        final rawCat = widget.initialService!['category'];
        final rawName = widget.initialService!['name'];
        _selectedProfession = rawName?.toString() ?? rawCat?.toString();
        _aiProfessionName = _selectedProfession;
        if (_descriptionController.text.isEmpty) {
          _descriptionController.text =
              "Agendamento de ${rawName?.toString() ?? ''}";
        }

        _aiTaskName = rawName?.toString();
        if (widget.initialService!['price'] != null) {
          _aiTaskPrice = double.tryParse(
            widget.initialService!['price'].toString(),
          );
        }
      }
      _currentStep =
          3; // Pula escolha de prestador, vai para Agenda (Calendário)
      _fetchSlots();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _aiDebounce?.cancel();
    _pixStatusPollTimer?.cancel();
    _providersRevealTimer?.cancel();
    _descScrollController.removeListener(_handleProvidersScroll);
    _descriptionController.dispose();
    _addressController.dispose();
    _professionSearchController.dispose();
    _descScrollController.dispose();
    super.dispose();
  }

  void _stopPendingPixWatcher() {
    _pixStatusPollTimer?.cancel();
    _pixStatusPollTimer = null;
  }

  Future<void> _resumePendingPixWatcherIfNeeded() async {
    try {
      final intentId = (_pendingPixState.intentId ?? '').trim();
      if (!_isAppInForeground ||
          intentId.isEmpty ||
          !_pendingPixState.visible) {
        return;
      }
      if (_pixStatusPollTimer != null) return;

      final detail = await _api.getPendingFixedBookingIntent(intentId);
      if (!mounted) return;
      if (detail == null) {
        await _clearPendingPixState();
        if (!mounted) return;
        setState(_clearPendingPixStateInMemory);
        return;
      }

      final decision = PendingFixedBookingPolicy.evaluate(detail);
      if (decision.shouldNavigateToScheduledService) {
        await _clearPendingPixState();
        if (!mounted) return;
        setState(_clearPendingPixStateInMemory);
        context.go(decision.scheduledServiceRoute);
        return;
      }

      if (decision.shouldClearCache) {
        await _clearPendingPixState();
        if (!mounted) return;
        setState(_clearPendingPixStateInMemory);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'A reserva temporária expirou. Escolha um novo horário disponível.',
            ),
          ),
        );
        return;
      }

      _startPendingPixWatcher(intentId);
    } catch (e) {
      debugPrint('Erro ao retomar watcher do PIX pendente: $e');
    }
  }

  Future<Map<String, dynamic>>
  _createPendingFixedBookingIntentForSelectedSlot() async {
    await _api.loadToken();

    if (_latitude == null || _longitude == null) {
      if (_selectedProviderId != null) {
        final provider = _providerSearchState.providers.firstWhere(
          (p) => int.tryParse(p['id'].toString()) == _selectedProviderId,
          orElse: () => {},
        );
        if (provider.isNotEmpty) {
          _latitude = double.tryParse(provider['latitude'].toString());
          _longitude = double.tryParse(provider['longitude'].toString());
          _address = provider['address']?.toString();
          _addressController.text = _address ?? '';
        }
      }
    }

    if (_latitude == null || _longitude == null) {
      throw Exception("Endereço do estabelecimento não encontrado.");
    }

    final addrRaw = _addressController.text.isEmpty
        ? (_address ?? '')
        : _addressController.text;
    final addressSafe = addrRaw.length > 255
        ? addrRaw.substring(0, 255)
        : addrRaw;

    String desc = _descriptionController.text.isEmpty
        ? ''
        : _descriptionController.text;
    if (desc.trim().length < 5) {
      desc = '${desc.trim()} - Serviço solicitado';
    }

    if (_aiTaskName != null) {
      desc = "Serviço: $_aiTaskName\n$desc";
    }

    final categoryId = _aiCategoryId ?? 1;
    final price = _aiTaskPrice ?? _priceEstimated;
    final upfront = price * 0.10;

    DateTime? scheduledAt;
    if (_scheduleState.selectedDate != null &&
        _scheduleState.selectedTimeSlot != null) {
      final parts = _scheduleState.selectedTimeSlot!.split(':');
      if (parts.length == 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        scheduledAt = DateTime(
          _scheduleState.selectedDate!.year,
          _scheduleState.selectedDate!.month,
          _scheduleState.selectedDate!.day,
          hour,
          minute,
        );
      }
    }

    if (scheduledAt == null) {
      throw Exception('Horário inválido para o agendamento.');
    }

    final resolvedProfessionId = await _api
        .resolveProfessionIdForServiceCreation(
          professionId: null,
          taskId: _aiTaskId,
          professionName: _selectedProfession ?? _aiProfessionName,
        );

    final authUid = Supabase.instance.client.auth.currentUser?.id ?? '';
    final clientUserId = _api.userIdInt ?? 0;
    String? providerUid;
    try {
      final providerUser = await Supabase.instance.client
          .from('users')
          .select('supabase_uid')
          .eq('id', _selectedProviderId!)
          .maybeSingle();
      providerUid = (providerUser?['supabase_uid'] ?? '').toString().trim();
      if (providerUid.isEmpty) providerUid = null;
    } catch (_) {}

    final intent = await _createIntent(
      clientUserId: clientUserId,
      clienteUid: authUid,
      providerId: _selectedProviderId!,
      providerUid: providerUid,
      procedureName: desc,
      scheduledStartUtc: scheduledAt.toUtc(),
      durationMinutes: _requiredServiceDurationMinutes,
      totalPrice: price,
      upfrontPrice: upfront,
      professionId: resolvedProfessionId,
      professionName: _selectedProfession ?? _aiProfessionName,
      taskId: _aiTaskId,
      taskName: _aiTaskName,
      categoryId: categoryId,
      address: addressSafe,
      latitude: _latitude!,
      longitude: _longitude!,
      imageKeys: _imageKeys,
      videoKey: _videoKey,
    );

    return {
      'result': {
        'id': intent.id,
        'status': intent.status,
        'payment_status': intent.paymentStatus,
        'scheduled_at': intent.scheduledAt.toIso8601String(),
        'price_estimated': intent.priceEstimated,
        'price_upfront': intent.priceUpfront,
      },
      'intentId': intent.id,
      'upfront': upfront,
      'total': price,
    };
  }

  Future<void> _persistPendingPixState({
    required String intentId,
    required Map<String, dynamic> provider,
    required String payload,
    required String image,
    required double fee,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = <String, dynamic>{
      'intent_id': intentId,
      'provider_id': _selectedProviderId,
      'provider': provider,
      'query': _descriptionController.text.trim(),
      'task_name': _aiTaskName,
      'profession_name': _aiProfessionName ?? _selectedProfession,
      'task_id': _aiTaskId,
      'category_id': _aiCategoryId,
      'task_price': _aiTaskPrice,
      'service_type': _aiServiceType ?? 'at_provider',
      'selected_date': _scheduleState.selectedDate?.toIso8601String(),
      'selected_time': _scheduleState.selectedTimeSlot,
      'pix_payload': payload,
      'pix_image': image,
      'pix_fee': fee,
      'pix_visible': true,
      'saved_at': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_pendingPixPrefsKey, jsonEncode(raw));
  }

  Future<void> _clearPendingPixState() async {
    await PendingFixedBookingPolicy.clearLocalCache();
  }

  Map<String, dynamic>? _decodePendingPixState(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
    } catch (e) {
      debugPrint('Erro ao decodificar estado pendente do PIX: $e');
    }
    return null;
  }

  Map<String, dynamic>? _mergePendingPixRestoreData({
    Map<String, dynamic>? persisted,
    Map<String, dynamic>? backend,
  }) {
    if (persisted == null && backend == null) return null;
    if (persisted == null) return backend;
    if (backend == null) return persisted;

    final persistedId = (persisted['intent_id'] ?? persisted['id'] ?? '')
        .toString()
        .trim();
    final backendId = (backend['id'] ?? backend['intent_id'] ?? '')
        .toString()
        .trim();

    if (persistedId.isEmpty || backendId.isEmpty || persistedId != backendId) {
      return backend;
    }

    return {
      ...backend,
      'intent_id': backendId,
      if ((persisted['provider_id'] ?? '').toString().trim().isNotEmpty)
        'provider_id': persisted['provider_id'],
      if (persisted['provider'] is Map) 'provider': persisted['provider'],
      if ((persisted['query'] ?? '').toString().trim().isNotEmpty)
        'query': persisted['query'],
      if ((persisted['task_name'] ?? '').toString().trim().isNotEmpty)
        'task_name': persisted['task_name'],
      if ((persisted['profession_name'] ?? '').toString().trim().isNotEmpty)
        'profession_name': persisted['profession_name'],
      if (persisted['task_id'] != null) 'task_id': persisted['task_id'],
      if (persisted['category_id'] != null)
        'category_id': persisted['category_id'],
      if (persisted['task_price'] != null)
        'task_price': persisted['task_price'],
      if ((persisted['service_type'] ?? '').toString().trim().isNotEmpty)
        'service_type': persisted['service_type'],
      if ((persisted['selected_date'] ?? '').toString().trim().isNotEmpty)
        'selected_date': persisted['selected_date'],
      if ((persisted['selected_time'] ?? '').toString().trim().isNotEmpty)
        'selected_time': persisted['selected_time'],
      if ((persisted['pix_payload'] ?? '').toString().trim().isNotEmpty)
        'pix_payload': persisted['pix_payload'],
      if ((persisted['pix_image'] ?? '').toString().trim().isNotEmpty)
        'pix_image': persisted['pix_image'],
      if (persisted['pix_fee'] != null) 'pix_fee': persisted['pix_fee'],
      if (persisted['saved_at'] != null) 'saved_at': persisted['saved_at'],
    };
  }

  Map<String, dynamic> _providerCardFromProfile(
    int providerId,
    Map<String, dynamic> profile,
    Map<String, dynamic> intent,
  ) {
    final providersRaw = profile['providers'];
    final providerMeta =
        providersRaw is List &&
            providersRaw.isNotEmpty &&
            providersRaw.first is Map
        ? Map<String, dynamic>.from(providersRaw.first as Map)
        : providersRaw is Map
        ? Map<String, dynamic>.from(providersRaw)
        : <String, dynamic>{};

    return {
      'id': providerId,
      'user_id': providerId,
      'full_name':
          profile['full_name'] ??
          profile['name'] ??
          providerMeta['full_name'] ??
          providerMeta['commercial_name'] ??
          'Salão parceiro',
      'commercial_name':
          providerMeta['commercial_name'] ??
          profile['commercial_name'] ??
          profile['full_name'] ??
          profile['name'] ??
          'Salão parceiro',
      'avatar_url':
          profile['avatar_url'] ??
          profile['photo'] ??
          profile['avatar'] ??
          providerMeta['avatar_url'],
      'rating': profile['rating'] ?? providerMeta['rating'],
      'reviews_count':
          profile['rating_count'] ??
          profile['reviews_count'] ??
          providerMeta['reviews_count'],
      'address':
          intent['address'] ??
          providerMeta['address'] ??
          profile['address'] ??
          'Endereço do salão',
      'latitude':
          intent['latitude'] ?? providerMeta['latitude'] ?? profile['latitude'],
      'longitude':
          intent['longitude'] ??
          providerMeta['longitude'] ??
          profile['longitude'],
      'service_type': 'at_provider',
    };
  }

  Future<void> _restorePendingPixFromData(
    Map<String, dynamic> pending, {
    bool persistRecoveredState = false,
  }) async {
    final intentId = (pending['intent_id'] ?? pending['id'] ?? '')
        .toString()
        .trim();
    if (intentId.isEmpty) {
      await _clearPendingPixState();
      return;
    }

    final detail =
        pending.containsKey('status') &&
            pending.containsKey('payment_status') &&
            pending.containsKey('scheduled_at')
        ? pending
        : await _api.getPendingFixedBookingIntent(intentId);
    if (detail == null) {
      await _clearPendingPixState();
      return;
    }

    final restoreDecision = PendingFixedBookingPolicy.evaluate(detail);
    if (restoreDecision.shouldNavigateToScheduledService) {
      await _clearPendingPixState();
      if (!mounted) return;
      context.go(restoreDecision.scheduledServiceRoute);
      return;
    }
    if (restoreDecision.shouldClearCache) {
      await _clearPendingPixState();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Seu horário reservado expirou. Escolha um novo horário disponível.',
          ),
        ),
      );
      return;
    }

    final providerId = int.tryParse(
      '${pending['provider_id'] ?? detail['prestador_user_id'] ?? ''}',
    );
    Map<String, dynamic> providerData = pending['provider'] is Map
        ? _normalizeProviderRow(
            Map<String, dynamic>.from(pending['provider'] as Map),
          )
        : <String, dynamic>{};
    if (providerData.isEmpty && providerId != null) {
      try {
        final profile = await _api.getProviderProfile(providerId);
        providerData = _normalizeProviderRow(
          _providerCardFromProfile(providerId, profile, detail),
        );
      } catch (e) {
        debugPrint('Erro ao carregar perfil do prestador pendente: $e');
      }
    }

    final detailScheduledAt = DateTime.tryParse(
      '${detail['scheduled_at'] ?? ''}',
    )?.toLocal();
    final persistedSelectedDate = DateTime.tryParse(
      '${pending['selected_date'] ?? ''}',
    )?.toLocal();
    final selectedDateSource = detailScheduledAt ?? persistedSelectedDate;
    final selectedDate = selectedDateSource != null
        ? DateTime(
            selectedDateSource.year,
            selectedDateSource.month,
            selectedDateSource.day,
          )
        : null;
    final selectedTime =
        (pending['selected_time'] ?? '').toString().trim().isNotEmpty
        ? (pending['selected_time'] ?? '').toString().trim()
        : detailScheduledAt != null
        ? '${detailScheduledAt.hour.toString().padLeft(2, '0')}:${detailScheduledAt.minute.toString().padLeft(2, '0')}'
        : '';
    final query = (pending['query'] ?? detail['description'] ?? '')
        .toString()
        .trim();

    if (!mounted) return;
    setState(() {
      _descriptionController.text = query;
      _aiTaskName = (pending['task_name'] ?? detail['task_name'] ?? _aiTaskName)
          ?.toString();
      _aiProfessionName =
          (pending['profession_name'] ??
                  detail['profession_name'] ??
                  _aiProfessionName)
              ?.toString();
      _selectedProfession = _aiProfessionName;
      _aiTaskId = int.tryParse(
        '${pending['task_id'] ?? detail['task_id'] ?? _aiTaskId ?? ''}',
      );
      _aiCategoryId = int.tryParse(
        '${pending['category_id'] ?? detail['category_id'] ?? _aiCategoryId ?? ''}',
      );
      final savedPrice = double.tryParse(
        '${pending['task_price'] ?? detail['price_estimated'] ?? ''}',
      );
      if (savedPrice != null && savedPrice > 0) {
        _aiTaskPrice = savedPrice;
      }
      _aiServiceType = 'at_provider';
      _scheduleState.selectedDate = selectedDate ?? _scheduleState.selectedDate;
      _scheduleState.selectedTimeSlot = selectedTime;
      _pendingPixState.intentId = intentId;
      _pendingPixState.payload = (pending['pix_payload'] ?? '')
          .toString()
          .trim();
      _pendingPixState.image = (pending['pix_image'] ?? '').toString().trim();
      _pendingPixState.fee =
          double.tryParse(
            '${pending['pix_fee'] ?? detail['price_upfront'] ?? ''}',
          ) ??
          _pendingPixState.fee;
      _pendingPixState.visible = true;
      _pendingPixState.pendingProviderAutoScrollArmed = true;
      _currentStep = 1;
      if (providerId != null) {
        _selectedProviderId = providerId;
        _providerSearchState.expandedProviderId = providerId;
      }
      if (providerData.isNotEmpty && providerId != null) {
        final exists = _providerSearchState.providers.any(
          (element) => int.tryParse('${element['id']}') == providerId,
        );
        if (!exists) {
          _providerSearchState.providers = [
            providerData,
            ..._providerSearchState.providers,
          ];
        }
        _address = (detail['address'] ?? providerData['address'])?.toString();
        _addressController.text = _address ?? '';
        _latitude = double.tryParse(
          '${detail['latitude'] ?? providerData['latitude'] ?? ''}',
        );
        _longitude = double.tryParse(
          '${detail['longitude'] ?? providerData['longitude'] ?? ''}',
        );
      }
    });

    if (query.isNotEmpty) {
      unawaited(_fetchProviders(query, preservePendingPixContext: true));
    }
    if (providerId != null) {
      _scrollToExpandedProvider(providerId);
    }
    await _fetchSlots();
    _scrollToPendingPixSection();

    if ((_pendingPixState.payload ?? '').isEmpty) {
      try {
        final pix = await _api.loadPixPayload(pendingFixedBookingId: intentId);
        if (!mounted) return;
        setState(() {
          _pendingPixState.payload = (pix['payload'] ?? '').toString().trim();
          _pendingPixState.image =
              (pix['encodedImage'] ?? pix['image_url'] ?? '').toString().trim();
          _pendingPixState.fee =
              double.tryParse('${pix['amount'] ?? ''}') ?? _pendingPixState.fee;
        });
        _scrollToPendingPixSection();
      } catch (e) {
        debugPrint('Erro ao restaurar payload PIX pendente: $e');
      }
    }

    if (persistRecoveredState) {
      await _persistPendingPixState(
        intentId: intentId,
        provider: providerData,
        payload: _pendingPixState.payload ?? '',
        image: _pendingPixState.image ?? '',
        fee: _pendingPixState.fee,
      );
    }

    _startPendingPixWatcher(intentId);
  }

  void _startPendingPixWatcher(String intentId) {
    if (!_isAppInForeground) return;
    _stopPendingPixWatcher();
    _pixStatusPollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      try {
        final detail = await _api.getPendingFixedBookingIntent(intentId);
        if (detail == null) {
          _pixStatusPollTimer?.cancel();
          await _clearPendingPixState();
          if (!mounted) return;
          setState(() {
            _clearPendingPixStateInMemory();
          });
          return;
        }

        final decision = PendingFixedBookingPolicy.evaluate(detail);
        if (decision.shouldNavigateToScheduledService) {
          _pixStatusPollTimer?.cancel();
          await _clearPendingPixState();
          if (!mounted) return;
          setState(() {
            _clearPendingPixStateInMemory();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pagamento confirmado. Agendamento reservado!'),
              backgroundColor: Colors.green,
            ),
          );
          context.go(decision.scheduledServiceRoute);
          return;
        }

        if (decision.shouldClearCache) {
          _pixStatusPollTimer?.cancel();
          await _clearPendingPixState();
          if (!mounted) return;
          setState(() {
            _clearPendingPixStateInMemory();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'A reserva temporária expirou. Escolha um novo horário disponível.',
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint('Erro ao verificar pagamento PIX pendente: $e');
      }
    });
  }

  void _clearPendingPixStateInMemory() {
    _pendingPixState.clear();
  }

  Future<void> _restorePendingPixState() async {
    final prefs = await SharedPreferences.getInstance();
    final persistedPending =
        _decodePendingPixState(prefs.getString(_pendingPixPrefsKey)) ??
        _decodePendingPixState(prefs.getString(_legacyPendingPixPrefsKey));

    Map<String, dynamic>? backendPending;
    try {
      backendPending = await _api
          .getLatestPendingFixedBookingIntentForCurrentClient();
    } catch (e) {
      debugPrint('Erro ao restaurar pendência PIX do backend: $e');
    }

    final resolvedPending = _mergePendingPixRestoreData(
      persisted: persistedPending,
      backend: backendPending,
    );
    if (resolvedPending == null) {
      if (persistedPending != null) {
        await _clearPendingPixState();
      }
      return;
    }

    final backendId = (backendPending?['id'] ?? '').toString().trim();
    final resolvedId =
        (resolvedPending['intent_id'] ?? resolvedPending['id'] ?? '')
            .toString()
            .trim();

    try {
      await _restorePendingPixFromData(
        resolvedPending,
        persistRecoveredState: backendId.isNotEmpty && backendId == resolvedId,
      );
    } catch (e) {
      debugPrint('Erro ao restaurar agendamento PIX pendente: $e');
      await _clearPendingPixState();
    }
  }

  void _restorePendingProviderCardIfVisible() {
    if (!_pendingPixState.visible ||
        !_pendingPixState.pendingProviderAutoScrollArmed ||
        _providerSearchState.expandedProviderId == null) {
      return;
    }
    final exists = _providerSearchState.providers.any(
      (provider) =>
          int.tryParse('${provider['id']}') ==
          _providerSearchState.expandedProviderId,
    );
    if (exists) {
      _pendingPixState.pendingProviderAutoScrollArmed = false;
      _scrollToExpandedProvider(_providerSearchState.expandedProviderId!);
    }
  }

  Future<void> _changePendingSchedule(Map<String, dynamic> provider) async {
    if (_changingPendingSchedule) return;
    final intentId = (_pendingPixState.intentId ?? '').trim();
    setState(() => _changingPendingSchedule = true);
    try {
      _pixStatusPollTimer?.cancel();
      if (intentId.isNotEmpty) {
        await _cancelIntent(intentId);
      }
      await _clearPendingPixState();
      if (!mounted) return;
      setState(() {
        _clearPendingPixStateInMemory();
      });
      await _fetchSlots();
      _scrollToExpandedProvider(int.tryParse('${provider['id']}') ?? 0);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reserva anterior cancelada. Escolha uma nova data.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível alterar o horário agora: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _changingPendingSchedule = false);
      }
    }
  }

  Future<bool> _openFixedBookingReviewScreen(
    Map<String, dynamic> provider,
  ) async {
    if (_scheduleState.selectedDate == null ||
        _scheduleState.selectedTimeSlot == null)
      return false;
    final serviceLabel = _serviceLabelForProvider(provider);
    final totalValue =
        _aiTaskPrice ??
        double.tryParse(
          '${_selectedService?['price'] ?? _selectedService?['unit_price'] ?? ''}',
        ) ??
        _priceEstimated;

    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FixedBookingReviewScreen(
          provider: provider,
          serviceLabel: serviceLabel,
          professionName: _selectedProfession ?? _aiProfessionName,
          selectedDate: _scheduleState.selectedDate!,
          selectedTimeSlot: _scheduleState.selectedTimeSlot!,
          address: _addressController.text.trim().isNotEmpty
              ? _addressController.text.trim()
              : _address,
          totalValue: totalValue,
        ),
      ),
    );

    return confirmed == true;
  }

  Future<void> _confirmExpandedProviderSchedule(
    Map<String, dynamic> provider,
  ) async {
    if (_selectedProviderId != provider['id'] ||
        _scheduleState.selectedDate == null ||
        _scheduleState.selectedTimeSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione um horário antes de continuar.'),
        ),
      );
      return;
    }

    setState(() => _preparingInlinePix = true);
    try {
      final booking = await _createPendingFixedBookingIntentForSelectedSlot();
      final intentId = booking['intentId'].toString();
      final upfront = (booking['upfront'] as num).toDouble();
      final pix = await _api.loadPixPayload(pendingFixedBookingId: intentId);
      final payload = (pix['payload'] ?? '').toString().trim();
      final image = (pix['encodedImage'] ?? pix['image_url'] ?? '')
          .toString()
          .trim();
      final fee = double.tryParse('${pix['amount'] ?? ''}') ?? upfront;

      if (payload.isEmpty && image.isEmpty) {
        throw Exception('PIX retornou sem QR ou payload válido.');
      }

      if (!mounted) return;
      setState(() {
        _pendingPixState.intentId = intentId;
        _pendingPixState.payload = payload;
        _pendingPixState.image = image;
        _pendingPixState.fee = fee;
        _pendingPixState.visible = true;
        _pendingPixState.pendingProviderAutoScrollArmed = true;
      });
      await _persistPendingPixState(
        intentId: intentId,
        provider: provider,
        payload: payload,
        image: image,
        fee: fee,
      );
      _startPendingPixWatcher(intentId);
      if (!mounted) return;
      _restorePendingProviderCardIfVisible();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIX carregado no card do horário escolhido.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao preparar o PIX do agendamento: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _preparingInlinePix = false);
      }
    }
  }

  void _nextStep() async {
    // Passo 1: Descrição/Detalhes
    if (_currentStep == 1) {
      if (_descriptionController.text.trim().isEmpty) {
        _descriptionController.text = "Agendamento simples";
      }

      // Se já temos um prestador (veio do perfil), pulamos a escolha e vamos para Agenda
      if (_selectedProviderId != null) {
        setState(() {
          _currentStep = 3; // Pula para Agenda
          _fetchSlots();
        });
      } else {
        setState(() {
          _currentStep = 2; // Vai para Escolha de Prestador
        });
        if (_selectedProfession != null) {
          _fetchProviders(_selectedProfession!);
        }
      }
      return;
    }

    // Passo 2: Escolha de Prestador
    if (_currentStep == 2) {
      if (_selectedProviderId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor, selecione um profissional.'),
          ),
        );
        return;
      }
      setState(() {
        _currentStep = 3;
        _fetchSlots();
      });
      return;
    }

    // Passo 3: Agenda
    if (_currentStep == 3) {
      if (_scheduleState.selectedDate == null ||
          _scheduleState.selectedTimeSlot == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, escolha data e horário.')),
        );
        return;
      }
      final provider = _providerSearchState.providers.firstWhere(
        (p) => int.tryParse('${p['id']}') == _selectedProviderId,
        orElse: () => {},
      );
      if (provider.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prestador não encontrado.')),
        );
        return;
      }
      final confirmed = await _openFixedBookingReviewScreen(provider);
      if (!confirmed || !mounted) return;
      await _confirmExpandedProviderSchedule(provider);
      return;
    }
  }

  void _prevStep() {
    if (_currentStep > 1) {
      setState(() {
        // Se estamos na Agenda (3) e viemos de um perfil, volta para Detalhes (1)
        if (_currentStep == 3 && widget.initialProviderId != null) {
          _currentStep = 1;
        } else {
          _currentStep--;
        }
      });
    } else {
      context.go('/home');
    }
  }

  void _onDescriptionChanged(String _) {
    setState(() {
      _selectedProviderId = null;
      _providerSearchState.providers = [];
      _providerSearchState.unavailableProviders = [];
      _providerSearchState.pendingProviders.clear();
      _providerSearchState.pendingUnavailableProviders.clear();
      _providerSearchState.expandedProviderId = null;
    });
    _aiDebounce?.cancel();
    _aiDebounce = Timer(const Duration(milliseconds: 1000), _classifyAi);
  }

  void _handleHomeStyleQueryChanged(String rawQuery) {
    final query = rawQuery;
    if (_descriptionController.text != query) {
      _descriptionController.text = query;
    }

    if (query.trim().isEmpty) {
      _aiDebounce?.cancel();
      setState(() {
        _selectedProviderId = null;
        _providerSearchState.providers = [];
        _providerSearchState.unavailableProviders = [];
        _providerSearchState.pendingProviders.clear();
        _providerSearchState.pendingUnavailableProviders.clear();
        _providerSearchState.expandedProviderId = null;
        _selectedProfession = null;
        _aiProfessionName = null;
        _aiTaskId = null;
        _aiTaskName = null;
        _aiTaskPrice = null;
      });
      return;
    }

    _onDescriptionChanged(query);
  }

  Future<void> _handleHomeStyleSuggestionSelected(
    Map<String, dynamic> suggestion,
  ) async {
    final query = (suggestion['task_name'] ?? suggestion['name'] ?? '')
        .toString()
        .trim();
    if (query.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _descriptionController.text = query;
      _selectedProfession =
          (suggestion['profession_name'] ?? _selectedProfession)?.toString();
      _aiProfessionName = (suggestion['profession_name'] ?? _aiProfessionName)
          ?.toString();
      _aiServiceType = (suggestion['service_type'] ?? _aiServiceType)
          ?.toString();
      _aiCategoryId = int.tryParse(
        '${suggestion['category_id'] ?? _aiCategoryId ?? ''}',
      );
      _aiTaskId = int.tryParse(
        '${suggestion['task_id'] ?? suggestion['id'] ?? ''}',
      );
      _aiTaskName = query;
      _aiTaskPrice = double.tryParse(
        '${suggestion['unit_price'] ?? suggestion['price'] ?? _aiTaskPrice ?? ''}',
      );
      _selectedProviderId = null;
      _providerSearchState.providers = [];
      _providerSearchState.unavailableProviders = [];
      _providerSearchState.pendingProviders.clear();
      _providerSearchState.pendingUnavailableProviders.clear();
      _providerSearchState.expandedProviderId = null;
    });

    _dismissKeyboard();
    await _fetchProviders(query);
  }

  Future<void> _handleHomeStyleQuerySubmitted(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return;
    if (_descriptionController.text != query) {
      _descriptionController.text = query;
    }
    _dismissKeyboard();
    await _fetchProviders(query);
  }

  void _handleHomeStyleClose() {
    _aiDebounce?.cancel();
    _dismissKeyboard();
    setState(() {
      _descriptionController.clear();
      _selectedProviderId = null;
      _providerSearchState.providers = [];
      _providerSearchState.unavailableProviders = [];
      _providerSearchState.pendingProviders.clear();
      _providerSearchState.pendingUnavailableProviders.clear();
      _providerSearchState.expandedProviderId = null;
      _selectedProfession = null;
      _aiProfessionName = null;
      _aiTaskId = null;
      _aiTaskName = null;
      _aiTaskPrice = null;
    });
  }

  Future<void> _classifyAi() async {
    if (_descriptionController.text.trim().length < 5) return;
    if (!mounted) return;
    try {
      final r = await _api.classifyService(_descriptionController.text.trim());
      if (!mounted) return;

      if (r['encontrado'] == true) {
        setState(() {
          _aiProfessionName = r['profissao']?.toString();
          _aiServiceType = r['service_type']?.toString();
          _aiCategoryId = int.tryParse(r['category_id']?.toString() ?? '');
          if (r['task_id'] != null || r['task_name'] != null) {
            _aiTaskId = int.tryParse(r['task_id']?.toString() ?? '');
            _aiTaskName = r['task_name']?.toString();
            _aiTaskPrice = double.tryParse(r['price']?.toString() ?? '0');
          } else {
            _aiTaskId = null;
            _aiTaskName = null;
            _aiTaskPrice = null;
          }
        });
      }
      final searchTerm = _effectiveServiceQuery();
      if (searchTerm.trim().isNotEmpty) {
        await _fetchProviders(searchTerm);
      }
    } catch (e) {
      debugPrint('AI Error (fixed): $e');
    }
  }

  Widget _buildFixedPaymentInfoCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            color: AppTheme.darkBlueText,
            size: 26,
          ),
          const SizedBox(height: 10),
          Text(
            'Pague 10% para reservar e 90% direto no salão',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              color: AppTheme.darkBlueText,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A taxa de agendamento garante o horário. O valor principal é pago presencialmente no local.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              color: AppTheme.darkBlueText.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_currentStep) {
      case 1:
        return _buildDescriptionStep();
      case 2:
        return _buildProviderSelectionStep();
      case 3:
        return _buildScheduleStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDescriptionStep() {
    final hasQuery = _descriptionController.text.trim().isNotEmpty;
    final hasVisibleProviders = _providerSearchState.providers.isNotEmpty;
    final showInitialLoadingState =
        hasQuery &&
        !_providerSearchState.providerSearchCompleted &&
        !hasVisibleProviders &&
        (_providerSearchState.loadingProviders ||
            _providerSearchState.loadingMoreProviders ||
            !_providerSearchState.providerSearchHasAnyMatch);
    final showEmptyState =
        hasQuery &&
        _providerSearchState.providerSearchCompleted &&
        !hasVisibleProviders &&
        !_providerSearchState.providerSearchHasAnyMatch &&
        !_providerSearchState.loadingProviders &&
        !_providerSearchState.loadingMoreProviders;
    final compactResultsLayout =
        hasQuery &&
        (_providerSearchState.loadingProviders ||
            _providerSearchState.loadingMoreProviders ||
            hasVisibleProviders ||
            showEmptyState ||
            showInitialLoadingState);
    return FixedBookingDescriptionStep(
      scrollController: _descScrollController,
      searchBar: HomeSearchBar(
        currentAddress: null,
        isEnabled: true,
        autoFocus: true,
        onSuggestionSelected: _handleHomeStyleSuggestionSelected,
        onQueryChanged: _handleHomeStyleQueryChanged,
        onQuerySubmitted: _handleHomeStyleQuerySubmitted,
        onCloseTap: _handleHomeStyleClose,
        seedQuery: _descriptionController.text,
      ),
      hasQuery: hasQuery,
      compactResultsLayout: compactResultsLayout,
      showInitialLoadingState: showInitialLoadingState,
      showEmptyState: showEmptyState,
      providerSearchMessage: _providerSearchState.providerSearchMessage,
      providerSearchDetail: _providerSearchState.providerSearchDetail,
      providerCards: _providerSearchState.providers
          .map(_buildFixedProviderCard)
          .toList(),
      loadingMoreProviders: _providerSearchState.loadingMoreProviders,
      paymentInfoCard: (hasQuery || hasVisibleProviders)
          ? _buildFixedPaymentInfoCard()
          : null,
    );
  }

  Widget _buildFixedProviderCard(Map<String, dynamic> p) {
    final isSelected = _selectedProviderId == p['id'];
    final isExpanded = _providerSearchState.expandedProviderId == p['id'];
    final providerId = int.tryParse(p['id'].toString()) ?? 0;
    if (providerId > 0 &&
        !_loadingProviderAvailability.contains(providerId) &&
        !_resolvedProviderAvailability.contains(providerId)) {
      unawaited(_ensureProviderNextAvailability(p));
    }
    final distanceLabel = p['distance_km'] is num
        ? '${(p['distance_km'] as num).toStringAsFixed(1)} km'
        : 'Distância indisponível';
    final expandedNextSlot = isExpanded
        ? _firstSelectableSlot(_scheduleState.realSlots)
        : null;
    final expandedNextAt = expandedNextSlot != null
        ? _slotStartLocal(expandedNextSlot)
        : null;
    final nextAt =
        expandedNextAt ??
        DateTime.tryParse('${p['next_available_at'] ?? ''}')?.toLocal();
    final nextSlotLabel = nextAt != null
        ? _formatNextAvailableLabel(nextAt)
        : (isExpanded && _scheduleState.loadingSlots)
        ? 'Carregando horários disponíveis...'
        : _loadingProviderAvailability.contains(providerId)
        ? 'Consultando próximo horário livre...'
        : ('${p['unavailability_reason'] ?? ''}'.trim().isNotEmpty)
        ? '${p['unavailability_reason']}'
        : (!_providerSearchState.providerSearchCompleted &&
              (_providerSearchState.loadingProviders ||
                  _providerSearchState.loadingMoreProviders))
        ? 'Consultando agenda...'
        : 'Sem agenda disponível';
    final selectedPrice =
        _aiTaskPrice ??
        double.tryParse(
          '${_selectedService?['price'] ?? _selectedService?['unit_price'] ?? ''}',
        ) ??
        _priceEstimated;
    final serviceLabel = _serviceLabelForProvider(p);

    return AnimatedContainer(
      key: _providerCardKeyFor(providerId),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
      margin: const EdgeInsets.only(bottom: 16, left: 2, right: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isExpanded
                ? AppTheme.primaryBlue.withValues(alpha: 0.12)
                : Colors.black12,
            blurRadius: isExpanded ? 18 : 10,
            offset: Offset(0, isExpanded ? 8 : 4),
          ),
        ],
      ),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isExpanded
                ? AppTheme.primaryBlue.withValues(alpha: 0.28)
                : isSelected
                ? AppTheme.primaryYellow
                : Colors.grey.shade100,
            width: isExpanded ? 2 : 1.6,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _toggleProviderExpansion(p),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildProviderAvatar(
                        avatarUrl: p['avatar_url']?.toString(),
                        size: 62,
                        radius: 16,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            p['commercial_name'] ??
                                p['full_name'] ??
                                'Salão parceiro',
                            style: TextStyle(
                              color: AppTheme.darkBlueText,
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          p['address'] ?? 'Endereço não informado',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.near_me_outlined,
                        size: 15,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          distanceLabel,
                          style: TextStyle(
                            color: Colors.grey.shade800,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 15,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          nextSlotLabel,
                          style: TextStyle(
                            color: Colors.grey.shade800,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Serviço e valor',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              serviceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppTheme.darkBlueText,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'R\$ ${selectedPrice.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: AppTheme.primaryBlue,
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 44,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: isExpanded
                                ? AppTheme.primaryYellow
                                : AppTheme.primaryBlue,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Center(
                              child: Text(
                                isExpanded ? 'Fechar' : 'Agendar',
                                style: TextStyle(
                                  color: isExpanded
                                      ? AppTheme.darkBlueText
                                      : Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isSelected) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: AppTheme.primaryYellow,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Salão selecionado',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SizeTransition(
                          sizeFactor: animation,
                          axisAlignment: -1,
                          child: child,
                        ),
                      );
                    },
                    child: isExpanded
                        ? Padding(
                            key: ValueKey('expanded-$providerId'),
                            padding: const EdgeInsets.only(top: 16),
                            child: _buildExpandedScheduleCard(p),
                          )
                        : const SizedBox.shrink(key: ValueKey('collapsed')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedScheduleCard(Map<String, dynamic> provider) {
    final isPixReadyForProvider =
        _pendingPixState.visible &&
        _pendingPixState.intentId != null &&
        _selectedProviderId == provider['id'];
    return FixedBookingExpandedScheduleCard(
      isPixReadyForProvider: isPixReadyForProvider,
      isSelectedProvider: _selectedProviderId == provider['id'],
      selectedDate: _scheduleState.selectedDate,
      selectedTimeSlot: _scheduleState.selectedTimeSlot,
      realSlots: _scheduleState.realSlots,
      loadingSlots: _scheduleState.loadingSlots,
      preparingInlinePix: _preparingInlinePix,
      changingPendingSchedule: _changingPendingSchedule,
      pendingPixPayload: _pendingPixState.payload ?? '',
      pendingPixImage: _pendingPixState.image ?? '',
      pendingPixFee: _pendingPixState.fee,
      pendingPixSectionKey: isPixReadyForProvider
          ? _pendingPixSectionKey
          : null,
      onConfirmSchedule: () => _confirmExpandedProviderSchedule(provider),
      onChangePendingSchedule: () => _changePendingSchedule(provider),
      onDateSelected: (day) {
        setState(() {
          _scheduleState.selectedDate = day;
          _scheduleState.selectedTimeSlot = null;
        });
        _fetchSlots();
      },
      onTimeSlotSelected: (timeStr) {
        setState(() {
          _scheduleState.selectedTimeSlot = timeStr;
        });
      },
    );
  }

  Widget _buildProviderAvatar({
    required String? avatarUrl,
    required double size,
    required double radius,
  }) {
    final url = avatarUrl?.trim() ?? '';
    if (url.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: Colors.grey.shade200,
        ),
        child: Icon(Icons.storefront, color: Colors.grey, size: size * 0.44),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        cacheWidth: (size * 2).round(),
        cacheHeight: (size * 2).round(),
        errorBuilder: (_, __, ___) {
          return Container(
            width: size,
            height: size,
            color: Colors.grey.shade200,
            child: Icon(
              Icons.storefront,
              color: Colors.grey,
              size: size * 0.44,
            ),
          );
        },
      ),
    );
  }

  Widget _buildScheduleStep() {
    final provider = _providerSearchState.providers.firstWhere(
      (p) => int.tryParse(p['id'].toString()) == _selectedProviderId,
      orElse: () => {},
    );
    if ((provider['address'] == null ||
            provider['address'] == 'Endereço não informado') &&
        provider['latitude'] != null &&
        !_fetchedAddresses.contains(provider['id'])) {
      _fetchedAddresses.add(provider['id']);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchAddressFromCoordinates(provider);
      });
    }

    final providerName =
        (provider['commercial_name'] ?? provider['full_name'] ?? 'Profissional')
            .toString();
    String? distanceLabel;
    String? etaLabel;
    if (_userPosition != null &&
        provider['latitude'] != null &&
        provider['longitude'] != null) {
      final distInMeters = Geolocator.distanceBetween(
        _userPosition!.latitude,
        _userPosition!.longitude,
        double.tryParse(provider['latitude'].toString()) ?? 0,
        double.tryParse(provider['longitude'].toString()) ?? 0,
      );
      final distKm = distInMeters / 1000;
      final timeMin = (distKm / 30 * 60).round();
      distanceLabel = '${distKm.toStringAsFixed(1)} km';
      etaLabel = '~$timeMin min';
    }

    return KeyedSubtree(
      key: _scheduleKey,
      child: FixedBookingScheduleStep(
        providerName: providerName,
        providerAvatarUrl: provider['avatar_url']?.toString(),
        providerAddress:
            provider['address'] ??
            (provider['latitude'] != null
                ? "Lat: ${provider['latitude']}, Lon: ${provider['longitude']}"
                : 'Endereço não informado'),
        providerRatingLabel: provider['rating']?.toString(),
        reviewsCount: int.tryParse('${provider['reviews_count'] ?? 0}') ?? 0,
        distanceLabel: distanceLabel,
        etaLabel: etaLabel,
        selectedDate: _scheduleState.selectedDate,
        selectedTimeSlot: _scheduleState.selectedTimeSlot,
        realSlots: _scheduleState.realSlots,
        loadingSlots: _scheduleState.loadingSlots,
        onConfirm: _nextStep,
        onDateChanged: (date) {
          setState(() {
            _scheduleState.selectedDate = date;
            _scheduleState.selectedTimeSlot = null;
          });
          _fetchSlots();
        },
        onTimeSlotSelected: (timeStr) {
          setState(() {
            _scheduleState.selectedTimeSlot = timeStr;
          });
        },
      ),
    );
  }

  Widget _buildProviderSelectionStep() {
    final items = _providerSearchState.providers.map((p) {
      final isSelected = _selectedProviderId == p['id'];
      final providerId = int.tryParse('${p['id'] ?? ''}') ?? 0;
      if (providerId > 0 &&
          '${p['next_available_at'] ?? ''}'.trim().isEmpty &&
          !_loadingProviderAvailability.contains(providerId) &&
          !_resolvedProviderAvailability.contains(providerId)) {
        unawaited(_ensureProviderNextAvailability(p));
      }
      final distanceLabel = p['distance_km'] is num
          ? '${(p['distance_km'] as num).toStringAsFixed(1)} km'
          : 'Distância indisponível';
      final nextAt = DateTime.tryParse(
        '${p['next_available_at'] ?? ''}',
      )?.toLocal();
      final nextSlotLabel = nextAt != null
          ? _formatNextAvailableLabel(nextAt)
          : _loadingProviderAvailability.contains(providerId)
          ? 'Consultando próximo horário livre...'
          : ('${p['unavailability_reason'] ?? ''}'.trim().isNotEmpty)
          ? '${p['unavailability_reason']}'
          : 'Sem agenda disponível';
      final selectedPrice =
          _aiTaskPrice ??
          double.tryParse(
            '${_selectedService?['price'] ?? _selectedService?['unit_price'] ?? ''}',
          ) ??
          _priceEstimated;
      final serviceLabel = _serviceLabelForProvider(p);

      return FixedBookingProviderSelectionItem(
        providerName: (p['commercial_name'] ?? p['full_name'] ?? 'Profissional')
            .toString(),
        providerAddress: (p['address'] ?? 'Endereço não informado').toString(),
        distanceLabel: distanceLabel,
        nextSlotLabel: nextSlotLabel,
        serviceLabel: serviceLabel,
        selectedPrice: selectedPrice,
        avatarUrl: p['avatar_url']?.toString(),
        isSelected: isSelected,
        onTap: () {
          final nextSlot = p['next_available_slot'] is Map
              ? Map<String, dynamic>.from(p['next_available_slot'] as Map)
              : null;
          final slotStart = nextSlot != null ? _slotStartLocal(nextSlot) : null;
          setState(() {
            _selectedProviderId = int.tryParse(p['id'].toString());
            _latitude = double.tryParse(p['latitude']?.toString() ?? '');
            _longitude = double.tryParse(p['longitude']?.toString() ?? '');
            _address = p['address']?.toString();
            _addressController.text = _address ?? '';
            if (slotStart != null) {
              _scheduleState.selectedDate = DateTime(
                slotStart.year,
                slotStart.month,
                slotStart.day,
              );
              _scheduleState.selectedTimeSlot =
                  '${slotStart.hour.toString().padLeft(2, '0')}:${slotStart.minute.toString().padLeft(2, '0')}';
            }
          });
          _nextStep();
        },
      );
    }).toList();

    return FixedBookingProviderSelectionStep(
      serviceQuery: _effectiveServiceQuery(),
      loadingProviders: _providerSearchState.loadingProviders,
      items: items,
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (MediaQuery.viewInsetsOf(context).bottom > 0) {
          _dismissKeyboard();
          return false;
        }
        _prevStep();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(
            'Estética e Beleza',
            style: TextStyle(
              color: AppTheme.darkBlueText,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          centerTitle: true,
          backgroundColor: AppTheme.primaryYellow,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: AppTheme.darkBlueText),
            onPressed: _prevStep,
          ),
        ),
        body: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _dismissKeyboard,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Column(
                children: [
                  if (_currentStep > 1) ...[
                    LinearProgressIndicator(
                      value: _currentStep / 3,
                      color: AppTheme.darkBlueText,
                      backgroundColor: Colors.grey[200],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Expanded(child: _buildContent()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
