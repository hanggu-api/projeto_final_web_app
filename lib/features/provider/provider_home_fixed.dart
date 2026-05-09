import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/data_gateway.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/logger.dart';
import '../../features/shared/chat_screen.dart';
import '../../domains/scheduling/scheduling.dart';
import '../../integrations/supabase/scheduling/supabase_scheduling_repository.dart';
import '../../services/api_service.dart';
import '../../services/media_service.dart';
import '../../services/notification_service.dart';
import '../../services/remote_theme_service.dart';
import '../../services/realtime_service.dart';
import '../shared/widgets/notification_dropdown_menu.dart';
import '../../widgets/skeleton_loader.dart';

class ProviderHomeFixed extends StatefulWidget {
  const ProviderHomeFixed({super.key});

  @override
  State<ProviderHomeFixed> createState() => _ProviderHomeFixedState();
}

class _ProviderSlotVisualState {
  final Color borderColor;
  final Color textColor;
  final Color backgroundColor;
  final Color timeColor;
  final String statusLabel;
  final String? contextTitle;
  final String? contextSubtitle;
  final String? badgeText;
  final Color badgeBackground;
  final Color badgeForeground;
  final bool opensDetails;
  final bool opensCreateModal;
  final bool showsChatShortcut;

  const _ProviderSlotVisualState({
    required this.borderColor,
    required this.textColor,
    required this.backgroundColor,
    required this.timeColor,
    required this.statusLabel,
    required this.contextTitle,
    required this.contextSubtitle,
    required this.badgeText,
    required this.badgeBackground,
    required this.badgeForeground,
    required this.opensDetails,
    required this.opensCreateModal,
    required this.showsChatShortcut,
  });
}

class _ProviderGeneratedScheduleResult {
  final List<Map<String, dynamic>> slots;
  final int configCount;
  final bool hasAnyConfig;
  final bool hasConfigForDay;
  final bool usedLegacyFallback;

  const _ProviderGeneratedScheduleResult({
    required this.slots,
    required this.configCount,
    required this.hasAnyConfig,
    required this.hasConfigForDay,
    required this.usedLegacyFallback,
  });
}

class _ProviderIdentitySnapshot {
  final String? authUid;
  final String? profileSupabaseUid;
  final String? providerUserId;
  final String? providerName;
  final double? providerLat;
  final double? providerLon;

  const _ProviderIdentitySnapshot({
    required this.authUid,
    required this.profileSupabaseUid,
    required this.providerUserId,
    required this.providerName,
    required this.providerLat,
    required this.providerLon,
  });
}

class _ProviderHomeFixedState extends State<ProviderHomeFixed>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _media = MediaService();
  late final SchedulingRepository _scheduling = SupabaseSchedulingRepository();
  Uint8List? _avatarBytes;
  String? _userName;
  String? _currentUserId;
  double? _providerLat;
  double? _providerLon;
  final Set<String> _notifiedWithin500m = <String>{};
  final Map<String, String> _lastServiceStatusById = <String, String>{};
  bool _hasScheduleSnapshot = false;
  bool _isUploadingAvatar = false;

  // Schedule State
  List<Map<String, dynamic>> _slots = [];
  Timer? _slotRefreshTimer;
  Timer? _scheduleRefreshDebounceTimer;
  StreamSubscription? _realtimeSub;
  bool _loadingSlots = true;
  bool _isBootstrappingIdentity = true;
  bool _isRefreshingSlots = false;
  bool _isAutoAdvancingAgendaDate = false;
  bool _hasConfirmedScheduleConfig = false;
  bool _scheduleDataIncomplete = false;
  bool _showClosedHoursForToday = false;
  bool _hasBootstrappedAgendaDate = false;
  String? _lastAgendaWarning;
  String? _lastAgendaEmptyReason;
  String? _lastProfileLoadError;
  DateTime? _lastRealtimeRefreshToastAt;
  DateTime? _lastScheduleErrorToastAt;
  DateTime _selectedDate = DateTime.now().toLocal();
  int _scheduleRequestVersion = 0;
  final Map<String, List<Map<String, dynamic>>> _scheduleSnapshotByDate = {};
  String? _pendingSlotKey;
  Timer? _pendingSlotCommitTimer;
  final List<Timer> _pendingHapticTimers = [];
  late final AnimationController _slotTouchFxController;

  // Notification State
  final ValueNotifier<List<Map<String, dynamic>>> _notificationsVN =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  @override
  void initState() {
    super.initState();
    _slotTouchFxController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _checkLocationPermission();
    _loadData();
    _setupRealtimeListener();
  }

  @override
  void dispose() {
    _cancelPendingSlotConfirmation();
    _slotTouchFxController.dispose();
    _slotRefreshTimer?.cancel();
    _scheduleRefreshDebounceTimer?.cancel();
    _realtimeSub?.cancel();
    _notificationsVN.dispose();
    RealtimeService().stopLocationUpdates();
    super.dispose();
  }

  String _slotKey(Map<String, dynamic> slot) =>
      '${slot['start_time']}_${slot['end_time']}';

  String _scheduleDateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _selectAgendaDate(
    DateTime date, {
    bool keepClosedHoursForToday = false,
  }) {
    final normalized = DateTime(date.year, date.month, date.day).toLocal();
    final nowLocal = DateTime.now().toLocal();
    final canKeepClosedHours =
        keepClosedHoursForToday && _isSameDay(normalized, nowLocal);
    setState(() {
      _selectedDate = normalized;
      _showClosedHoursForToday = canKeepClosedHours;
      _hasBootstrappedAgendaDate = true;
    });
  }

  void _applyAgendaIdentitySnapshot(_ProviderIdentitySnapshot snapshot) {
    _currentUserId = snapshot.providerUserId;
    _userName = snapshot.providerName;
    _providerLat = snapshot.providerLat;
    _providerLon = snapshot.providerLon;
    _logAgendaState('identity_resolved', {
      'authUid': snapshot.authUid,
      'profileSupabaseUid': snapshot.profileSupabaseUid,
      'providerUserId': snapshot.providerUserId,
      'providerName': snapshot.providerName,
    });
  }

  Future<List<Map<String, dynamic>>> _buildAgendaPreviewForDate(
    int providerId,
    DateTime displayDate,
  ) async {
    if (_currentUserId == null) return const <Map<String, dynamic>>[];

    final rawAppointmentSlots = await _scheduling.getProviderSlots(
      int.parse(_currentUserId!),
      date: _scheduleDateKey(displayDate),
    );
    final generatedResult = await _generateSlotsFromSchedule(
      providerId,
      displayDate,
    );

    final mergedSlots = rawAppointmentSlots
        .map((slot) => Map<String, dynamic>.from(slot))
        .toList();

    for (final generated in generatedResult.slots) {
      final hasConflict = mergedSlots.any((existing) {
        try {
          final existingStart = DateTime.parse(
            existing['start_time'].toString(),
          );
          final existingEnd = DateTime.parse(existing['end_time'].toString());
          final newStart = DateTime.parse(generated['start_time'].toString());
          final newEnd = DateTime.parse(generated['end_time'].toString());
          return newStart.isBefore(existingEnd) &&
              existingStart.isBefore(newEnd);
        } catch (_) {
          return false;
        }
      });
      if (!hasConflict) {
        mergedSlots.add(Map<String, dynamic>.from(generated));
      }
    }

    _sortSlotsInPlace(mergedSlots);
    return mergedSlots;
  }

  Future<DateTime> _resolvePreferredAgendaDate(
    int providerId, {
    bool includeToday = true,
  }) async {
    final today = DateTime.now().toLocal();

    if (includeToday) {
      final todayPreview = await _buildAgendaPreviewForDate(providerId, today);
      final visibleToday = _visibleSlotsForDate(todayPreview, today);
      if (visibleToday.isNotEmpty) {
        return DateTime(today.year, today.month, today.day);
      }
    }

    final nextDate = await _findNextConfiguredWorkingDate();
    if (nextDate != null) {
      return DateTime(nextDate.year, nextDate.month, nextDate.day);
    }

    return DateTime(today.year, today.month, today.day);
  }

  Future<void> _handleTodayTabTap() async {
    final today = DateTime.now().toLocal();
    final providerId = int.tryParse(_currentUserId ?? '');
    if (providerId == null || providerId <= 0) {
      _selectAgendaDate(today);
      await _loadSchedule(today, silent: true, suppressUserWarnings: true);
      return;
    }

    final preferredDate = await _resolvePreferredAgendaDate(providerId);
    if (!mounted) return;

    _selectAgendaDate(preferredDate);
    await _loadSchedule(
      preferredDate,
      silent: _isSameDay(preferredDate, today),
      suppressUserWarnings: true,
    );
  }

  Future<DateTime?> _findNextConfiguredWorkingDate() async {
    final providerId = int.tryParse(_currentUserId ?? '');
    if (providerId == null || providerId <= 0) return null;

    final configs = (await _scheduling.getScheduleConfig(
      providerId,
    )).map((c) => c.toMap()).toList();
    final enabledDays = configs
        .where((conf) => SlotGenerator.isScheduleEnabled(conf))
        .map((conf) {
          if (conf['day_of_week'] is int) return conf['day_of_week'] as int;
          return int.tryParse('${conf['day_of_week'] ?? ''}');
        })
        .whereType<int>()
        .toSet();

    if (enabledDays.isEmpty) return null;

    final start = DateTime.now().toLocal();
    for (int offset = 1; offset <= 30; offset++) {
      final candidate = DateTime(
        start.year,
        start.month,
        start.day,
      ).add(Duration(days: offset));
      final candidateDay = candidate.weekday % 7;
      if (enabledDays.contains(candidateDay)) {
        return candidate;
      }
    }

    return null;
  }

  Future<void> _advanceToNextWorkingDay({bool showNotFoundToast = true}) async {
    if (_isAutoAdvancingAgendaDate) return;
    if (mounted) {
      setState(() {
        _isAutoAdvancingAgendaDate = true;
        _loadingSlots = false;
        _isRefreshingSlots = true;
        _scheduleDataIncomplete = false;
        _lastAgendaWarning = null;
      });
    }

    final nextDate = await _findNextConfiguredWorkingDate();
    if (!mounted) return;
    if (nextDate == null) {
      setState(() {
        _isAutoAdvancingAgendaDate = false;
        _isRefreshingSlots = false;
      });
      if (showNotFoundToast) {
        _showToast(
          'Não encontramos um próximo dia útil configurado.',
          backgroundColor: Colors.orange[800],
        );
      }
      return;
    }

    _selectAgendaDate(nextDate);
    await _loadSchedule(nextDate, silent: false, suppressUserWarnings: true);
    if (mounted) {
      setState(() {
        _isAutoAdvancingAgendaDate = false;
      });
    }
  }

  Future<void> _jumpToNextWorkingDay() async {
    await _advanceToNextWorkingDay(showNotFoundToast: true);
  }

  void _scheduleAutoAdvanceToNextWorkingDay() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!_isSameDay(_selectedDate, DateTime.now().toLocal())) return;
      await _advanceToNextWorkingDay(showNotFoundToast: false);
    });
  }

  void _sortSlotsInPlace(List<Map<String, dynamic>> slots) {
    slots.sort((a, b) {
      final tA = DateTime.tryParse('${a['start_time'] ?? ''}');
      final tB = DateTime.tryParse('${b['start_time'] ?? ''}');
      if (tA == null || tB == null) return 0;
      return tA.compareTo(tB);
    });
  }

  List<Map<String, dynamic>> _visibleSlotsForDate(
    List<Map<String, dynamic>> slots,
    DateTime selectedDate, {
    bool showClosedHoursForToday = false,
  }) {
    final nowLocal = DateTime.now().toLocal();
    final isToday = _isSameDay(selectedDate, nowLocal);

    if (showClosedHoursForToday && isToday) {
      return List<Map<String, dynamic>>.from(slots);
    }

    return slots.where((slot) {
      final endTimeStr = slot['end_time']?.toString();
      if (endTimeStr == null) return false;
      final end = DateTime.tryParse(endTimeStr);
      if (end == null) return false;

      if (!isToday) return true;

      final status = (slot['status'] ?? 'free').toString().toLowerCase();
      if (status != 'free') return true;

      return end.isAfter(nowLocal);
    }).toList();
  }

  List<Map<String, dynamic>> _cloneSlots(List<Map<String, dynamic>> slots) =>
      slots.map((slot) => Map<String, dynamic>.from(slot)).toList();

  void _storeScheduleSnapshot(
    String dateKey,
    List<Map<String, dynamic>> slots,
  ) {
    if (slots.isEmpty) return;
    _scheduleSnapshotByDate[dateKey] = _cloneSlots(slots);
  }

  List<Map<String, dynamic>>? _snapshotForDate(String dateKey) {
    final snapshot = _scheduleSnapshotByDate[dateKey];
    if (snapshot == null || snapshot.isEmpty) return null;
    return _cloneSlots(snapshot);
  }

  void _logAgendaState(String stage, Map<String, Object?> payload) {
    debugPrint('🗓️ [ProviderHomeFixed][$stage] ${jsonEncode(payload)}');
  }

  void _showScheduleRefreshWarning(String message) {
    final now = DateTime.now();
    final shouldShowToast =
        _lastScheduleErrorToastAt == null ||
        now.difference(_lastScheduleErrorToastAt!) >
            const Duration(seconds: 15);
    if (!shouldShowToast) return;
    _lastScheduleErrorToastAt = now;
    _showToast(
      message,
      backgroundColor: Colors.orange[800],
      duration: const Duration(seconds: 3),
    );
  }

  void _replaceSlotLocally(
    Map<String, dynamic> nextSlot, {
    String? previousKey,
  }) {
    final targetKey = previousKey ?? _slotKey(nextSlot);
    final updated = List<Map<String, dynamic>>.from(_slots);
    final index = updated.indexWhere((slot) => _slotKey(slot) == targetKey);
    if (index >= 0) {
      updated[index] = nextSlot;
    } else {
      updated.add(nextSlot);
    }
    _sortSlotsInPlace(updated);
    _storeScheduleSnapshot(_scheduleDateKey(_selectedDate), updated);
    if (!mounted) return;
    setState(() => _slots = updated);
  }

  Map<String, dynamic> _buildOptimisticBusySlot(Map<String, dynamic> slot) {
    return {
      ...slot,
      'status': 'booked',
      'service_status': slot['service_status'] ?? 'booked',
      'is_manual_block': true,
      'appointment_id':
          slot['appointment_id'] ?? 'optimistic_${_slotKey(slot)}',
    };
  }

  Map<String, dynamic> _buildOptimisticFreeSlot(Map<String, dynamic> slot) {
    final updated = Map<String, dynamic>.from(slot)
      ..['status'] = 'free'
      ..['service_status'] = null
      ..['appointment_id'] = null
      ..['service_id'] = null
      ..['is_manual_block'] = false
      ..remove('hold_status')
      ..remove('is_slot_hold')
      ..remove('client_distance_m');
    return updated;
  }

  void _scheduleAgendaRefresh({
    DateTime? date,
    Duration delay = const Duration(milliseconds: 250),
  }) {
    final targetDate = (date ?? _selectedDate).toLocal();
    _scheduleRefreshDebounceTimer?.cancel();
    _scheduleRefreshDebounceTimer = Timer(delay, () {
      if (!mounted) return;
      unawaited(_loadSchedule(targetDate, silent: true));
    });
  }

  void _showToast(
    String message, {
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 2),
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: duration,
      ),
    );
  }

  void _cancelPendingSlotConfirmation() {
    _pendingSlotCommitTimer?.cancel();
    _pendingSlotCommitTimer = null;
    for (final t in _pendingHapticTimers) {
      t.cancel();
    }
    _pendingHapticTimers.clear();
    _slotTouchFxController.stop();
    if (_pendingSlotKey != null && mounted) {
      setState(() => _pendingSlotKey = null);
    } else {
      _pendingSlotKey = null;
    }
  }

  void _setupRealtimeListener() {
    _realtimeSub = RealtimeService().eventsStream.listen((event) {
      final type = event['type'];
      // Listen for various events that should refresh the schedule
      if (type == 'payment_confirmed' ||
          type == 'service_accepted' ||
          type == 'schedule_update' ||
          type == 'service.status' ||
          type == 'client.arrived' ||
          type == 'client.departing' ||
          type == 'client.departed') {
        if (mounted) {
          final now = DateTime.now();
          final shouldShowToast =
              _lastRealtimeRefreshToastAt == null ||
              now.difference(_lastRealtimeRefreshToastAt!) >
                  const Duration(seconds: 12);
          if (shouldShowToast) {
            _lastRealtimeRefreshToastAt = now;
            _showToast('Agenda atualizada! 📅', backgroundColor: Colors.green);
          }
          _scheduleAgendaRefresh();
        }
      }
    });
  }

  Future<void> _checkLocationPermission() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
    } catch (_) {}
  }

  Future<void> _loadData() async {
    AppLogger.debug('[_loadData] provider_home_fixed init');
    _loadAvatar();
    _loadProfile();
    // Real-time notifications handled by DataGateway
  }

  Future<void> _loadAvatar() async {
    try {
      final bytes = await _media.loadMyAvatarBytes();
      if (!mounted) return;
      setState(() {
        _avatarBytes = bytes;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _avatarBytes = null;
      });
    }
  }

  Future<void> _refreshAvatarAfterUpload() async {
    try {
      _api.invalidateMediaBytesCache();
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await _loadAvatar();
      if (!mounted) return;
      setState(() {});
    } catch (_) {}
  }

  Future<void> _editAvatar() async {
    if (_isUploadingAvatar) return;

    if (kIsWeb) {
      final res = await _media.pickImageWeb();
      if (res == null || res.files.isEmpty || res.files.first.bytes == null) {
        return;
      }
      final file = res.files.first;
      final ext = file.extension?.toLowerCase();
      final mime = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
          ? 'image/webp'
          : 'image/jpeg';
      setState(() => _isUploadingAvatar = true);
      try {
        await _media.uploadAvatarBytes(file.bytes!, file.name, mime);
        await _refreshAvatarAfterUpload();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto de perfil atualizada com sucesso!'),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao atualizar foto: $e')));
      } finally {
        if (mounted) setState(() => _isUploadingAvatar = false);
      }
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Usar câmera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final xfile = await _media.pickImageMobile(source);
    if (xfile == null) return;

    final bytes = await xfile.readAsBytes();
    final ext = xfile.name.split('.').last.toLowerCase();
    final mime = ext == 'png'
        ? 'image/png'
        : ext == 'webp'
        ? 'image/webp'
        : 'image/jpeg';
    setState(() => _isUploadingAvatar = true);
    try {
      await _media.uploadAvatarBytes(bytes, xfile.name, mime);
      await _refreshAvatarAfterUpload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto de perfil atualizada com sucesso!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao atualizar foto: $e')));
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _loadProfile() async {
    const maxAttempts = 3;
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        _logAgendaState('bootstrap_identity_pending', {
          'attempt': attempt,
          'cachedUserId': _api.userId,
          'cachedRole': _api.role,
          'cachedIsFixedLocation': _api.isFixedLocation,
          'authUid': Supabase.instance.client.auth.currentUser?.id,
        });
        await _api.loadToken();
        final user = await _api.getMyProfile();
        final authUid = Supabase.instance.client.auth.currentUser?.id.trim();
        final providerUserId = user['id']?.toString();
        final profileSupabaseUid = user['supabase_uid']?.toString().trim();
        final providerName = (user['name'] ?? user['full_name'] ?? '')
            .toString()
            .trim();
        final providerLat = _readDouble(
          user['latitude'] ?? user['provider_lat'],
        );
        final providerLon = _readDouble(
          user['longitude'] ?? user['provider_lon'],
        );

        if (!mounted) return;

        setState(() {
          _applyAgendaIdentitySnapshot(
            _ProviderIdentitySnapshot(
              authUid: authUid,
              profileSupabaseUid: profileSupabaseUid,
              providerUserId: providerUserId,
              providerName: providerName.isEmpty ? null : providerName,
              providerLat: providerLat,
              providerLon: providerLon,
            ),
          );
          _isBootstrappingIdentity = false;
          _lastProfileLoadError = null;
        });

        if (user['id'] != null) {
          AppLogger.debug(
            '[_loadProfile] provider_home_fixed userId=${user['id']} name=${user['name'] ?? user['full_name']} authUid=${authUid ?? "-"} profileSupabaseUid=${profileSupabaseUid ?? "-"}',
          );
          final userId = user['id'].toString();
          final providerId = int.tryParse(userId);
          RealtimeService().authenticate(userId);
          RealtimeService().stopLocationUpdates();
          DateTime initialDate;
          try {
            initialDate = providerId != null && providerId > 0
                ? await _resolvePreferredAgendaDate(providerId)
                : DateTime.now().toLocal();
          } catch (e) {
            _logAgendaState('schedule_preview_failed', {
              'attempt': attempt,
              'providerId': providerId,
              'error': e.toString(),
              'authUid': authUid,
            });
            if (!mounted) return;
            setState(() {
              _loadingSlots = false;
              _isBootstrappingIdentity = false;
              _hasBootstrappedAgendaDate = true;
              _hasConfirmedScheduleConfig = false;
              _scheduleDataIncomplete = true;
              _lastAgendaEmptyReason = 'schedule_preview_failed';
              _lastProfileLoadError = e.toString();
              _lastAgendaWarning =
                  'Nao foi possivel carregar a agenda agora. Tente atualizar.';
            });
            return;
          }
          if (!mounted) return;
          _selectAgendaDate(initialDate);
          unawaited(_loadSchedule(initialDate, suppressUserWarnings: true));
          _slotRefreshTimer?.cancel();
          _slotRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
            _scheduleAgendaRefresh(delay: const Duration(milliseconds: 50));
          });
        }
        return;
      } catch (e) {
        lastError = e;
        _logAgendaState('profile_query_failed', {
          'attempt': attempt,
          'error': e.toString(),
          'cachedUserId': _api.userId,
          'cachedRole': _api.role,
          'cachedIsFixedLocation': _api.isFixedLocation,
          'authUid': Supabase.instance.client.auth.currentUser?.id,
        });
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 250 * attempt));
        }
      }
    }

    if (mounted) {
      setState(() {
        _loadingSlots = false;
        _isBootstrappingIdentity = false;
        _hasBootstrappedAgendaDate = true;
        _lastAgendaEmptyReason = 'profile_load_failed';
        _lastProfileLoadError = lastError?.toString();
        _lastAgendaWarning =
            'Não foi possível reidratar sua sessão agora. Tente atualizar.';
      });
    }
  }

  double? _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value == null) return null;
    return double.tryParse(value.toString());
  }

  void _notifyClientTravelTransitions(List<Map<String, dynamic>> slots) {
    final currentStatuses = <String, String>{};

    for (final slot in slots) {
      final serviceId =
          slot['service_id']?.toString() ??
          slot['agendamento_servico_id']?.toString() ??
          slot['service_request_id']?.toString() ??
          slot['id']?.toString();
      if (serviceId == null || serviceId.trim().isEmpty) continue;

      final status = (slot['service_status'] ?? slot['status'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      if (status.isEmpty) continue;
      currentStatuses[serviceId] = status;

      final previous = _lastServiceStatusById[serviceId];
      if (!_hasScheduleSnapshot || previous == status) continue;

      if (status == 'client_departing') {
        _showToast(
          'Cliente a caminho do salão 🚶‍♂️',
          backgroundColor: Colors.blue,
        );
        NotificationService().showNotification(
          'Cliente a caminho',
          'O cliente iniciou o deslocamento até o salão.',
        );
      } else if (status == 'client_arrived') {
        _showToast('Cliente chegou ao salão 📍', backgroundColor: Colors.green);
        NotificationService().showNotification(
          'Cliente chegou',
          'O cliente chegou ao local do atendimento.',
        );
      }
    }

    _lastServiceStatusById
      ..clear()
      ..addAll(currentStatuses);
    _hasScheduleSnapshot = true;
  }

  Map<String, dynamic> _enrichSlotWithServiceData(Map<String, dynamic> slot) {
    final enriched = Map<String, dynamic>.from(slot);
    final serviceId = enriched['service_id']?.toString().trim();
    final status = (enriched['service_status'] ?? enriched['status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();

    if ((enriched['status'] ?? '').toString().toLowerCase().trim() == 'busy' ||
        (enriched['status'] ?? '').toString().toLowerCase().trim() ==
            'confirmed' ||
        (enriched['status'] ?? '').toString().toLowerCase().trim() ==
            'scheduled' ||
        (enriched['status'] ?? '').toString().toLowerCase().trim() ==
            'waiting_payment') {
      enriched['status'] = 'booked';
    }

    final clientLat = _readDouble(
      enriched['client_latitude'] ?? enriched['latitude'],
    );
    final clientLon = _readDouble(
      enriched['client_longitude'] ?? enriched['longitude'],
    );
    if (serviceId != null &&
        serviceId.isNotEmpty &&
        clientLat != null &&
        clientLon != null &&
        _providerLat != null &&
        _providerLon != null) {
      final distanceM = Geolocator.distanceBetween(
        _providerLat!,
        _providerLon!,
        clientLat,
        clientLon,
      );
      enriched['client_distance_m'] = distanceM;

      final trackingUpdatedAt = DateTime.tryParse(
        '${enriched['client_tracking_updated_at'] ?? ''}',
      )?.toLocal();
      final trackingIsStale =
          trackingUpdatedAt != null &&
          DateTime.now().difference(trackingUpdatedAt) >
              const Duration(minutes: 2);
      enriched['client_tracking_is_stale'] = trackingIsStale;

      if (status == 'client_departing' &&
          distanceM <= 500 &&
          !_notifiedWithin500m.contains(serviceId)) {
        _notifiedWithin500m.add(serviceId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Cliente a ${distanceM.toStringAsFixed(0)}m do salão 🚶‍♂️',
              ),
              backgroundColor: Colors.blue[700],
            ),
          );
        }
        NotificationService().showNotification(
          'Cliente próximo',
          'Cliente está a menos de 500m do salão',
        );
      }
    }

    return enriched;
  }

  String _normalizedProviderSlotStatus(Map<String, dynamic> slot) {
    final rawStatus = (slot['status'] ?? '').toString().toLowerCase().trim();
    final serviceStatus = (slot['service_status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();

    if (rawStatus == 'lunch') return 'lunch';
    if (serviceStatus == 'client_arrived') return 'client_arrived';
    if (serviceStatus == 'client_departing') return 'client_departing';
    if (serviceStatus == 'waiting_payment' || rawStatus == 'waiting_payment') {
      return 'waiting_payment';
    }

    if (rawStatus == 'booked' ||
        rawStatus == 'busy' ||
        rawStatus == 'confirmed' ||
        rawStatus == 'scheduled') {
      return 'occupied';
    }

    if (rawStatus == 'free') return 'free';
    return rawStatus.isNotEmpty ? rawStatus : 'free';
  }

  bool _slotHasChat(Map<String, dynamic> slot) {
    if (slot['is_manual_block'] == true) return false;
    final serviceId = slot['service_id']?.toString().trim() ?? '';
    return serviceId.isNotEmpty;
  }

  _ProviderSlotVisualState _resolveSlotVisualState(
    Map<String, dynamic> slot, {
    required bool isActuallyNow,
    required bool isPendingConfirmation,
  }) {
    final normalizedStatus = _normalizedProviderSlotStatus(slot);
    final isManualBlock = slot['is_manual_block'] == true;
    final distanceM = _readDouble(slot['client_distance_m']);

    var borderColor = Colors.transparent;
    var textColor = Colors.black87;
    var backgroundColor = Colors.grey[100]!;
    var timeColor = Colors.black;
    var statusLabel = 'Livre';
    String? contextTitle;
    String? contextSubtitle;
    String? badgeText;
    var badgeBackground = Colors.transparent;
    var badgeForeground = Colors.white;
    var opensDetails = false;
    var opensCreateModal = false;
    final clientName = (slot['client_name'] ?? '').toString().trim();
    final procedureName =
        (slot['procedure_name'] ??
                slot['service_profession'] ??
                slot['task_name'] ??
                '')
            .toString()
            .trim();

    switch (normalizedStatus) {
      case 'occupied':
        borderColor = const Color(0xFF1E88E5);
        textColor = const Color(0xFF0D47A1);
        backgroundColor = const Color(0xFFE3F2FD);
        timeColor = const Color(0xFF0D47A1);
        statusLabel = 'Ocupado';
        badgeText = isManualBlock ? 'Manual' : 'Agendado';
        badgeBackground = const Color(0xFF1565C0);
        opensDetails = true;
        contextTitle = isManualBlock
            ? 'Bloqueado manualmente'
            : (clientName.isNotEmpty ? clientName : 'Cliente agendado');
        contextSubtitle = procedureName.isNotEmpty ? procedureName : null;
        break;
      case 'waiting_payment':
        borderColor = const Color(0xFFF9A825);
        textColor = const Color(0xFF8D6E00);
        backgroundColor = const Color(0xFFFFF0B3);
        timeColor = const Color(0xFF8D6E00);
        statusLabel = 'Aguard. Pix';
        badgeText = 'Pagamento';
        badgeBackground = const Color(0xFFF9A825);
        opensDetails = true;
        contextTitle = clientName.isNotEmpty ? clientName : 'Reserva pendente';
        contextSubtitle = procedureName.isNotEmpty
            ? procedureName
            : 'Pagamento pendente';
        break;
      case 'client_departing':
        borderColor = const Color(0xFF1E88E5);
        textColor = Colors.white;
        backgroundColor = const Color(0xFF42A5F5);
        timeColor = Colors.white;
        statusLabel = 'A caminho';
        final trackingIsStale = slot['client_tracking_is_stale'] == true;
        badgeText = trackingIsStale
            ? 'Sinal fraco'
            : distanceM != null
            ? '${distanceM.toStringAsFixed(0)}m'
            : 'Indo';
        badgeBackground = trackingIsStale
            ? const Color(0xFF6D4C41)
            : const Color(0xFF1565C0);
        opensDetails = true;
        contextTitle = clientName.isNotEmpty ? clientName : 'Cliente';
        contextSubtitle = trackingIsStale
            ? 'Rastreamento temporariamente indisponivel'
            : distanceM != null
            ? 'Chega em breve'
            : 'Em deslocamento';
        break;
      case 'client_arrived':
        borderColor = const Color(0xFF2E7D32);
        textColor = Colors.white;
        backgroundColor = const Color(0xFF4CAF50);
        timeColor = Colors.white;
        statusLabel = 'Chegou';
        badgeText = 'No local';
        badgeBackground = const Color(0xFF2E7D32);
        opensDetails = true;
        contextTitle = clientName.isNotEmpty ? clientName : 'Cliente';
        contextSubtitle = 'Aguardando atendimento';
        break;
      case 'lunch':
        borderColor = const Color(0xFFFF9800);
        textColor = const Color(0xFFFF9800);
        backgroundColor = const Color(0xFFFFF7F0);
        timeColor = const Color(0xFFFF9800);
        statusLabel = 'Almoco';
        badgeText = slot['lunch_label']?.toString();
        if (badgeText != null && badgeText.isNotEmpty) {
          badgeBackground = const Color(0xFFFF9800);
        }
        break;
      case 'free':
      default:
        opensCreateModal = true;
        if (isActuallyNow) {
          borderColor = const Color(0xFF4CAF50);
          textColor = const Color(0xFF4CAF50);
          backgroundColor = const Color(0xFFF1FDF1);
          timeColor = const Color(0xFF4CAF50);
          statusLabel = 'AGORA';
          badgeText = 'Disponivel';
          badgeBackground = const Color(0xFF4CAF50);
        }
        break;
    }

    if (isPendingConfirmation) {
      statusLabel = 'Confirmando...';
    }

    return _ProviderSlotVisualState(
      borderColor: borderColor,
      textColor: textColor,
      backgroundColor: backgroundColor,
      timeColor: timeColor,
      statusLabel: statusLabel,
      contextTitle: contextTitle,
      contextSubtitle: contextSubtitle,
      badgeText: badgeText,
      badgeBackground: badgeBackground,
      badgeForeground: badgeForeground,
      opensDetails: opensDetails,
      opensCreateModal: opensCreateModal,
      showsChatShortcut: _slotHasChat(slot) && opensDetails,
    );
  }

  Future<_ProviderGeneratedScheduleResult> _generateSlotsFromSchedule(
    int providerId,
    DateTime displayDate,
  ) async {
    final configResult = await _scheduling.getScheduleConfigResult(providerId);
    final configs = configResult.configs.map((c) => c.toMap()).toList();
    debugPrint(
      '🐞 [_generateSlotsFromSchedule] providerId=$providerId '
      'selectedDate=${_scheduleDateKey(displayDate)} configs=${configs.length} '
      'usedLegacyFallback=${configResult.usedLegacyFallback}',
    );

    if (configs.isEmpty) {
      _logAgendaState('schedule_config_empty', {
        'providerId': providerId,
        'selectedDate': _scheduleDateKey(displayDate),
        'configCount': 0,
        'usedLegacyFallback': configResult.usedLegacyFallback,
      });
      return _ProviderGeneratedScheduleResult(
        slots: const [],
        configCount: 0,
        hasAnyConfig: false,
        hasConfigForDay: false,
        usedLegacyFallback: configResult.usedLegacyFallback,
      );
    }

    final dayIndex = displayDate.weekday % 7;
    final hasConfigForDay = configs.any((c) {
      final d = c['day_of_week'] is int
          ? c['day_of_week'] as int
          : int.tryParse('${c['day_of_week'] ?? ''}') ?? -1;
      return d == dayIndex && SlotGenerator.isScheduleEnabled(c);
    });

    if (!hasConfigForDay) {
      _logAgendaState('schedule_day_without_config', {
        'providerId': providerId,
        'selectedDate': _scheduleDateKey(displayDate),
        'configCount': configs.length,
        'usedLegacyFallback': configResult.usedLegacyFallback,
        'dayIndex': dayIndex,
      });
      return _ProviderGeneratedScheduleResult(
        slots: const [],
        configCount: configs.length,
        hasAnyConfig: true,
        hasConfigForDay: false,
        usedLegacyFallback: configResult.usedLegacyFallback,
      );
    }

    final generatedSlots = const SlotGenerator().generateSlotsForDate(
      providerId: providerId,
      selectedDate: displayDate,
      configsRaw: configs,
      appointmentsList: const [],
    );

    _logAgendaState('schedule_generated', {
      'providerId': providerId,
      'selectedDate': _scheduleDateKey(displayDate),
      'configCount': configs.length,
      'generatedSlotCount': generatedSlots.length,
      'usedLegacyFallback': configResult.usedLegacyFallback,
    });

    return _ProviderGeneratedScheduleResult(
      slots: generatedSlots,
      configCount: configs.length,
      hasAnyConfig: true,
      hasConfigForDay: true,
      usedLegacyFallback: configResult.usedLegacyFallback,
    );
  }

  Future<void> _loadSchedule(
    DateTime displayDate, {
    bool silent = false,
    bool suppressUserWarnings = false,
  }) async {
    if (_currentUserId == null) {
      AppLogger.debug('[_loadSchedule] _currentUserId is null!');
      if (mounted) {
        setState(() {
          _loadingSlots = false;
          _isRefreshingSlots = false;
        });
      }
      return;
    }

    final providerId = int.tryParse(_currentUserId!);
    AppLogger.debug(
      '[_loadSchedule] start providerIdRaw=$_currentUserId selectedDate=${_scheduleDateKey(displayDate)}',
    );
    if (providerId == null || providerId <= 0) {
      AppLogger.debug('[_loadSchedule] invalid providerIdRaw=$_currentUserId');
      _logAgendaState('load_aborted_invalid_provider', {
        'providerIdRaw': _currentUserId,
        'selectedDate': _scheduleDateKey(displayDate),
      });
      if (mounted) {
        setState(() {
          _slots = [];
          _loadingSlots = false;
          _isRefreshingSlots = false;
          _hasConfirmedScheduleConfig = false;
          _scheduleDataIncomplete = true;
          _lastAgendaEmptyReason = 'invalid_provider';
          _lastAgendaWarning = 'Não foi possível identificar o prestador.';
        });
      }
      return;
    }

    final requestVersion = ++_scheduleRequestVersion;
    final targetDateKey = _scheduleDateKey(displayDate);
    final snapshotForDay = _snapshotForDate(targetDateKey);
    final hasSnapshotForDay =
        snapshotForDay != null && snapshotForDay.isNotEmpty;
    final currentDayKey = _scheduleDateKey(_selectedDate);
    final shouldWarmLoadFromSnapshot =
        hasSnapshotForDay && currentDayKey != targetDateKey;
    final hasVisibleGrid =
        shouldWarmLoadFromSnapshot ||
        (currentDayKey == targetDateKey && _slots.isNotEmpty);

    if (mounted) {
      setState(() {
        if (shouldWarmLoadFromSnapshot) {
          _slots = snapshotForDay;
        }
        if (hasVisibleGrid) {
          _loadingSlots = false;
          _isRefreshingSlots = true;
        } else {
          _loadingSlots = true;
          _isRefreshingSlots = false;
        }
      });
    }

    try {
      final rawAppointmentSlots = await _scheduling.getProviderSlots(
        int.parse(_currentUserId!),
        date: targetDateKey,
      );
      if (requestVersion != _scheduleRequestVersion) return;

      debugPrint(
        '🐞 [_loadSchedule] providerId=$providerId targetDate=$targetDateKey '
        'rawAppointmentSlots=${rawAppointmentSlots.length}',
      );
      _logAgendaState('load_inputs', {
        'authUid': Supabase.instance.client.auth.currentUser?.id,
        'currentUserId': _currentUserId,
        'providerId': providerId,
        'selectedDate': targetDateKey,
        'rawAppointmentSlots': rawAppointmentSlots.length,
      });

      final enrichedAppointments = rawAppointmentSlots
          .map(
            (slot) =>
                _enrichSlotWithServiceData(Map<String, dynamic>.from(slot)),
          )
          .toList();
      final generatedResult = await _generateSlotsFromSchedule(
        providerId,
        displayDate,
      );
      if (requestVersion != _scheduleRequestVersion) return;

      final mergedSlots = <Map<String, dynamic>>[];
      mergedSlots.addAll(enrichedAppointments);

      // Evitar duplicar períodos: somente adicionar slots gerados se não há compromisso em mesma janela
      for (final generated in generatedResult.slots) {
        final hasConflict = mergedSlots.any((existing) {
          try {
            final existingStart = DateTime.parse(
              existing['start_time'].toString(),
            );
            final existingEnd = DateTime.parse(existing['end_time'].toString());
            final newStart = DateTime.parse(generated['start_time'].toString());
            final newEnd = DateTime.parse(generated['end_time'].toString());
            return newStart.isBefore(existingEnd) &&
                existingStart.isBefore(newEnd);
          } catch (_) {
            return false;
          }
        });
        if (!hasConflict) {
          mergedSlots.add(generated);
        }
      }

      _sortSlotsInPlace(mergedSlots);

      _notifyClientTravelTransitions(mergedSlots);

      final hasRealNoConfig =
          mergedSlots.isEmpty &&
          enrichedAppointments.isEmpty &&
          !generatedResult.hasConfigForDay;
      final shouldFallbackToSnapshot =
          mergedSlots.isEmpty && hasSnapshotForDay && !hasRealNoConfig;
      final suspiciousEmpty =
          mergedSlots.isEmpty && !hasRealNoConfig && !shouldFallbackToSnapshot;
      final visibleSlotsForCurrentState = _visibleSlotsForDate(
        mergedSlots,
        displayDate,
        showClosedHoursForToday: _showClosedHoursForToday,
      );
      final emptyReason = mergedSlots.isNotEmpty
          ? (visibleSlotsForCurrentState.isEmpty
                ? 'slots_generated_but_filtered'
                : 'slots_available')
          : shouldFallbackToSnapshot
          ? 'snapshot_preserved'
          : hasRealNoConfig
          ? (generatedResult.hasAnyConfig
                ? 'configs_loaded_but_day_disabled'
                : 'configs_empty')
          : suspiciousEmpty
          ? 'load_failed_or_incomplete'
          : 'no_more_slots_today';

      _logAgendaState('load_result', {
        'providerId': providerId,
        'selectedDate': targetDateKey,
        'appointmentCount': enrichedAppointments.length,
        'slotHoldCount': rawAppointmentSlots
            .where(
              (slot) =>
                  (slot['is_slot_hold'] == true) ||
                  ((slot['service_status'] ?? '').toString().toLowerCase() ==
                      'waiting_payment'),
            )
            .length,
        'generatedSlotCount': generatedResult.slots.length,
        'mergedSlotCount': mergedSlots.length,
        'visibleSlotCount': visibleSlotsForCurrentState.length,
        'configCount': generatedResult.configCount,
        'hasAnyConfig': generatedResult.hasAnyConfig,
        'hasConfigForDay': generatedResult.hasConfigForDay,
        'usedLegacyFallback': generatedResult.usedLegacyFallback,
        'hasSnapshotForDay': hasSnapshotForDay,
        'emptyReason': emptyReason,
        'decision': mergedSlots.isNotEmpty
            ? 'commit_fresh_grid'
            : shouldFallbackToSnapshot
            ? 'preserve_snapshot'
            : hasRealNoConfig
            ? 'show_no_config'
            : 'show_incomplete_state',
      });
      debugPrint(
        '🐞 [_loadSchedule] providerId=$providerId date=$targetDateKey '
        'appointments=$enrichedAppointments.length generated=$generatedResult.slots.length '
        'merged=$mergedSlots.length configForDay=$generatedResult.hasConfigForDay '
        'hasAnyConfig=$generatedResult.hasAnyConfig '
        'fallback=$shouldFallbackToSnapshot suspiciousEmpty=$suspiciousEmpty '
        'realNoConfig=$hasRealNoConfig',
      );

      if (mergedSlots.isNotEmpty) {
        _storeScheduleSnapshot(targetDateKey, mergedSlots);
        final visibleSlots = _visibleSlotsForDate(
          mergedSlots,
          displayDate,
          showClosedHoursForToday: _showClosedHoursForToday,
        );
        final shouldAutoAdvanceToNextDay =
            _isSameDay(displayDate, DateTime.now().toLocal()) &&
            visibleSlots.isEmpty &&
            !_showClosedHoursForToday;

        if (shouldAutoAdvanceToNextDay) {
          final nextDate = await _findNextConfiguredWorkingDate();
          if (nextDate != null && !_isSameDay(nextDate, displayDate)) {
            _logAgendaState('auto_advance_off_hours', {
              'providerId': providerId,
              'fromDate': targetDateKey,
              'toDate': _scheduleDateKey(nextDate),
              'reason': 'today_without_available_visible_slots',
            });
            unawaited(_advanceToNextWorkingDay(showNotFoundToast: false));
            return;
          }
        }

        if (mounted) {
          setState(() {
            _slots = mergedSlots;
            _loadingSlots = false;
            _isRefreshingSlots = false;
            _hasConfirmedScheduleConfig = generatedResult.hasAnyConfig;
            _scheduleDataIncomplete = false;
            _lastAgendaEmptyReason = emptyReason;
            _lastAgendaWarning = null;
          });
        }
        return;
      }

      if (shouldFallbackToSnapshot) {
        if (mounted) {
          setState(() {
            _slots = snapshotForDay;
            _loadingSlots = false;
            _isRefreshingSlots = false;
            _hasConfirmedScheduleConfig = true;
            _scheduleDataIncomplete = true;
            _lastAgendaEmptyReason = emptyReason;
            _lastAgendaWarning =
                'Mostrando a última agenda válida enquanto sincronizamos.';
          });
        }
        if (!suppressUserWarnings && !_isAutoAdvancingAgendaDate) {
          _showScheduleRefreshWarning(
            'Atualização parcial: mantendo a última agenda válida.',
          );
        }
        return;
      }

      if (mounted) {
        setState(() {
          _slots = const <Map<String, dynamic>>[];
          _loadingSlots = false;
          _isRefreshingSlots = false;
          _hasConfirmedScheduleConfig = generatedResult.hasAnyConfig;
          _scheduleDataIncomplete = suspiciousEmpty;
          _lastAgendaEmptyReason = emptyReason;
          _lastAgendaWarning = suspiciousEmpty
              ? 'Não foi possível confirmar os horários agora. Tente atualizar.'
              : null;
        });
      }

      if (suspiciousEmpty &&
          !suppressUserWarnings &&
          !_isAutoAdvancingAgendaDate) {
        _showScheduleRefreshWarning(
          'Não foi possível confirmar a agenda agora. Tente atualizar.',
        );
      }
    } catch (e) {
      if (requestVersion != _scheduleRequestVersion) return;
      _logAgendaState('load_error', {
        'providerId': providerId,
        'selectedDate': targetDateKey,
        'error': e.toString(),
        'hasSnapshotForDay': hasSnapshotForDay,
      });
      if (mounted) {
        setState(() {
          if (hasSnapshotForDay) {
            _slots = snapshotForDay;
          } else {
            _slots = const <Map<String, dynamic>>[];
          }
          _loadingSlots = false;
          _isRefreshingSlots = false;
          _hasConfirmedScheduleConfig = hasSnapshotForDay;
          _scheduleDataIncomplete = true;
          _lastAgendaEmptyReason = 'load_exception';
          _lastAgendaWarning = hasSnapshotForDay
              ? 'Mostrando a última agenda válida enquanto a sincronização falha.'
              : 'Agenda indisponível no momento. Tente atualizar novamente.';
        });
      }
      if (!suppressUserWarnings && !_isAutoAdvancingAgendaDate) {
        _showScheduleRefreshWarning(
          hasSnapshotForDay
              ? 'Não foi possível atualizar a agenda. Mantendo a última versão válida.'
              : 'Não foi possível atualizar a agenda agora. Tente novamente.',
        );
      }
    }
  }

  Future<void> _toggleSlotBusy(Map<String, dynamic> slot) async {
    final slotKey = _slotKey(slot);
    final originalSlot = Map<String, dynamic>.from(slot);
    try {
      final start = DateTime.parse(slot['start_time']);
      final end = DateTime.parse(slot['end_time']);
      final status = slot['status']?.toString().toLowerCase() ?? 'free';
      final appointmentId = slot['appointment_id'];
      final isManualBlock = slot['is_manual_block'] == true;

      final isBusyStatus =
          status == 'busy' ||
          status == 'booked' ||
          status == 'confirmed' ||
          status == 'scheduled' ||
          status == 'waiting_payment';

      if (status == 'free') {
        _replaceSlotLocally(
          _buildOptimisticBusySlot(slot),
          previousKey: slotKey,
        );
        await _scheduling.markSlotBusy(
          int.parse(_currentUserId!),
          start,
          endTime: end,
        );
        await _loadSchedule(_selectedDate, silent: true);
      } else if ((isBusyStatus || isManualBlock) && appointmentId != null) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Liberar horário?'),
            content: const Text(
              'Isso removerá o bloqueio/agendamento desse horário. Deseja continuar?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Liberar',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        _replaceSlotLocally(
          _buildOptimisticFreeSlot(slot),
          previousKey: slotKey,
        );
        await _scheduling.deleteAppointment(appointmentId.toString());
        await _loadSchedule(_selectedDate, silent: true);
        _showToast(
          'Horário liberado com sucesso.',
          backgroundColor: Colors.green,
        );
      } else {
        _showToast('Este horário já está ocupado ou agendado.');
      }
    } catch (e) {
      _replaceSlotLocally(originalSlot, previousKey: slotKey);
      if (!mounted) return;
      debugPrint('❌ [Slots] toggle error: $e');
      _showToast(
        'Erro ao atualizar horário. Tente novamente.',
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _showCreateAppointmentModal(Map<String, dynamic> slot) async {
    final providerId = int.tryParse(_currentUserId ?? '');
    if (providerId == null) return;
    final start = DateTime.tryParse((slot['start_time'] ?? '').toString());
    final end = DateTime.tryParse((slot['end_time'] ?? '').toString());
    if (start == null || end == null) return;

    final clientController = TextEditingController();
    final procedureController = TextEditingController();
    final notesController = TextEditingController();
    bool creating = false;
    List<String> procedureSuggestions = const [];

    try {
      final services = await _api.getProviderServices(providerId: providerId);
      procedureSuggestions =
          services
              .map((s) => (s['name'] ?? '').toString().trim())
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
    } catch (_) {
      procedureSuggestions = const [];
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Novo agendamento'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Horário: ${start.toLocal().toString().substring(11, 16)} - ${end.toLocal().toString().substring(11, 16)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: clientController,
                      decoration: const InputDecoration(
                        labelText: 'Nome do cliente',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Autocomplete<String>(
                      optionsBuilder: (textEditingValue) {
                        final query = textEditingValue.text
                            .trim()
                            .toLowerCase();
                        if (query.isEmpty) return procedureSuggestions;
                        return procedureSuggestions.where(
                          (option) => option.toLowerCase().contains(query),
                        );
                      },
                      onSelected: (selection) {
                        procedureController.text = selection;
                      },
                      fieldViewBuilder:
                          (
                            context,
                            textEditingController,
                            focusNode,
                            onFieldSubmitted,
                          ) {
                            if (procedureController.text.isNotEmpty &&
                                textEditingController.text.isEmpty) {
                              textEditingController.text =
                                  procedureController.text;
                            }
                            return TextField(
                              controller: textEditingController,
                              focusNode: focusNode,
                              onChanged: (value) =>
                                  procedureController.text = value,
                              decoration: const InputDecoration(
                                labelText: 'Procedimento',
                                border: OutlineInputBorder(),
                              ),
                            );
                          },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Observação (opcional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: creating
                      ? null
                      : () async {
                          if (Navigator.of(
                            dialogContext,
                            rootNavigator: true,
                          ).canPop()) {
                            Navigator.of(
                              dialogContext,
                              rootNavigator: true,
                            ).pop();
                          }
                          await _toggleSlotBusy(slot);
                        },
                  child: const Text('Bloquear apenas'),
                ),
                TextButton(
                  onPressed: creating
                      ? null
                      : () {
                          if (Navigator.of(
                            dialogContext,
                            rootNavigator: true,
                          ).canPop()) {
                            Navigator.of(
                              dialogContext,
                              rootNavigator: true,
                            ).pop();
                          }
                        },
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: creating
                      ? null
                      : () async {
                          final clientName = clientController.text.trim();
                          final procedure = procedureController.text.trim();
                          if (clientName.isEmpty || procedure.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Preencha nome do cliente e procedimento.',
                                ),
                              ),
                            );
                            return;
                          }

                          setModalState(() => creating = true);
                          try {
                            await _scheduling.createManualAppointment(
                              providerId: providerId,
                              startTime: start.toUtc(),
                              endTime: end.toUtc(),
                              clientName: clientName,
                              procedureName: procedure,
                              notes: notesController.text.trim(),
                            );
                            if (Navigator.of(
                              dialogContext,
                              rootNavigator: true,
                            ).canPop()) {
                              Navigator.of(
                                dialogContext,
                                rootNavigator: true,
                              ).pop();
                            }
                            if (Navigator.of(dialogContext).canPop()) {
                              Navigator.of(dialogContext).pop();
                            }
                            if (!mounted) return;
                            await _loadSchedule(_selectedDate, silent: true);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Agendamento criado com sucesso.',
                                ),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            setModalState(() => creating = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Erro ao criar agendamento: $e'),
                              ),
                            );
                          }
                        },
                  child: creating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Agendar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(child: _buildHeader(context)),
        ],
        body: Column(
          children: [
            _buildPainelHeader(),
            if (_isRefreshingSlots) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _loadSchedule(_selectedDate, silent: true),
                child: _loadingSlots
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 1.4,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                          itemCount: 12,
                          itemBuilder: (context, index) => const BaseSkeleton(),
                        ),
                      )
                    : _buildScheduleGrid(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 32),
      decoration: BoxDecoration(
        color: AppTheme.primaryYellow,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: RemoteThemeService().getShadow(),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: InkWell(
              onTap: () => context.push('/my-provider-profile'),
              child: Row(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          image: _avatarBytes != null
                              ? DecorationImage(
                                  image: MemoryImage(_avatarBytes!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _avatarBytes == null
                            ? const Center(
                                child: Text(
                                  'P',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      GestureDetector(
                        onTap: _isUploadingAvatar ? null : _editAvatar,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black87,
                            shape: BoxShape.circle,
                          ),
                          child: _isUploadingAvatar
                              ? const SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  LucideIcons.camera,
                                  color: Colors.white,
                                  size: 10,
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Olá,',
                          style: TextStyle(color: Colors.black54),
                        ),
                        Text(
                          _userName ?? 'Prestador',
                          style: const TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: Supabase.instance.client.auth.currentUser?.id != null
                ? DataGateway().watchNotifications(
                    Supabase.instance.client.auth.currentUser!.id,
                  )
                : const Stream.empty(),
            builder: (context, snapshot) {
              final notifications = snapshot.data ?? [];
              final unreadCount = notifications
                  .where((n) => n['read'] != true && n['is_read'] != true)
                  .length;

              return Stack(
                alignment: Alignment.topRight,
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.bell, color: Colors.black87),
                    onPressed: () async {
                      await NotificationDropdownMenu.show(context);
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          unreadCount > 9 ? '9+' : unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openServiceEditMenu() async {
    final services = await _api.getProviderServices();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              minChildSize: 0.5,
              maxChildSize: 0.9,
              builder: (context, scrollController) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Serviços do Salão',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 20),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (services.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 24.0),
                          child: Text(
                            'Nenhum serviço cadastrado ainda.',
                            style: TextStyle(color: Colors.black54),
                          ),
                        )
                      else
                        Expanded(
                          child: ListView.builder(
                            controller: scrollController,
                            shrinkWrap: true,
                            itemCount: services.length,
                            itemBuilder: (context, index) {
                              final service = Map<String, dynamic>.from(
                                services[index],
                              );
                              final isActive =
                                  (service['is_active'] == true ||
                                      service['is_active'] == 1) ||
                                  (service['active'] == true ||
                                      service['active'] == 1);

                              return SwitchListTile(
                                title: Text(
                                  service['name']?.toString() ?? 'Sem nome',
                                ),
                                subtitle: Text(
                                  'R\$ ${double.tryParse(service['unit_price']?.toString() ?? '0')?.toStringAsFixed(2) ?? '0.00'}',
                                ),
                                value: isActive,
                                onChanged: (value) async {
                                  final taskId =
                                      int.tryParse(
                                        service['id']?.toString() ?? '0',
                                      ) ??
                                      0;
                                  if (taskId <= 0) return;

                                  // Otimista: atualiza UI primeiro, persiste depois.
                                  setModalState(() {
                                    services[index]['is_active'] = value;
                                    services[index]['active'] = value;
                                  });

                                  try {
                                    await _api.setProviderServiceActive(
                                      taskId,
                                      value,
                                    );
                                    final updated = await _api
                                        .getProviderServices();
                                    setModalState(() {
                                      services
                                        ..clear()
                                        ..addAll(updated);
                                    });
                                  } catch (e) {
                                    // Reverter se falhar
                                    setModalState(() {
                                      services[index]['is_active'] = !value;
                                      services[index]['active'] = !value;
                                    });
                                    if (mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Erro ao atualizar serviço: $e',
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 14),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          if (mounted) setState(() {});
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryYellow,
                          foregroundColor: Colors.black,
                          minimumSize: const Size.fromHeight(42),
                        ),
                        child: const Text('Fechar'),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildPainelHeader() {
    return Container(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Painel de Serviços',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                ),
                _buildEditServicesButton(),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildTodayTabButton(),
              Expanded(child: _buildPainelDateSelector()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditServicesButton() {
    return InkWell(
      onTap: _openServiceEditMenu,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.settings, size: 16, color: Colors.black87),
            SizedBox(width: 6),
            Text(
              'Editar serviços',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black87,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayTabButton() {
    final nowBr = DateTime.now().toLocal();
    final isSelected =
        _hasBootstrappedAgendaDate &&
        _selectedDate.day == nowBr.day &&
        _selectedDate.month == nowBr.month &&
        _selectedDate.year == nowBr.year;

    return Container(
      width: 92,
      margin: const EdgeInsets.only(left: 16),
      child: Column(
        children: [
          InkWell(
            onTap: _handleTodayTabTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'Hoje',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                    color: isSelected ? Colors.black : Colors.grey[400],
                  ),
                ),
              ),
            ),
          ),
          if (isSelected) Container(height: 2, width: 50, color: Colors.black),
        ],
      ),
    );
  }

  Widget _buildPainelDateSelector() {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        scrollDirection: Axis.horizontal,
        itemCount: 14,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final nowBr = DateTime.now().toLocal();
          final date = nowBr.add(Duration(days: index + 1));
          final isSelected =
              _hasBootstrappedAgendaDate &&
              date.day == _selectedDate.day &&
              date.month == _selectedDate.month &&
              date.year == _selectedDate.year;

          final dayName = index == 0 ? "Amanhã" : _getDayName(date.weekday);

          return Center(
            child: InkWell(
              onTap: () {
                _selectAgendaDate(date);
                _scheduleAgendaRefresh(delay: Duration.zero);
              },
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).primaryColor
                      : Colors.grey[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).primaryColor
                        : Colors.grey[200]!,
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      dayName,
                      style: TextStyle(
                        fontSize: 10,
                        color: isSelected ? Colors.black : Colors.grey[600],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${date.day}/${date.month}",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: isSelected ? Colors.black : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildScheduleGrid() {
    final nowLocal = DateTime.now().toLocal();
    final isToday =
        _selectedDate.year == nowLocal.year &&
        _selectedDate.month == nowLocal.month &&
        _selectedDate.day == nowLocal.day;
    final List<Map<String, dynamic>> upcomingSlots = _visibleSlotsForDate(
      _slots,
      _selectedDate,
    );
    if (_isBootstrappingIdentity) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 42,
              height: 42,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 18),
            Text(
              'Restaurando sua sessao',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Estamos reidratando sua identidade antes de carregar a agenda.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final showClosedShiftState =
        isToday &&
        _slots.isNotEmpty &&
        upcomingSlots.isEmpty &&
        !_scheduleDataIncomplete &&
        !_showClosedHoursForToday;
    final List<Map<String, dynamic>> filteredSlots =
        _showClosedHoursForToday && isToday
        ? List<Map<String, dynamic>>.from(_slots)
        : upcomingSlots;

    if (filteredSlots.isEmpty) {
      final showIdentityFailureState =
          _slots.isEmpty && _lastAgendaEmptyReason == 'profile_load_failed';
      final showSchedulePreviewFailureState =
          _slots.isEmpty && _lastAgendaEmptyReason == 'schedule_preview_failed';
      final showNoConfigState =
          _slots.isEmpty &&
          !showIdentityFailureState &&
          !showSchedulePreviewFailureState &&
          !_scheduleDataIncomplete &&
          !_hasConfirmedScheduleConfig;
      final showIncompleteState = _slots.isEmpty && _scheduleDataIncomplete;
      final showSimpleTodayClosedState =
          isToday &&
          _slots.isNotEmpty &&
          !_scheduleDataIncomplete &&
          !_showClosedHoursForToday &&
          !showClosedShiftState;

      AppLogger.debug(
        '[_buildScheduleGrid] filteredSlots=0 _slots.length=${_slots.length} _scheduleDataIncomplete=$_scheduleDataIncomplete _hasConfirmedScheduleConfig=$_hasConfirmedScheduleConfig showNoConfigState=$showNoConfigState showIncompleteState=$showIncompleteState showClosedShiftState=$showClosedShiftState showSimpleTodayClosedState=$showSimpleTodayClosedState',
      );
      _logAgendaState('grid_empty', {
        'selectedDate': _scheduleDateKey(_selectedDate),
        'slotCount': _slots.length,
        'filteredSlotCount': filteredSlots.length,
        'scheduleDataIncomplete': _scheduleDataIncomplete,
        'hasConfirmedScheduleConfig': _hasConfirmedScheduleConfig,
        'showNoConfigState': showNoConfigState,
        'showIncompleteState': showIncompleteState,
        'showClosedShiftState': showClosedShiftState,
        'showSimpleTodayClosedState': showSimpleTodayClosedState,
        'showIdentityFailureState': showIdentityFailureState,
        'showSchedulePreviewFailureState': showSchedulePreviewFailureState,
        'lastAgendaEmptyReason': _lastAgendaEmptyReason,
      });

      if ((showClosedShiftState || (showIncompleteState && isToday)) &&
          !_showClosedHoursForToday) {
        _scheduleAutoAdvanceToNextWorkingDay();
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(height: 18),
              Text(
                'Buscando o próximo horário útil',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Hoje já encerrou. Vamos abrir o próximo dia com agenda.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              showIncompleteState ? LucideIcons.wifiOff : LucideIcons.calendarX,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              showSimpleTodayClosedState
                  ? "Expediente encerrado por hoje"
                  : showIdentityFailureState
                  ? "Nao foi possivel restaurar sua sessao"
                  : showSchedulePreviewFailureState
                  ? "Nao foi possivel carregar sua agenda"
                  : showIncompleteState
                  ? (isToday
                        ? "Fora do expediente"
                        : "Agenda indisponível agora.")
                  : showClosedShiftState
                  ? "Expediente encerrado"
                  : showNoConfigState
                  ? "Nenhum horário configurado."
                  : "Não há mais horários para hoje.",
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              showSimpleTodayClosedState
                  ? "Selecione o próximo dia útil para ver os próximos horários."
                  : showIdentityFailureState
                  ? (_lastProfileLoadError ??
                        "Estamos com dificuldade para validar seu perfil agora.")
                  : showSchedulePreviewFailureState
                  ? (_lastProfileLoadError ??
                        "Houve uma incompatibilidade com os dados da agenda no servidor.")
                  : showIncompleteState
                  ? (_lastAgendaWarning ??
                        (_lastAgendaEmptyReason ==
                                'slots_generated_but_filtered'
                            ? "Os horários foram carregados, mas ficaram fora do recorte atual da tela."
                            : isToday
                            ? "Hoje não há mais horários disponíveis. Vamos te mostrar o próximo horário útil."
                            : "Não foi possível confirmar os horários agora."))
                  : showClosedShiftState
                  ? "Os horários de hoje já passaram. Você pode revisar os horários encerrados ou abrir o próximo dia útil."
                  : showNoConfigState
                  ? "Verifique sua configuração de dias e horários."
                  : "Você completou seu expediente ou o estabelecimento está fechado.",
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                if (showIdentityFailureState)
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _isBootstrappingIdentity = true;
                        _lastAgendaWarning = null;
                        _lastProfileLoadError = null;
                      });
                      unawaited(_loadProfile());
                    },
                    icon: const Icon(LucideIcons.refreshCw),
                    label: const Text('Tentar novamente'),
                  ),
                if (showSchedulePreviewFailureState)
                  FilledButton.icon(
                    onPressed: () async {
                      await _loadSchedule(
                        _selectedDate,
                        suppressUserWarnings: true,
                      );
                    },
                    icon: const Icon(LucideIcons.refreshCw),
                    label: const Text('Recarregar agenda'),
                  ),
                if (showIncompleteState && isToday)
                  OutlinedButton.icon(
                    onPressed: _jumpToNextWorkingDay,
                    icon: const Icon(LucideIcons.arrowRightCircle),
                    label: const Text('Próximo horário útil'),
                  ),
                if (showClosedShiftState)
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _showClosedHoursForToday = true;
                      });
                    },
                    icon: const Icon(LucideIcons.clock3),
                    label: const Text('Ver horários encerrados'),
                  ),
                if (showClosedShiftState)
                  OutlinedButton.icon(
                    onPressed: _jumpToNextWorkingDay,
                    icon: const Icon(LucideIcons.arrowRightCircle),
                    label: const Text('Próximo dia útil'),
                  ),
                FilledButton.icon(
                  onPressed: () async {
                    final result = await context.push('/provider-schedule');
                    if (result == true) {
                      _scheduleAgendaRefresh(delay: Duration.zero);
                    }
                  },
                  icon: const Icon(LucideIcons.calendarRange),
                  label: const Text('Editar agenda'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.push('/my-provider-profile'),
                  icon: const Icon(LucideIcons.settings),
                  label: const Text('Configurar serviços'),
                ),
                TextButton.icon(
                  onPressed: () => _loadSchedule(_selectedDate, silent: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text("Atualizar"),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Sort slots by time
    final sortedSlots = List<Map<String, dynamic>>.from(filteredSlots);
    sortedSlots.sort((a, b) {
      final t1 =
          DateTime.tryParse(a['start_time'].toString()) ?? DateTime.now();
      final t2 =
          DateTime.tryParse(b['start_time'].toString()) ?? DateTime.now();
      return t1.compareTo(t2);
    });

    final grid = GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.14,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: sortedSlots.length,
      itemBuilder: (context, index) {
        final slot = sortedSlots[index];
        final slotKey = _slotKey(slot);
        final isPendingConfirmation = _pendingSlotKey == slotKey;

        final start = DateTime.parse(slot['start_time']);
        final end = DateTime.parse(slot['end_time']);
        final isCurrent =
            nowLocal.isAfter(start.subtract(const Duration(minutes: 1))) &&
            nowLocal.isBefore(end);

        final nowBr = nowLocal;
        final isFixedDayToday =
            _selectedDate.day == nowBr.day &&
            _selectedDate.month == nowBr.month &&
            _selectedDate.year == nowBr.year;
        final isActuallyNow = isCurrent && isFixedDayToday;
        final normalizedStatus = _normalizedProviderSlotStatus(slot);
        final visualState = _resolveSlotVisualState(
          slot,
          isActuallyNow: isActuallyNow,
          isPendingConfirmation: isPendingConfirmation,
        );
        final isWaitingPix = normalizedStatus == 'waiting_payment';

        final pulseScale = isPendingConfirmation
            ? 1 + 0.06 * math.sin(_slotTouchFxController.value * 2 * math.pi)
            : 1.0;
        final wiggleRotation = isPendingConfirmation
            ? 0.025 * math.sin(_slotTouchFxController.value * 6 * math.pi)
            : 0.0;

        return InkWell(
          onTap: () async {
            if (visualState.opensCreateModal) {
              await _showCreateAppointmentModal(slot);
              return;
            }

            if (_normalizedProviderSlotStatus(slot) == 'lunch') {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Horário de almoço do estabelecimento.'),
                ),
              );
              return;
            }

            if (visualState.opensDetails) {
              await _showAppointmentDetails(slot);
              return;
            }

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Horário ocupado por agendamento de cliente.'),
              ),
            );
          },
          child: Transform.rotate(
            angle: wiggleRotation,
            child: Transform.scale(
              scale: pulseScale,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (visualState.badgeText != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: visualState.badgeBackground,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          visualState.badgeText!,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: visualState.badgeForeground,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  if (visualState.showsChatShortcut)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (slot['service_id'] == null) return;
                          _openClientChatModal(slot);
                        },
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E88E5),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Icon(
                            LucideIcons.messageCircle,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      color: visualState.backgroundColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: visualState.borderColor,
                        width: isActuallyNow
                            ? 2.5
                            : (visualState.borderColor == Colors.transparent
                                  ? 0
                                  : 1.5),
                      ),
                      boxShadow: [
                        ...RemoteThemeService().getShadow(),
                        if (isActuallyNow)
                          BoxShadow(
                            color: const Color(0xFF4CAF50).withOpacity(0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            () {
                              try {
                                final dt = DateTime.parse(
                                  slot['start_time'].toString(),
                                ).toLocal();
                                return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
                              } catch (e) {
                                return "--:--";
                              }
                            }(),
                            style: TextStyle(
                              fontSize: visualState.contextTitle == null
                                  ? 21
                                  : 19,
                              fontWeight: FontWeight.w900,
                              color: visualState.timeColor,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            visualState.statusLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isPendingConfirmation ? 10 : 11,
                              fontWeight: FontWeight.w800,
                              color: visualState.textColor,
                              letterSpacing: 0.2,
                              height: 1.05,
                            ),
                          ),
                          if (visualState.contextTitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              visualState.contextTitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: visualState.timeColor,
                                height: 1.05,
                              ),
                            ),
                          ],
                          if (visualState.contextSubtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              visualState.contextSubtitle!,
                              maxLines: isWaitingPix ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isWaitingPix ? 8.2 : 8.6,
                                fontWeight: FontWeight.w600,
                                color: visualState.textColor.withOpacity(
                                  visualState.textColor == Colors.white
                                      ? 0.9
                                      : 0.72,
                                ),
                                height: 1.05,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (isPendingConfirmation)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.blue[700]!,
                            ),
                            backgroundColor: Colors.white.withOpacity(0.4),
                          ),
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

    final bannerWidgets = <Widget>[];

    if (_scheduleDataIncomplete && _lastAgendaWarning != null) {
      bannerWidgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF9A825)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    LucideIcons.alertTriangle,
                    size: 16,
                    color: Color(0xFF8D6E00),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _lastAgendaWarning!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8D6E00),
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_showClosedHoursForToday && isToday) {
      bannerWidgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F1FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF90CAF9)),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.clock3,
                  size: 16,
                  color: Color(0xFF1565C0),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Mostrando também os horários já encerrados de hoje.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1565C0),
                      height: 1.25,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _showClosedHoursForToday = false;
                    });
                  },
                  child: const Text('Ocultar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (bannerWidgets.isEmpty) {
      return ListView(children: [grid]);
    }

    return ListView(children: [...bannerWidgets, grid]);
  }

  Future<Map<String, dynamic>> _hydrateAppointmentDetailsForModal(
    Map<String, dynamic> slot,
  ) async {
    final serviceId = slot['service_id']?.toString().trim();
    if (serviceId == null || serviceId.isEmpty) {
      return slot;
    }

    try {
      final service = await _api.getServiceDetails(
        serviceId,
        scope: ServiceDataScope.fixedOnly,
      );
      return {
        ...slot,
        'service_status': service['status'] ?? slot['service_status'],
        'client_name': service['client_name'] ?? slot['client_name'],
        'client_phone': service['client_phone'] ?? slot['client_phone'],
        'client_avatar': service['client_avatar'] ?? slot['client_avatar'],
        'service_profession':
            service['profession_name'] ??
            service['task_name'] ??
            slot['service_profession'],
        'procedure_name': service['task_name'] ?? slot['procedure_name'],
        'service_description':
            service['description'] ?? slot['service_description'],
        'price_total':
            service['preco_total'] ??
            service['price_estimated'] ??
            slot['price_total'],
        'price_paid':
            service['valor_entrada'] ??
            service['price_upfront'] ??
            slot['price_paid'],
      };
    } catch (_) {
      return slot;
    }
  }

  Future<void> _showAppointmentDetails(Map<String, dynamic> slot) async {
    final modalSlot = await _hydrateAppointmentDetailsForModal(slot);
    final totalAmount =
        double.tryParse(modalSlot['price_total']?.toString() ?? '') ?? 0;
    final paidAmount =
        double.tryParse(modalSlot['price_paid']?.toString() ?? '') ?? 0;
    final remainingAmount = (totalAmount - paidAmount).clamp(
      0,
      double.infinity,
    );
    final paidPercentage = totalAmount > 0
        ? ((paidAmount / totalAmount) * 100).round()
        : 0;
    final remainingPercentage = totalAmount > 0
        ? ((remainingAmount / totalAmount) * 100).round()
        : 0;
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.black,
                width: 0.5,
              ), // Thin black border
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text(
                        'Detalhes do Agendamento',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey[200],
                          image: modalSlot['client_avatar'] != null
                              ? DecorationImage(
                                  image: NetworkImage(
                                    modalSlot['client_avatar'],
                                  ),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: modalSlot['client_avatar'] == null
                            ? const Icon(
                                Icons.person,
                                size: 40,
                                color: Colors.grey,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        modalSlot['client_name'] ?? 'Cliente',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildClientInfoCard(modalSlot),
                    const SizedBox(height: 12),
                    _buildDetailRow(
                      LucideIcons.briefcase,
                      'Serviço',
                      modalSlot['service_profession'] ??
                          modalSlot['procedure_name'] ??
                          'Serviço',
                    ),
                    if (modalSlot['service_description'] != null ||
                        modalSlot['notes'] != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 32, bottom: 12),
                        child: Text(
                          (modalSlot['service_description'] ??
                                  modalSlot['notes'])
                              .toString(),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ),
                    if (modalSlot['price_total'] != null) ...[
                      _buildDetailRow(
                        LucideIcons.banknote,
                        'Valor Total (100%)',
                        "R\$ ${totalAmount.toStringAsFixed(2).replaceAll('.', ',')}",
                      ),
                      if (paidAmount > 0)
                        _buildDetailRow(
                          LucideIcons.checkCircle2,
                          'Pago (taxa ${paidPercentage.clamp(0, 100)}%)',
                          "R\$ ${paidAmount.toStringAsFixed(2).replaceAll('.', ',')}",
                          color: Colors.green[600],
                        ),
                      _buildDetailRow(
                        LucideIcons.alertCircle,
                        'Restante no local (${remainingPercentage.clamp(0, 100)}%)',
                        "R\$ ${remainingAmount.toStringAsFixed(2).replaceAll('.', ',')}",
                        color: Colors.orange[800],
                      ),
                    ],
                    _buildDetailRow(
                      LucideIcons.clock,
                      'Horário',
                      "${modalSlot['start_time'].toString().substring(11, 16)} - ${modalSlot['end_time'].toString().substring(11, 16)}",
                    ),
                    const SizedBox(height: 24),
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              Future.microtask(
                                () => _openClientChatModal(modalSlot),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF007AFF),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            icon: const Icon(
                              LucideIcons.messageSquare,
                              size: 20,
                            ),
                            label: const Text(
                              'Enviar mensagem para o cliente',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        if (modalSlot['service_id'] != null &&
                            modalSlot['service_status'] != 'completed' &&
                            modalSlot['service_status'] != 'cancelled')
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Finalizar Serviço?'),
                                      content: Text(
                                        'Isso marcará o serviço como finalizado com sucesso e o pagamento total como recebido. Neste agendamento, o valor restante (${remainingPercentage.clamp(0, 100)}%) é pago diretamente no local.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('Cancelar'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text(
                                            'Confirmar',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true && mounted) {
                                    try {
                                      final serviceId = modalSlot['service_id']
                                          ?.toString()
                                          .trim();
                                      if (serviceId == null ||
                                          serviceId.isEmpty) {
                                        throw Exception(
                                          'ID do serviço não encontrado.',
                                        );
                                      }

                                      await _api.completeService(serviceId);
                                      if (!mounted) return;
                                      Navigator.pop(context);
                                      _showToast(
                                        'Serviço finalizado e horário liberado.',
                                        backgroundColor: Colors.green,
                                      );
                                      await _loadSchedule(
                                        _selectedDate,
                                        silent: true,
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Erro ao finalizar serviço: $e',
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFC2185B),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 2,
                                ),
                                icon: const Icon(
                                  LucideIcons.checkCircle2,
                                  size: 20,
                                ),
                                label: const Text(
                                  'Finalizar e Confirmar Recebimento',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey[700],
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey[300]!),
                              ),
                            ),
                            child: const Text(
                              'Fechar',
                              style: TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openClientChatModal(Map<String, dynamic> slot) async {
    final serviceId = slot['service_id']?.toString().trim();
    if (serviceId == null || serviceId.isEmpty) {
      _showToast('Erro: ID do serviço não encontrado.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.96,
          child: ChatScreen(
            serviceId: serviceId,
            otherName: slot['client_name']?.toString(),
            otherAvatar: slot['client_avatar']?.toString(),
            isInline: true,
            onClose: () => Navigator.of(context).pop(),
          ),
        );
      },
    );
  }

  Widget _buildClientInfoCard(Map<String, dynamic> slot) {
    final clientName = (slot['client_name'] ?? 'Cliente').toString().trim();
    final clientPhone = (slot['client_phone'] ?? '').toString().trim();
    final phoneLabel = clientPhone.isNotEmpty
        ? clientPhone
        : 'Telefone não cadastrado';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dados do cliente',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(LucideIcons.user, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Nome',
                      style: TextStyle(fontSize: 12, color: Colors.black45),
                    ),
                    Text(
                      clientName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(LucideIcons.phone, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Telefone cadastrado',
                      style: TextStyle(fontSize: 12, color: Colors.black45),
                    ),
                    Text(
                      phoneLabel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: clientPhone.isNotEmpty
                            ? Colors.black87
                            : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color ?? AppTheme.primaryPurple),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: color ?? Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case 1:
        return "Seg";
      case 2:
        return "Ter";
      case 3:
        return "Qua";
      case 4:
        return "Qui";
      case 5:
        return "Sex";
      case 6:
        return "Sáb";
      case 7:
        return "Dom";
      default:
        return "";
    }
  }
}
