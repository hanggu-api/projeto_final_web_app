import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/data_gateway.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/media_service.dart';
import '../../services/remote_theme_service.dart';
import '../../services/realtime_service.dart';
import '../../widgets/skeleton_loader.dart';

class ProviderHomeFixed extends StatefulWidget {
  const ProviderHomeFixed({super.key});

  @override
  State<ProviderHomeFixed> createState() => _ProviderHomeFixedState();
}

class _ProviderHomeFixedState extends State<ProviderHomeFixed> {
  final _api = ApiService();
  final _media = MediaService();
  Uint8List? _avatarBytes;
  String? _userName;
  int? _currentUserId;
  int _unreadCount = 0;
  
  // Schedule State
  List<Map<String, dynamic>> _slots = [];
  Timer? _slotRefreshTimer;
  StreamSubscription? _realtimeSub;
  bool _loadingSlots = true;
  DateTime _selectedDate = DateTime.now().toUtc().subtract(const Duration(hours: 3));

  // Notification State
  final ValueNotifier<List<Map<String, dynamic>>> _notificationsVN =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  @override
  void initState() {
    super.initState();
    _checkLocationPermission(); 
    _loadData();
    _setupRealtimeListener();
  }

  @override
  void dispose() {
    _slotRefreshTimer?.cancel();
    _realtimeSub?.cancel();
    _notificationsVN.dispose();
    RealtimeService().stopLocationUpdates(); 
    super.dispose();
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
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Agenda atualizada! 📅'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
          _loadSchedule(_selectedDate);
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
    _loadAvatar();
    _loadProfile();
    // Real-time notifications handled by DataGateway
  }

  Future<void> _loadAvatar() async {
    try {
      final bytes = await _media.loadMyAvatarBytes();
      if (mounted && bytes != null) {
        setState(() => _avatarBytes = bytes);
      }
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    try {
      final user = await _api.getMyProfile();

      if (mounted) {
        setState(() {
          _userName = user['name'] ?? user['full_name'];
        });

        if (user['id'] != null) {
          final userId = user['id'] is int
              ? user['id']
              : int.tryParse(user['id'].toString());

          if (userId != null) {
            _currentUserId = userId;
            // Authenticate socket for chat/events
            RealtimeService().authenticate(userId);
            
            // Fixed provider: Ensure tracking is OFF
            RealtimeService().stopLocationUpdates();

            // Start loading slots
            _loadSchedule(_selectedDate);
            _slotRefreshTimer?.cancel();
            _slotRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
              _loadSchedule(_selectedDate);
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadSchedule(DateTime displayDate) async {
    if (_currentUserId == null) return;
    try {
      if (_slots.isEmpty) setState(() => _loadingSlots = true);
      final dateStr = "${displayDate.year}-${displayDate.month.toString().padLeft(2, '0')}-${displayDate.day.toString().padLeft(2, '0')}";
      
      final slots = await _api.getProviderSlots(_currentUserId!, date: dateStr);
      if (mounted) {
        setState(() {
          _slots = slots;
          _loadingSlots = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading slots: $e');
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  Future<void> _toggleSlotBusy(Map<String, dynamic> slot) async {
    try {
      final start = DateTime.parse(slot['start_time']);
      final status = slot['status'];
      final appointmentId = slot['appointment_id'];

      if (status == 'free') {
        await _api.markSlotBusy(start);
        _loadSchedule(_selectedDate);
      } else if (status == 'busy' && appointmentId != null) {
        await _api.deleteAppointment(appointmentId);
        _loadSchedule(_selectedDate);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este horário já está ocupado ou agendado.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao atualizar status: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: _buildHeader(context),
          ),
        ],
        body: Column(
          children: [
            _buildPainelHeader(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _loadSchedule(_selectedDate),
                child: _loadingSlots 
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
      padding: const EdgeInsets.only(
        top: 60,
        left: 24,
        right: 24,
        bottom: 32,
      ),
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
              onTap: () => context.push('/provider-profile'),
              child: Row(
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: Supabase.instance.client.auth.currentUser?.id != null
                        ? DataGateway().watchNotifications(Supabase.instance.client.auth.currentUser!.id)
                        : const Stream.empty(),
                    builder: (context, snapshot) {
                        final notifications = snapshot.data ?? [];
                        final unreadCount = notifications.where((n) => n['read'] != true && n['is_read'] != true).length;

                        return Stack(
                          alignment: Alignment.topRight,
                          children: [
                            IconButton(
                              icon: const Icon(LucideIcons.bell, color: Colors.black87),
                              onPressed: () async {
                                  await context.push('/notifications');
                                  // Refresh manual data if needed, but stream updates automatically
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
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        );
                    }
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Saldo disponível',
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.wallet,
                    color: Colors.black87,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'R\$ 0,00',
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPainelHeader() {
    return Container(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Painel de Serviços',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 16),
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

  Widget _buildTodayTabButton() {
    final nowBr = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    final isSelected = _selectedDate.day == nowBr.day && 
                      _selectedDate.month == nowBr.month && 
                      _selectedDate.year == nowBr.year;

    return Container(
      width: 120,
      margin: const EdgeInsets.only(left: 24),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _selectedDate = nowBr;
              });
              _loadSchedule(_selectedDate);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Hoje',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                    color: isSelected ? Colors.black : Colors.grey[400],
                  ),
                ),
              ),
            ),
          ),
          if (isSelected)
            Container(
              height: 2,
              width: 50,
              color: Colors.black,
            ),
        ],
      ),
    );
  }

  Widget _buildPainelDateSelector() {
    return SizedBox(
      height: 90,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: 14,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final nowBr = DateTime.now().toUtc().subtract(const Duration(hours: 3));
          final date = nowBr.add(Duration(days: index + 1));
          final isSelected = date.day == _selectedDate.day && 
                            date.month == _selectedDate.month &&
                            date.year == _selectedDate.year;
          
          final dayName = index == 0 ? "Amanhã" : _getDayName(date.weekday);
          
          return Center(
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedDate = date;
                });
                _loadSchedule(_selectedDate);
              },
              child: Container(
                width: 75,
                height: 75,
                decoration: BoxDecoration(
                  color: isSelected ? Theme.of(context).primaryColor : Colors.grey[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? Theme.of(context).primaryColor : Colors.grey[200]!,
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      dayName,
                      style: TextStyle(
                        fontSize: 11,
                        color: isSelected ? Colors.black : Colors.grey[600],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${date.day}/${date.month}",
                      style: TextStyle(
                        fontSize: 18,
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
    if (_loadingSlots) {
      return const Center(child: Text("Carregando agenda..."));
    }

    final nowUtc = DateTime.now().toUtc();
    final List<Map<String, dynamic>> filteredSlots = _slots.where((slot) {
      final endTimeStr = slot['end_time']?.toString();
      if (endTimeStr == null) return false;
      final end = DateTime.tryParse(endTimeStr);
      if (end == null) return false;
      return end.toUtc().isAfter(nowUtc);
    }).toList();

    if (filteredSlots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.calendarX, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _slots.isEmpty 
                  ? "Nenhum horário configurado." 
                  : "Não há mais horários para hoje.",
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _slots.isEmpty
                  ? "Verifique sua configuração de dias e horários."
                  : "Você completou seu expediente ou o estabelecimento está fechado.",
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => _loadSchedule(_selectedDate),
              icon: const Icon(Icons.refresh),
              label: const Text("Atualizar"),
            ),
          ],
        ),
      );
    }

    // Sort slots by time
    final sortedSlots = List<Map<String, dynamic>>.from(filteredSlots);
    sortedSlots.sort((a, b) {
      final t1 = DateTime.tryParse(a['start_time'].toString()) ?? DateTime.now();
      final t2 = DateTime.tryParse(b['start_time'].toString()) ?? DateTime.now();
      return t1.compareTo(t2);
    });

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: sortedSlots.length,
      itemBuilder: (context, index) {
        final slot = sortedSlots[index];
        final status = slot['status'];

        final start = DateTime.parse(slot['start_time']).toUtc();
        final end = DateTime.parse(slot['end_time']).toUtc();
        final isCurrent = nowUtc.isAfter(start.subtract(const Duration(minutes: 1))) && 
                          nowUtc.isBefore(end);
        
        final nowBr = nowUtc.subtract(const Duration(hours: 3));
        final isFixedDayToday = _selectedDate.day == nowBr.day && 
                               _selectedDate.month == nowBr.month && 
                               _selectedDate.year == nowBr.year;
        final isActuallyNow = isCurrent && isFixedDayToday;

        // Default Style (Free/Available) - Now Light Gray with No Border
        Color borderColor = Colors.transparent; 
        Color textColor = Colors.black87; // Darker text for contrast on gray
        Color bgColor = Colors.grey[100]!; // Light Gray Background
        Color timeColor = Colors.black;
        String statusLabel = 'Livre';

        if (status == 'booked') {
          final isArrived = slot['service_status'] == 'client_arrived';
          if (isArrived) {
            borderColor = const Color(0xFF1976D2); // Material Blue 700
            textColor = Colors.white;
            bgColor = const Color(0xFF2196F3); // Material Blue 500
            timeColor = Colors.white;
            statusLabel = 'Chegou';
          } else {
            borderColor = const Color(0xFFE65100); 
            textColor = Colors.white;
            bgColor = const Color(0xFFEF6C00);
            timeColor = Colors.white;
            statusLabel = 'Agendado';
          }
        } else if (status == 'busy') {
          // Busy/Blocked
          borderColor = Colors.transparent;
          textColor = Colors.blue[700]!; // Keep blue text to distinguish? Or Gray?
          // User asked to remove blue border. 
          // Let's keep a distinct background or text for Blocked?
          // For now, let's make it similar to free but maybe darker gray or keep blue text.
          bgColor = Colors.blue[50]!; 
          statusLabel = 'Bloqueado';
        } else if (status == 'lunch') {
          borderColor = const Color(0xFFFF9800);
          textColor = const Color(0xFFFF9800);
          bgColor = const Color(0xFFFFF7F0);
          statusLabel = 'Almoço';
        } else if (isActuallyNow) {
          borderColor = const Color(0xFF4CAF50);
          textColor = const Color(0xFF4CAF50);
          bgColor = const Color(0xFFF1FDF1);
          statusLabel = 'AGORA';
        }

        return InkWell(
          onTap: () {
            if (status == 'booked') {
              _showAppointmentDetails(slot);
            } else if (status == 'free') {
              _toggleSlotBusy(slot);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: borderColor,
                width: isActuallyNow ? 2.5 : (borderColor == Colors.transparent ? 0 : 1.5),
              ),
              boxShadow: [
                ...RemoteThemeService().getShadow(),
                if (isActuallyNow)
                  BoxShadow(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  slot['start_time'].toString().contains('T') 
                    ? slot['start_time'].toString().split('T')[1].substring(0, 5)
                    : "${DateTime.parse(slot['start_time']).hour.toString().padLeft(2, '0')}:${DateTime.parse(slot['start_time']).minute.toString().padLeft(2, '0')}",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: timeColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAppointmentDetails(Map<String, dynamic> slot) {
    debugPrint("🔍 [DEBUG] Opening Slot Details: $slot");
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent, // Transparent to let Container handle styling
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black, width: 0.5), // Thin black border
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  'Detalhes do Agendamento',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16, // Reduced font size
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
                    image: slot['client_avatar'] != null
                        ? DecorationImage(
                            image: NetworkImage(slot['client_avatar']),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: slot['client_avatar'] == null
                      ? const Icon(Icons.person, size: 40, color: Colors.grey)
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  slot['client_name'] ?? 'Cliente',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
              ),
              _buildDetailRow(LucideIcons.briefcase, 'Serviço', slot['service_profession'] ?? 'Serviço'),
              if (slot['service_description'] != null)
                 Padding(
                    padding: const EdgeInsets.only(left: 32, bottom: 12),
                    child: Text(slot['service_description'], style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                 ),
              
              // Preço Detalhado
              if (slot['price_total'] != null) ...[
                _buildDetailRow(LucideIcons.banknote, 'Valor Total (100%)', "R\$ ${double.tryParse(slot['price_total'].toString())?.toStringAsFixed(2).replaceAll('.', ',') ?? '0,00'}"),
                if (slot['price_paid'] != null && double.parse(slot['price_paid'].toString()) > 0)
                  _buildDetailRow(LucideIcons.checkCircle2, 'Pago (Entrada 30%)', "R\$ ${double.tryParse(slot['price_paid'].toString())?.toStringAsFixed(2).replaceAll('.', ',') ?? '0,00'}", color: Colors.green[600]),
                
                _buildDetailRow(
                  LucideIcons.alertCircle, 
                  'A Pagar (Restante 70%)', 
                  "R\$ ${( (double.tryParse(slot['price_total'].toString()) ?? 0) - (double.tryParse(slot['price_paid']?.toString() ?? '0') ?? 0) ).toStringAsFixed(2).replaceAll('.', ',')}",
                  color: Colors.orange[800]
                ),
              ],

              _buildDetailRow(LucideIcons.clock, 'Horário', "${slot['start_time'].toString().substring(11, 16)} - ${slot['end_time'].toString().substring(11, 16)}"),
              const SizedBox(height: 24),
              Column(
                children: [
                   SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                         Navigator.pop(context);
                         if (slot['service_id'] != null) {
                           context.push(
                             '/chat/${slot['service_id']}', 
                             extra: {
                               'otherName': slot['client_name'],
                               'otherAvatar': slot['client_avatar'],
                               'serviceId': slot['service_id'].toString(), // Ensure string
                             }
                           );
                         } else {
                           ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(content: Text("Erro: ID do serviço não encontrado."))
                           );
                         }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF), // Blue color
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(LucideIcons.messageSquare, size: 20),
                      label: const Text(
                        'Enviar mensagem para o cliente',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  
                  // Botão Confirmar Pagamento Manual (Rosa/Magenta)
                  // Mostra o botão se o serviço existe e não está finalizado nem cancelado
                  if (slot['service_id'] != null && 
                      slot['service_status'] != 'completed' && 
                      slot['service_status'] != 'cancelled')
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
                                content: const Text('Isso marcará o serviço como finalizado com sucesso e o pagamento total como recebido (incluindo o restante de 70%).'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true), 
                                    child: const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true && mounted) {
                              try {
                                await ApiService().confirmPaymentManual(slot['service_id'].toString());
                                Navigator.pop(context); // Fecha o modal de detalhes
                                _loadSchedule(_selectedDate); // Recarrega a agenda
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Serviço finalizado com sucesso! ✅'), 
                                    backgroundColor: Colors.green
                                  ),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Erro ao finalizar: $e'), 
                                    backgroundColor: Colors.red
                                  ),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFC2185B), // Magenta
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          icon: const Icon(LucideIcons.checkCircle2, size: 20),
                          label: const Text(
                            'Finalizar e Confirmar Recebimento',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                        )
                      ),
                      child: const Text('Fechar', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, {Color? color}) {
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
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(value, style: TextStyle(
                  fontSize: 15, 
                  fontWeight: FontWeight.w500,
                  color: color ?? Colors.black87,
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case 1: return "Seg";
      case 2: return "Ter";
      case 3: return "Qua";
      case 4: return "Qui";
      case 5: return "Sex";
      case 6: return "Sáb";
      case 7: return "Dom";
      default: return "";
    }
  }
}
