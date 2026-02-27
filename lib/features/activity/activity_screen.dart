import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../core/theme/app_theme.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ApiService _api = ApiService();
  bool _isLoading = true;
  List<dynamic> _services = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final data = await _api.getMyServices();
      if (mounted) {
        setState(() {
          _services = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Atividade',
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w800,
            color: AppTheme.textDark,
            fontSize: 24,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryYellow,
          indicatorWeight: 3,
          labelColor: AppTheme.textDark,
          unselectedLabelColor: AppTheme.textMuted,
          labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 14),
          tabs: const [
            Tab(text: 'Próximas'),
            Tab(text: 'Anteriores'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildActivityList(isPast: false),
                _buildActivityList(isPast: true),
              ],
            ),
    );
  }

  Widget _buildActivityList({required bool isPast}) {
    final filtered = _services.where((s) {
      final status = s['status']?.toString().toLowerCase();
      if (isPast) {
        return status == 'completed' || status == 'cancelled' || status == 'finished';
      }
      return status != 'completed' && status != 'cancelled' && status != 'finished';
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.history, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              isPast ? 'Nenhuma atividade recente' : 'Sem agendamentos próximos',
              style: GoogleFonts.manrope(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final item = filtered[index];
        return _buildActivityCard(item);
      },
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> item) {
    final date = DateTime.tryParse(item['created_at'] ?? '');
    final formattedDate = date != null ? DateFormat('dd/MM/yyyy • HH:mm').format(date) : '';
    final status = item['status']?.toString().toUpperCase() ?? 'PENDENTE';
    
    Color statusColor = Colors.orange;
    if (status.contains('OK') || status.contains('CONCLUÍDO') || status.contains('FINISHED')) statusColor = Colors.green;
    if (status.contains('CANCEL')) statusColor = Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppTheme.backgroundLight,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              item['service_type'] == 'uber' ? LucideIcons.car : LucideIcons.wrench,
              color: AppTheme.textDark,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['description'] ?? 'Serviço solicitado',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppTheme.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  formattedDate,
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              status,
              style: GoogleFonts.manrope(
                color: statusColor,
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
