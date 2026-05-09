import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/data_gateway.dart';
import '../../services/realtime_service.dart';
import '../shared/widgets/notification_dropdown_menu.dart';
import 'medical_agenda_view.dart';
import 'schedule_edit_screen.dart';
import '../../widgets/skeleton_loader.dart';

class MedicalHomeScreen extends StatefulWidget {
  const MedicalHomeScreen({super.key});

  @override
  State<MedicalHomeScreen> createState() => _MedicalHomeScreenState();
}

class _MedicalHomeScreenState extends State<MedicalHomeScreen> {
  bool _isLoading = true;
  List<dynamic> _pendingRequests = [];
  List<dynamic> _confirmedAppointments = [];
  List<dynamic> _schedules = [];
  List<dynamic> _exceptions = [];
  final _api = ApiService();
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initRealtime();
  }

  void _initRealtime() async {
    final rt = RealtimeService();
    // Fetch profile to get ID
    try {
      final profile = await _api.getMyProfile();
      if (profile['id'] != null) {
        final userId = profile['id'] is int
            ? profile['id']
            : int.tryParse(profile['id'].toString());
        if (userId != null) {
          rt.init(userId);
        }
      }
    } catch (e) {
      debugPrint('Error getting profile for RT init: $e');
    }

    rt.on('chat.message', _handleChatMessage);
    rt.on('chat_message', _handleChatMessage);
    rt.on('appointment.new', _handleNewAppointment);
    rt.on('appointment.cancelled', _handleAppointmentCancelled);
    rt.connect();

    final unread = await DataGateway().loadUnreadChatCount();
    if (mounted) {
      setState(() {
        _unreadCount = unread;
      });
    }
  }

  void _handleChatMessage(dynamic data) async {
    if (!mounted) return;
    final unread = await DataGateway().loadUnreadChatCount();
    if (!mounted) return;
    setState(() {
      _unreadCount = unread;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nova Mensagem: ${data['message'] ?? ''}'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Ver',
            onPressed: () {
              final id = data['service_id'] ?? data['id'];
              if (id != null) {
                context.push('/chat/${id.toString()}');
              }
            },
          ),
        ),
      );
    }
  }

  void _handleNewAppointment(dynamic data) {
    if (!mounted) return;
    _loadData(); // Refresh UI
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Novo agendamento recebido!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleAppointmentCancelled(dynamic data) {
    if (!mounted) return;
    _loadData(); // Refresh UI
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Um agendamento foi cancelado.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load Services (Requests/Appointments)
      final services = await DataGateway().loadMyServices();

      // Sprint 2: Supabase SDK em vez de GET /provider/setup
      final providerId = _api.userId;
      List<Map<String, dynamic>> schedulesData = [];
      List<Map<String, dynamic>> exceptionsData = [];

      if (providerId != null) {
        schedulesData = await DataGateway().loadProviderSchedules(providerId);
        exceptionsData = await DataGateway().loadProviderScheduleExceptions(
          providerId,
        );
      }

      setState(() {
        _pendingRequests = services
            .where((s) => s['status'] == 'pending')
            .toList();
        _confirmedAppointments = services
            .where(
              (s) =>
                  s['status'] == 'accepted' ||
                  s['status'] == 'in_progress' ||
                  s['status'] == 'confirmed' ||
                  s['status'] == 'waiting_client_confirmation',
            )
            .toList();

        _schedules = schedulesData
            .map((s) => Map<String, dynamic>.from(s))
            .toList();
        _exceptions = exceptionsData
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading medical data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openScheduleSettings() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ScheduleEditScreen()),
    );

    if (result == true) {
      _loadData();
    }
  }

  Future<void> _handleRequest(Map<String, dynamic> request, bool accept) async {
    final id = request['id'];
    if (id == null) return;

    try {
      await _api.updateServiceStatus(
        id.toString(),
        accept ? 'accepted' : 'refused',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept
                  ? 'Agendamento confirmado!'
                  : 'Agendamento recusado. O crédito foi estornado ao cliente.',
            ),
            backgroundColor: accept ? Colors.green : Colors.red,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao atualizar status: $e')));
      }
    }
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final date = DateTime.tryParse(request['start_time'] ?? '');
    final dateStr = date != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(date)
        : 'Data inválida';
    final clientName = request['client_name'] ?? 'Cliente';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryPurple.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person,
                    color: AppTheme.primaryPurple,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clientName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        request['service_name'] ?? 'Consulta',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Pendente',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(dateStr),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _handleRequest(request, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: const Text('Recusar'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _handleRequest(request, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Aceitar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Painel Médico',
            style: TextStyle(color: Colors.black),
          ),
          backgroundColor: AppTheme.primaryYellow,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
          actions: [
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications),
                  onPressed: () => NotificationDropdownMenu.show(context),
                ),
                if (_unreadCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 14,
                        minHeight: 14,
                      ),
                      child: Text(
                        '$_unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          ],
          bottom: TabBar(
            labelColor: AppTheme.primaryPurple,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppTheme.primaryPurple,
            tabs: [
              Tab(text: 'Solicitações', icon: Icon(Icons.notifications)),
              Tab(text: 'Agenda', icon: Icon(Icons.calendar_month)),
            ],
          ),
        ),
        body: _isLoading
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: List.generate(
                    3,
                    (index) => const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: CardSkeleton(),
                    ),
                  ),
                ),
              )
            : TabBarView(
                children: [
                  // 0. Requests
                  RefreshIndicator(
                    onRefresh: _loadData,
                    child: _pendingRequests.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 100),
                              Center(
                                child: Text(
                                  'Nenhuma solicitação pendente',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _pendingRequests.length,
                            itemBuilder: (context, index) =>
                                _buildRequestCard(_pendingRequests[index]),
                          ),
                  ),
                  // 1. Agenda
                  MedicalAgendaView(
                    appointments: _confirmedAppointments,
                    schedules: _schedules,
                    exceptions: _exceptions,
                    onSettingsTap: _openScheduleSettings,
                    onDateSelected: (date) {},
                  ),
                ],
              ),
      ),
    );
  }
}
