import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_theme.dart';

class MedicalAgendaView extends StatefulWidget {
  final List<dynamic> appointments;
  final List<dynamic> schedules;
  final List<dynamic> exceptions;
  final Function(DateTime) onDateSelected;
  final VoidCallback? onSettingsTap;
  final int slotDuration; // Duration in minutes (service + gap)

  const MedicalAgendaView({
    super.key,
    required this.appointments,
    required this.onDateSelected,
    this.schedules = const [],
    this.exceptions = const [],
    this.onSettingsTap,
    this.slotDuration = 35, // Default to 35 (30 min service + 5 min gap)
  });

  @override
  State<MedicalAgendaView> createState() => _MedicalAgendaViewState();
}

class _MedicalAgendaViewState extends State<MedicalAgendaView> {
  DateTime _selectedDate = DateTime.now();
  final ScrollController _scrollController = ScrollController();
  int _startMinutes = 480; // 08:00
  int _endMinutes = 1080; // 18:00
  int? _breakStartMinutes;
  int? _breakEndMinutes;
  bool _isDayEnabled = true;
  List<TimeOfDay> _slots = [];

  @override
  void initState() {
    super.initState();
    _updateSchedule();
    // Scroll to start hour roughly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _slots.isNotEmpty) {
        // Approximate scroll position: index of first slot * height
        // Finding the first slot that is >= 8:00 (default start if not specified)
        // or just scroll to top if starts early.
        // Let's just scroll to offset 0 for now or calculate properly if needed.
      }
    });
  }

  @override
  void didUpdateWidget(MedicalAgendaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schedules != widget.schedules ||
        oldWidget.slotDuration != widget.slotDuration ||
        oldWidget.appointments != widget.appointments) {
      _updateSchedule();
    }
  }

  void _updateSchedule() {
    // int startMinutes = 8 * 60; // Default 08:00 - Removed as class members are used directly
    // int endMinutes = 18 * 60; // Default 18:00 - Removed as class members are used directly
    // int? breakStartMinutes; // Removed as class members are used directly
    // int? breakEndMinutes; // Removed as class members are used directly

    if (widget.schedules.isEmpty) {
      _startMinutes = 8 * 60;
      _endMinutes = 18 * 60;
      _breakStartMinutes = null;
      _breakEndMinutes = null;
      _isDayEnabled = true;
    } else {
      // day_of_week: 0=Sunday
      final weekday = _selectedDate.weekday == 7 ? 0 : _selectedDate.weekday;

      final schedule = widget.schedules.firstWhere(
        (s) => s['day_of_week'] == weekday,
        orElse: () => null,
      );

      if (schedule != null) {
        _isDayEnabled =
            schedule['is_enabled'] == true || schedule['is_enabled'] == 1;
        if (_isDayEnabled) {
          final start = schedule['start_time'] as String?;
          final end = schedule['end_time'] as String?;
          final bStart = schedule['break_start'] as String?;
          final bEnd = schedule['break_end'] as String?;

          if (start != null) _startMinutes = _parseTimeStr(start);
          if (end != null) _endMinutes = _parseTimeStr(end);
          if (bStart != null) _breakStartMinutes = _parseTimeStr(bStart);
          if (bEnd != null) _breakEndMinutes = _parseTimeStr(bEnd);
        } else {
          // If day is disabled, ensure break times are null
          _breakStartMinutes = null;
          _breakEndMinutes = null;
        }
      } else {
        _startMinutes = 8 * 60;
        _endMinutes = 18 * 60;
        _isDayEnabled = true;
        _breakStartMinutes = null;
        _breakEndMinutes = null;
      }
    }

    // Generate Slots
    _slots = [];
    if (_isDayEnabled) {
      int current = _startMinutes;
      while (current < _endMinutes) {
        _slots.add(TimeOfDay(hour: current ~/ 60, minute: current % 60));
        current += widget.slotDuration;
      }
    }
    setState(() {});
  }

  int _parseTimeStr(String time) {
    // Expected "HH:MM" or "HH:MM:SS"
    try {
      final parts = time.split(':');
      final h = int.parse(parts[0]);
      final m = parts.length > 1 ? int.parse(parts[1]) : 0;
      return h * 60 + m;
    } catch (_) {
      return 0; // Fallback
    }
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _updateSchedule();
    widget.onDateSelected(_selectedDate);
  }

  List<dynamic> _getAppointmentsForSlot(TimeOfDay slotTime) {
    return widget.appointments.where((appt) {
      final startTimeStr = appt['start_time'];
      if (startTimeStr == null) return false;
      final startTime = DateTime.tryParse(startTimeStr);
      if (startTime == null) return false;

      if (startTime.year != _selectedDate.year ||
          startTime.month != _selectedDate.month ||
          startTime.day != _selectedDate.day) {
        return false;
      }

      // Calculate minutes from start of day for comparison
      final slotMinutes = slotTime.hour * 60 + slotTime.minute;
      final apptMinutes = startTime.hour * 60 + startTime.minute;

      // Check if appointment starts within this slot (inclusive start, exclusive end)
      return apptMinutes >= slotMinutes &&
          apptMinutes < (slotMinutes + widget.slotDuration);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: !_isDayEnabled ? _buildDayOffState() : _buildSlotsList(),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildCircleButton(
            icon: Icons.chevron_left,
            onTap: () => _changeDate(-1),
          ),
          Column(
            children: [
              Text(
                DateFormat('EEEE', 'pt_BR').format(_selectedDate).toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryPurple.withValues(alpha: 0.6),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                DateFormat('d MMMM yyyy', 'pt_BR').format(_selectedDate),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          Row(
            children: [
              _buildCircleButton(
                icon: Icons.chevron_right,
                onTap: () => _changeDate(1),
              ),
              if (widget.onSettingsTap != null) ...[
                const SizedBox(width: 8),
                _buildCircleButton(
                  icon: LucideIcons.settings,
                  onTap: widget.onSettingsTap!,
                  isPrimary: true,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return Material(
      color: isPrimary ? AppTheme.primaryPurple : Colors.grey[100],
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Icon(
            icon,
            size: 18,
            color: isPrimary ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildDayOffState() {
    return Container(
      key: const ValueKey('day_off'),
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.calendarOff,
              size: 80,
              color: Colors.grey[300],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Dia de Descanso',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Você não configurou atendimento para este dia. Aproveite para recarregar as energias!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          if (widget.onSettingsTap != null)
            TextButton.icon(
              onPressed: widget.onSettingsTap,
              icon: const Icon(LucideIcons.settings2),
              label: const Text('Configurar Horários'),
            ),
        ],
      ),
    );
  }

  Widget _buildSlotsList() {
    return ListView.builder(
      key: const ValueKey('slots_list'),
      padding: const EdgeInsets.symmetric(vertical: 20),
      controller: _scrollController,
      itemCount: _slots.length,
      itemBuilder: (context, index) {
        final slotTime = _slots[index];
        final appointments = _getAppointmentsForSlot(slotTime);

        bool isBreak = false;
        if (_breakStartMinutes != null && _breakEndMinutes != null) {
          final slotMinutes = slotTime.hour * 60 + slotTime.minute;
          if (slotMinutes >= _breakStartMinutes! &&
              slotMinutes < _breakEndMinutes!) {
            isBreak = true;
          }
        }

        return Padding(
          padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
          child: IntrinsicHeight(
            child: Row(
              children: [
                _buildTimeColumn(slotTime),
                const SizedBox(width: 16),
                Expanded(
                  child: isBreak
                      ? _buildBreakCard()
                      : (appointments.isEmpty
                            ? _buildAvailableCard(slotTime)
                            : _buildAppointmentCards(appointments)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimeColumn(TimeOfDay time) {
    return SizedBox(
      width: 50,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryPurple.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.coffee, size: 20, color: Colors.brown[300]),
          const SizedBox(width: 12),
          Text(
            'Intervalo de Almoço',
            style: TextStyle(
              color: Colors.grey[500],
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailableCard(TimeOfDay time) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[100]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            children: [
              Icon(LucideIcons.plusCircle, size: 20, color: Colors.green),
              SizedBox(width: 12),
              Text(
                'Horário Disponível',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          Icon(Icons.chevron_right, size: 18, color: Colors.grey[300]),
        ],
      ),
    );
  }

  Widget _buildAppointmentCards(List<dynamic> appointments) {
    return Column(
      children: appointments.map((appt) {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primaryPurple,
                AppTheme.primaryPurple.withValues(alpha: 0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryPurple.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white24,
                child: Icon(LucideIcons.user, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appt['client_name'] ?? 'Paciente',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      appt['service_name'] ?? 'Procedimento Médico',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                LucideIcons.chevronRight,
                color: Colors.white60,
                size: 20,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
