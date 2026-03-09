import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';

class ScheduleEditScreen extends StatefulWidget {
  const ScheduleEditScreen({super.key});

  @override
  State<ScheduleEditScreen> createState() => _ScheduleEditScreenState();
}

class _ScheduleEditScreenState extends State<ScheduleEditScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _schedules = [];
  final List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _exceptions = [];

  // Day names mapping (0 = Sunday in some systems, but let's check backend)
  // Backend schema: day_of_week: 0-6. Usually 0=Sunday or 0=Monday.
  // In JS Date.getDay(), 0=Sunday. Let's assume 0=Sunday.
  final List<String> _weekDays = [
    'Domingo',
    'Segunda',
    'Terça',
    'Quarta',
    'Quinta',
    'Sexta',
    'Sábado',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final providerId = ApiService().userId;
    if (providerId == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      // Sprint 2: Supabase SDK em vez de GET /provider/setup
      final schedulesRaw = await Supabase.instance.client
          .from('provider_schedule_configs')
          .select()
          .eq('provider_id', providerId);

      final exceptionsRaw = await Supabase.instance.client
          .from('provider_schedule_exceptions')
          .select()
          .eq('provider_id', providerId);

      setState(() {
        final List<dynamic> schedulesData = schedulesRaw;
        _schedules = List.generate(7, (index) {
          final existing = schedulesData
              .cast<Map<String, dynamic>?>()
              .firstWhere(
                (s) => s?['day_of_week'] == index,
                orElse: () => null,
              );

          final bool isEnabled = existing != null
              ? (existing['is_enabled'] == 1 || existing['is_enabled'] == true)
              : (index != 0 && index != 6);

          final Map<String, dynamic> data = (existing != null)
              ? Map<String, dynamic>.from(existing)
              : {
                  'day_of_week': index,
                  'start_time': '09:00',
                  'end_time': '18:00',
                  'break_start': '12:00',
                  'break_end': '13:00',
                };
          data['is_enabled'] = isEnabled;
          return data;
        });

        _exceptions = exceptionsRaw
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao carregar dados: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  bool _isValidTime(String start, String end) {
    try {
      final s = start.split(':');
      final e = end.split(':');
      final startMin = int.parse(s[0]) * 60 + int.parse(s[1]);
      final endMin = int.parse(e[0]) * 60 + int.parse(e[1]);
      return startMin < endMin;
    } catch (_) {
      return false;
    }
  }

  bool _isContained(
    String outerStart,
    String outerEnd,
    String innerStart,
    String innerEnd,
  ) {
    try {
      final os = outerStart.split(':');
      final oe = outerEnd.split(':');
      final iS = innerStart.split(':');
      final ie = innerEnd.split(':');

      final osMin = int.parse(os[0]) * 60 + int.parse(os[1]);
      final oeMin = int.parse(oe[0]) * 60 + int.parse(oe[1]);
      final isMin = int.parse(iS[0]) * 60 + int.parse(iS[1]);
      final ieMin = int.parse(ie[0]) * 60 + int.parse(ie[1]);

      return isMin >= osMin && ieMin <= oeMin;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveData() async {
    // 1. Validation
    for (final s in _schedules) {
      if (s['is_enabled'] == true) {
        final day = _weekDays[s['day_of_week']];
        if (!_isValidTime(s['start_time'], s['end_time'])) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Horário inválido na $day: Fim deve ser após o Início.',
              ),
            ),
          );
          return;
        }
        if (!_isValidTime(s['break_start'], s['break_end'])) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Intervalo de almoço inválido na $day.')),
          );
          return;
        }
        if (!_isContained(
          s['start_time'],
          s['end_time'],
          s['break_start'],
          s['break_end'],
        )) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Almoço na $day deve estar dentro do expediente.'),
            ),
          );
          return;
        }
      }
    }

    setState(() => _isLoading = true);
    final providerId = ApiService().userId;
    if (providerId == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      // Sprint 2: Supabase SDK em vez de POST /provider/schedule
      final schedulesToSend = _schedules
          .map(
            (s) => {
              'provider_id': providerId,
              'day_of_week': s['day_of_week'],
              'start_time': s['start_time'],
              'end_time': s['end_time'],
              'break_start': s['break_start'],
              'break_end': s['break_end'],
              'is_enabled': s['is_enabled'] == true,
            },
          )
          .toList();

      await Supabase.instance.client
          .from('provider_schedule_configs')
          .upsert(schedulesToSend, onConflict: 'provider_id,day_of_week');

      // Exceptions: delete all and re-insert
      await Supabase.instance.client
          .from('provider_schedule_exceptions')
          .delete()
          .eq('provider_id', providerId);

      if (_exceptions.isNotEmpty) {
        final exceptionsToSend = _exceptions
            .map(
              (e) => {
                ...Map<String, dynamic>.from(e),
                'provider_id': providerId,
              },
            )
            .toList();
        await Supabase.instance.client
            .from('provider_schedule_exceptions')
            .insert(exceptionsToSend);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configurações salvas com sucesso!')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectTime(
    BuildContext context,
    Map<String, dynamic> item,
    String key,
  ) async {
    final currentStr = item[key] as String?;
    TimeOfDay initialTime = const TimeOfDay(hour: 9, minute: 0);
    if (currentStr != null && currentStr.isNotEmpty) {
      final parts = currentStr.split(':');
      if (parts.length == 2) {
        initialTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 9,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        final hour = picked.hour.toString().padLeft(2, '0');
        final minute = picked.minute.toString().padLeft(2, '0');
        item[key] = '$hour:$minute';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar Agenda'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isLoading ? null : _saveData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Duração da Consulta'),
                  ..._services.map(
                    (service) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    service['name'] ?? 'Serviço',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (service['description'] != null)
                                    Text(
                                      service['description'],
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () {
                                    final current =
                                        service['duration'] as int? ?? 30;
                                    if (current > 5) {
                                      setState(() {
                                        service['duration'] = current - 5;
                                      });
                                    }
                                  },
                                ),
                                Text(
                                  '${service['duration']} min',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () {
                                    final current =
                                        service['duration'] as int? ?? 30;
                                    setState(() {
                                      service['duration'] = current + 5;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  _buildSectionTitle('Horário de Funcionamento'),
                  const Text(
                    'Configure os dias e horários que você atende.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 16),

                  ..._schedules.map((schedule) {
                    final index = schedule['day_of_week'] as int;
                    final isEnabled =
                        schedule['is_enabled'] == true ||
                        schedule['is_enabled'] == 1;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: isEnabled ? Colors.white : Colors.grey.shade100,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: isEnabled,
                                  onChanged: (val) {
                                    setState(() {
                                      schedule['is_enabled'] = val;
                                    });
                                  },
                                  activeColor: AppTheme.primaryPurple,
                                ),
                                Text(
                                  _weekDays[index],
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isEnabled
                                        ? Colors.black
                                        : Colors.grey,
                                  ),
                                ),
                                const Spacer(),
                                if (isEnabled) ...[
                                  _buildTimeButton(schedule, 'start_time'),
                                  const Text(' - '),
                                  _buildTimeButton(schedule, 'end_time'),
                                ],
                              ],
                            ),
                            if (isEnabled) ...[
                              const Divider(),
                              Row(
                                children: [
                                  const SizedBox(
                                    width: 48,
                                  ), // Indent to align with text
                                  const Text(
                                    'Almoço:',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildTimeButton(
                                    schedule,
                                    'break_start',
                                    fontSize: 12,
                                  ),
                                  const Text(
                                    ' - ',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  _buildTimeButton(
                                    schedule,
                                    'break_end',
                                    fontSize: 12,
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionTitle('Feriados e Ausências'),
                      IconButton(
                        icon: Icon(
                          Icons.add_circle,
                          color: AppTheme.primaryPurple,
                        ),
                        onPressed: _addException,
                      ),
                    ],
                  ),
                  const Text(
                    'Adicione dias específicos de folga ou horários diferenciados.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  if (_exceptions.isEmpty)
                    const Text(
                      'Nenhuma exceção cadastrada.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ..._exceptions.map((ex) {
                    final date = DateTime.parse(ex['date']);
                    final dateStr =
                        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
                    final isFullDay = ex['start_time'] == null;

                    return Card(
                      child: ListTile(
                        title: Text(
                          dateStr,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          isFullDay
                              ? 'Folga (Dia inteiro)'
                              : '${ex['start_time']} - ${ex['end_time']}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            setState(() {
                              _exceptions.remove(ex);
                            });
                          },
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 48),
                ],
              ),
            ),
    );
  }

  Future<void> _addException() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );

    if (pickedDate == null) return;

    // Check if already exists
    final dateStr = pickedDate.toString().split(' ')[0];
    if (_exceptions.any((e) => e['date'] == dateStr)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Já existe uma exceção para esta data.'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    bool isFullDay = true;
    String? startTime;
    String? endTime;
    final reasonController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Adicionar Exceção'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Data: $dateStr'),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('Dia inteiro de folga'),
                    value: isFullDay,
                    onChanged: (val) {
                      setStateDialog(() => isFullDay = val!);
                    },
                  ),
                  if (!isFullDay) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final t = await showTimePicker(
                                context: context,
                                initialTime: const TimeOfDay(
                                  hour: 9,
                                  minute: 0,
                                ),
                              );
                              if (t != null) {
                                setStateDialog(() {
                                  startTime =
                                      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Início',
                              ),
                              child: Text(startTime ?? '09:00'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final t = await showTimePicker(
                                context: context,
                                initialTime: const TimeOfDay(
                                  hour: 18,
                                  minute: 0,
                                ),
                              );
                              if (t != null) {
                                setStateDialog(() {
                                  endTime =
                                      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Fim',
                              ),
                              child: Text(endTime ?? '18:00'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  TextField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Motivo (opcional)',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () {
                    if (!isFullDay && (startTime == null || endTime == null)) {
                      // Default values if not picked
                      startTime ??= '09:00';
                      endTime ??= '18:00';
                    }
                    Navigator.pop(context, true);
                  },
                  child: const Text('Adicionar'),
                ),
              ],
            );
          },
        );
      },
    ).then((result) {
      if (result == true) {
        setState(() {
          _exceptions.add({
            'date': dateStr,
            'start_time': isFullDay ? null : (startTime ?? '09:00'),
            'end_time': isFullDay ? null : (endTime ?? '18:00'),
            'reason': reasonController.text,
          });
        });
      }
    });
  }

  Widget _buildTimeButton(
    Map<String, dynamic> item,
    String key, {
    double fontSize = 14,
  }) {
    return InkWell(
      onTap: () => _selectTime(context, item, key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(4),
          color: Colors.white,
        ),
        child: Text(
          item[key] ?? '--:--',
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppTheme.primaryPurple,
        ),
      ),
    );
  }
}
