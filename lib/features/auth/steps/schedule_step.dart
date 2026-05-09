import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/ios_date_time_picker.dart';

class ScheduleStep extends StatefulWidget {
  final Map<int, Map<String, dynamic>> schedule;
  final Function(Map<int, Map<String, dynamic>>) onChanged;

  const ScheduleStep({
    super.key,
    required this.schedule,
    required this.onChanged,
  });

  @override
  State<ScheduleStep> createState() => _ScheduleStepState();
}

class _ScheduleStepState extends State<ScheduleStep>
    with SingleTickerProviderStateMixin {
  static const double _fieldRadius = 18;
  final List<String> _days = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  late TabController _tabController;
  String _globalBreakStart = '12:00';
  String _globalBreakEnd = '13:00';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Initialize global break time from first enabled day
    for (int i = 0; i < 7; i++) {
      if (widget.schedule[i]?['is_enabled'] ?? false) {
        _globalBreakStart = widget.schedule[i]!['break_start'] ?? '12:00';
        _globalBreakEnd = widget.schedule[i]!['break_end'] ?? '13:00';
        break;
      }
    }
  }

  void _toggleDay(int dayIndex) {
    final newSchedule = Map<int, Map<String, dynamic>>.from(widget.schedule);
    if (newSchedule.containsKey(dayIndex)) {
      final current = newSchedule[dayIndex]!;
      newSchedule[dayIndex] = {
        ...current,
        'is_enabled': !(current['is_enabled'] ?? false),
      };
    } else {
      newSchedule[dayIndex] = {
        'day_of_week': dayIndex,
        'start_time': '09:00',
        'end_time': '18:00',
        'break_start': _globalBreakStart,
        'break_end': _globalBreakEnd,
        'is_enabled': true,
      };
    }
    widget.onChanged(newSchedule);
  }

  Future<void> _pickTime(int dayIndex, String key) async {
    final current =
        widget.schedule[dayIndex]?[key] ??
        (key.contains('break') ? '12:00' : '09:00');
    final parts = current.split(':');
    final time = await AppCupertinoPicker.showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
      title: 'Selecionar horário',
    );

    if (time != null) {
      final newSchedule = Map<int, Map<String, dynamic>>.from(widget.schedule);
      final formatted =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

      final currentDay =
          newSchedule[dayIndex] ??
          {
            'day_of_week': dayIndex,
            'start_time': '09:00',
            'end_time': '18:00',
            'break_start': _globalBreakStart,
            'break_end': _globalBreakEnd,
            'is_enabled': true,
          };

      newSchedule[dayIndex] = {...currentDay, key: formatted};

      widget.onChanged(newSchedule);
    }
  }

  Future<void> _pickGlobalBreakTime(String key) async {
    final current = key == 'break_start' ? _globalBreakStart : _globalBreakEnd;
    final parts = current.split(':');
    final time = await AppCupertinoPicker.showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
      title: 'Selecionar horário',
    );

    if (time != null) {
      setState(() {
        final formatted =
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
        if (key == 'break_start') {
          _globalBreakStart = formatted;
        } else {
          _globalBreakEnd = formatted;
        }

        // Sync to all enabled days
        final newSchedule = Map<int, Map<String, dynamic>>.from(
          widget.schedule,
        );
        for (int i = 0; i < 7; i++) {
          if (newSchedule.containsKey(i) &&
              (newSchedule[i]!['is_enabled'] ?? false)) {
            newSchedule[i] = {...newSchedule[i]!, key: formatted};
          }
        }
        widget.onChanged(newSchedule);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Defina seus horários de atendimento',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        TabBar(
          controller: _tabController,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.black,
          tabs: const [
            Tab(text: 'Horários Diários'),
            Tab(text: 'Almoço Global'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Daily Schedule Tab
              ListView.builder(
                itemCount: 7,
                itemBuilder: (context, index) {
                  final isEnabled =
                      widget.schedule[index]?['is_enabled'] ?? false;

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceWhite,
                      borderRadius: BorderRadius.circular(_fieldRadius),
                      border: Border.all(
                        color: const Color(0xFFE6ECF5),
                        width: 1.2,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: Checkbox(
                                  activeColor: AppTheme.darkBlueText,
                                  value: isEnabled,
                                  onChanged: (_) => _toggleDay(index),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _days[index],
                                style: GoogleFonts.manrope(
                                  color: AppTheme.textDark,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              const Spacer(),
                              if (isEnabled) ...[
                                InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => _pickTime(index, 'start_time'),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 6,
                                    ),
                                    child: Text(
                                      widget.schedule[index]!['start_time'],
                                      style: GoogleFonts.manrope(
                                        color: AppTheme.textDark,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Text(
                                    '-',
                                    style: GoogleFonts.manrope(
                                      color: AppTheme.textMuted,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => _pickTime(index, 'end_time'),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 6,
                                    ),
                                    child: Text(
                                      widget.schedule[index]!['end_time'],
                                      style: GoogleFonts.manrope(
                                        color: AppTheme.textDark,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ] else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.backgroundLight,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'Fechado',
                                    style: GoogleFonts.manrope(
                                      color: AppTheme.textMuted,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (isEnabled) ...[
                            const SizedBox(height: 10),
                            const Divider(height: 1, color: Color(0xFFE6ECF5)),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const SizedBox(width: 36),
                                Text(
                                  'Almoço:',
                                  style: GoogleFonts.manrope(
                                    color: AppTheme.textMuted,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const Spacer(),
                                InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () =>
                                      _pickTime(index, 'break_start'),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      widget.schedule[index]!['break_start'] ??
                                          '12:00',
                                      style: GoogleFonts.manrope(
                                        color: AppTheme.textDark,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Text(
                                    '-',
                                    style: GoogleFonts.manrope(
                                      color: AppTheme.textMuted,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => _pickTime(index, 'break_end'),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      widget.schedule[index]!['break_end'] ??
                                          '13:00',
                                      style: GoogleFonts.manrope(
                                        color: AppTheme.textDark,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            const SizedBox(height: 2),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
              // Global Lunch Break Tab
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Defina o horário de almoço para todos os dias',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () => _pickGlobalBreakTime('break_start'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black,
                            textStyle: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          child: Text(_globalBreakStart),
                        ),
                        const Text(
                          '-',
                          style: TextStyle(color: Colors.black, fontSize: 24),
                        ),
                        TextButton(
                          onPressed: () => _pickGlobalBreakTime('break_end'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black,
                            textStyle: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          child: Text(_globalBreakEnd),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Este horário será aplicado a todos os dias habilitados.',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
