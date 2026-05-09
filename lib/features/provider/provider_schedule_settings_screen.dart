import 'package:flutter/material.dart';

import '../../domains/scheduling/scheduling.dart';
import '../../integrations/supabase/scheduling/supabase_scheduling_repository.dart';
import '../../services/api_service.dart';
import '../../widgets/ios_date_time_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ProviderScheduleSettingsScreen extends StatefulWidget {
  const ProviderScheduleSettingsScreen({super.key});

  @override
  State<ProviderScheduleSettingsScreen> createState() =>
      _ProviderScheduleSettingsScreenState();
}

class _ProviderScheduleSettingsScreenState
    extends State<ProviderScheduleSettingsScreen> {
  final ApiService _api = ApiService();
  late final SchedulingRepository _scheduling = SupabaseSchedulingRepository();
  bool _loading = true;
  int _selectedDay = DateTime.now().weekday % 7;
  int? _providerId;
  String? _providerUid;

  final Map<int, TimeOfDay> _startTimes = {};
  final Map<int, TimeOfDay> _endTimes = {};
  final Map<int, TimeOfDay?> _lunchStarts = {};
  final Map<int, TimeOfDay?> _lunchEnds = {};
  final Map<int, bool> _activeDays = {};
  List<dynamic> _exceptions = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    // Initialize defaults synchronously to prevent null check crash if API fails
    for (int i = 0; i < 7; i++) {
      _startTimes[i] = const TimeOfDay(hour: 8, minute: 0);
      _endTimes[i] = const TimeOfDay(hour: 18, minute: 0);
      _lunchStarts[i] = const TimeOfDay(hour: 12, minute: 0);
      _lunchEnds[i] = const TimeOfDay(hour: 13, minute: 0);
      _activeDays[i] = (i > 0 && i < 6);
    }

    setState(() => _loading = true);
    try {
      final identity = await _resolveProviderIdentity();
      final providerId = identity.$1;
      final providerUid = identity.$2;
      final configResult = await _scheduling.getScheduleConfigResult(
        providerId,
      );
      final configs = configResult.configs.map((config) => config.toMap());
      final exceptions = await _scheduling.getScheduleExceptions(providerId);

      if (!mounted) return;
      _providerId = providerId;
      _providerUid = providerUid ?? configResult.providerUid;

      if (configs.isNotEmpty) {
        for (final conf in configs) {
          final day = conf['day_of_week'] as int;
          _startTimes[day] =
              _parseTime(conf['start_time']) ??
              const TimeOfDay(hour: 8, minute: 0);
          _endTimes[day] =
              _parseTime(conf['end_time']) ??
              const TimeOfDay(hour: 18, minute: 0);
          _lunchStarts[day] = _parseTime(
            conf['lunch_start']?.toString() ?? conf['break_start']?.toString(),
          );
          _lunchEnds[day] = _parseTime(
            conf['lunch_end']?.toString() ?? conf['break_end']?.toString(),
          );
          _activeDays[day] =
              conf['is_active'] == 1 ||
              conf['is_active'] == true ||
              conf['is_enabled'] == 1 ||
              conf['is_enabled'] == true;
        }
      }

      setState(() {
        _exceptions = exceptions;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<(int, String?)> _resolveProviderIdentity() async {
    final cachedId = _api.userIdInt;
    if (cachedId != null && cachedId > 0) {
      return (cachedId, null);
    }

    final profile = await _api.getMyProfile();
    final profileId = profile['id'] is num
        ? (profile['id'] as num).toInt()
        : int.tryParse('${profile['id'] ?? ''}');
    if (profileId == null || profileId <= 0) {
      throw Exception('Não foi possível identificar o prestador atual.');
    }
    final providerUid = (profile['supabase_uid'] ?? '').toString().trim();
    return (profileId, providerUid.isEmpty ? null : providerUid);
  }

  TimeOfDay? _parseTime(String? t) {
    if (t == null || !t.contains(':')) return null;
    try {
      final p = t.split(':');
      if (p.length < 2) return null;
      return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    } catch (_) {
      return null;
    }
  }

  bool _isValidSchedule(int day) {
    // Overnight schedules are now allowed (e.g., 22:00 to 05:00)
    // So strictly speaking, almost any pair of times is valid unless start == end?
    // Let's assume start == end IS invalid, but everything else is valid.
    final start = _startTimes[day]!;
    final end = _endTimes[day]!;

    if (start.hour == end.hour && start.minute == end.minute) {
      return false;
    }

    final lStart = _lunchStarts[day];
    final lEnd = _lunchEnds[day];

    if (lStart != null && lEnd != null) {
      final isLunchValid =
          (lEnd.hour > lStart.hour) ||
          (lEnd.hour == lStart.hour && lEnd.minute > lStart.minute);
      // Lunch should probably still be within the same day logic, but let's keep it simple for now.
      if (!isLunchValid) return false;
    }

    return true;
  }

  void _copyToAllDays() {
    final start = _startTimes[_selectedDay]!;
    final end = _endTimes[_selectedDay]!;
    final lStart = _lunchStarts[_selectedDay];
    final lEnd = _lunchEnds[_selectedDay];

    setState(() {
      for (int i = 0; i < 7; i++) {
        if (_activeDays[i] == true && i != _selectedDay) {
          _startTimes[i] = start;
          _endTimes[i] = end;
          _lunchStarts[i] = lStart;
          _lunchEnds[i] = lEnd;
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuração aplicada a todos os dias ativos'),
      ),
    );
  }

  Future<void> _save() async {
    // Validate all active days
    for (int i = 0; i < 7; i++) {
      if (_activeDays[i] == true && !_isValidSchedule(i)) {
        final days = [
          'Domingo',
          'Segunda',
          'Terça',
          'Quarta',
          'Quinta',
          'Sexta',
          'Sábado',
        ];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Horário inválido na ${days[i]}. Início e fim não podem ser iguais.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _selectedDay = i);
        return;
      }
    }

    setState(() => _loading = true);
    try {
      final List<Map<String, dynamic>> configs = [];
      for (int i = 0; i < 7; i++) {
        configs.add({
          'day_of_week': i,
          'start_time': _fmt(_startTimes[i]!),
          'end_time': _fmt(_endTimes[i]!),
          'lunch_start': _lunchStarts[i] != null
              ? _fmt(_lunchStarts[i]!)
              : null,
          'lunch_end': _lunchEnds[i] != null ? _fmt(_lunchEnds[i]!) : null,
          'is_enabled': _activeDays[i],
        });
      }

      debugPrint(
        '[ScheduleUI] payload configs=$configs exceptions=$_exceptions',
      );

      final providerId = _providerId;
      if (providerId == null || providerId <= 0) {
        throw Exception('Prestador não identificado para salvar agenda.');
      }
      final scheduleConfigs = configs
          .map((config) => ScheduleConfig.fromMap(config))
          .toList();
      await _scheduling.saveScheduleConfig(
        providerId,
        _providerUid,
        scheduleConfigs,
      );
      await _scheduling.saveScheduleExceptions(
        providerId,
        _exceptions
            .whereType<Map>()
            .map((exception) => exception.cast<String, dynamic>())
            .toList(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configurações salvas com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e, st) {
      debugPrint('[ScheduleUI] erro ao salvar: $e');
      debugPrint('[ScheduleUI] stack: $st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Horário de Funcionamento',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _save,
            icon: const Icon(LucideIcons.save, color: Colors.black),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: ElevatedButton.icon(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                  icon: const Icon(LucideIcons.save, size: 24),
                  label: const Text(
                    'SALVAR ALTERAÇÕES',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        _buildDaySelector(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildToggleCard(),
                if (_activeDays[_selectedDay] == true) ...[
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionTitle('Expediente Principal'),
                      TextButton.icon(
                        onPressed: _copyToAllDays,
                        icon: const Icon(Icons.copy_all, size: 16),
                        label: const Text(
                          'Copiar para todos',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blueGrey,
                        ),
                      ),
                    ],
                  ),
                  _buildTimeCard(
                    'Entrada e Saída',
                    _startTimes[_selectedDay]!,
                    _endTimes[_selectedDay]!,
                    (t) => setState(() => _startTimes[_selectedDay] = t),
                    (t) => setState(() => _endTimes[_selectedDay] = t),
                  ),
                  const SizedBox(height: 20),
                  _buildSectionTitle('Intervalo de Almoço'),
                  _buildTimeCard(
                    'Início e Fim',
                    _lunchStarts[_selectedDay],
                    _lunchEnds[_selectedDay],
                    (t) => setState(() => _lunchStarts[_selectedDay] = t),
                    (t) => setState(() => _lunchEnds[_selectedDay] = t),
                    canClear: true,
                  ),
                ],
                const SizedBox(height: 40),
                _buildSectionTitle('Datas Especiais e Feriados'),
                _buildExceptionsList(),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDaySelector() {
    final days = ['DOM', 'SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SAB'];
    return Container(
      height: 100,
      color: Theme.of(context).primaryColor,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        scrollDirection: Axis.horizontal,
        itemCount: 7,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final isSelected = _selectedDay == index;
          final isActive = _activeDays[index] ?? false;
          return GestureDetector(
            onTap: () => setState(() => _selectedDay = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 60,
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.black
                    : Colors.black.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? Colors.black : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    days[index],
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : (isActive ? Colors.black54 : Colors.black26),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    isActive ? LucideIcons.checkCircle2 : LucideIcons.circle,
                    size: 14,
                    color: isSelected
                        ? Theme.of(context).primaryColor
                        : Colors.black26,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildToggleCard() {
    final days = [
      'Domingo',
      'Segunda-feira',
      'Terça-feira',
      'Quarta-feira',
      'Quinta-feira',
      'Sexta-feira',
      'Sábado',
    ];
    final active = _activeDays[_selectedDay] ?? false;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: active ? Colors.green[50] : Colors.red[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              active ? LucideIcons.store : LucideIcons.doorClosed,
              color: active ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  days[_selectedDay],
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  active
                      ? 'Aberto para atendimento'
                      : 'Estabelecimento fechado',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ],
            ),
          ),
          Switch(
            value: active,
            onChanged: (v) => setState(() => _activeDays[_selectedDay] = v),
            activeThumbColor: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: Colors.blueGrey,
        ),
      ),
    );
  }

  Widget _buildTimeCard(
    String label,
    TimeOfDay? start,
    TimeOfDay? end,
    Function(TimeOfDay) onStart,
    Function(TimeOfDay) onEnd, {
    bool canClear = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTimePicker(
              start,
              (t) => onStart(t),
              'INÍCIO',
              canClear: false,
            ),
          ),
          Container(
            height: 40,
            width: 1,
            color: Colors.grey[100],
            margin: const EdgeInsets.symmetric(horizontal: 20),
          ),
          Expanded(
            child: _buildTimePicker(
              end,
              (t) => onEnd(t),
              'FIM',
              canClear: canClear,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimePicker(
    TimeOfDay? time,
    Function(TimeOfDay) onPick,
    String label, {
    bool canClear = false,
  }) {
    return GestureDetector(
      onTap: () async {
        final picked = await AppCupertinoPicker.showTimePicker(
          context: context,
          initialTime: time ?? const TimeOfDay(hour: 9, minute: 0),
          title: label,
        );
        if (picked != null) {
          onPick(picked);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                time != null
                    ? '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}'
                    : '--:--',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: time == null ? Colors.grey[300] : Colors.black,
                ),
              ),
              if (canClear && time != null)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => setState(() {
                    // Force clear both lunch times for data integrity
                    _lunchStarts[_selectedDay] = null;
                    _lunchEnds[_selectedDay] = null;
                  }),
                  icon: const Icon(Icons.close, size: 16, color: Colors.red),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExceptionsList() {
    return Column(
      children: [
        ..._exceptions.map((ex) {
          final isClosed = ex['is_closed'] == true;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  LucideIcons.calendarDays,
                  color: Colors.orange,
                  size: 20,
                ),
              ),
              title: Text(
                ex['date'],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                isClosed
                    ? 'Fechado'
                    : '${ex['start_time']} - ${ex['end_time']}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => setState(() => _exceptions.remove(ex)),
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _addException,
          icon: const Icon(Icons.add),
          label: const Text('Adicionar Data Especial'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
            side: const BorderSide(color: Colors.black12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            minimumSize: const Size(double.infinity, 50),
          ),
        ),
      ],
    );
  }

  Future<void> _addException() async {
    final d = await AppCupertinoPicker.showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      title: 'Adicionar data especial',
    );
    if (d != null) {
      final s =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      setState(() => _exceptions.add({'date': s, 'is_closed': true}));
    }
  }
}
