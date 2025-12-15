import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/realtime_service.dart';

class ProviderHomeScreen extends StatefulWidget {
  const ProviderHomeScreen({super.key});

  @override
  State<ProviderHomeScreen> createState() => _ProviderHomeScreenState();
}

class _ProviderHomeScreenState extends State<ProviderHomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = ApiService();
  bool _isLoading = true;
  List<dynamic> _availableServices = [];
  List<dynamic> _myServices = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    final rt = RealtimeService();
    rt.connect();
    rt.on('service.created', (_) => _loadData());
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final available = await _api.getAvailableServices();
      final my = await _api.getMyServices();
      
      if (mounted) {
        setState(() {
          _availableServices = available;
          _myServices = my;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar: $e')));
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [AppTheme.primaryPurple, AppTheme.secondaryOrange]),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          onTap: () => context.push('/provider-profile'),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                child: const Center(child: Text('P', style: TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.bold))),
                              ),
                              const SizedBox(width: 12),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Olá,', style: TextStyle(color: Colors.white70)),
                                  Text('Prestador', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Saldo disponível', style: TextStyle(color: Colors.white70)),
                            Row(
                              children: [
                                Icon(LucideIcons.wallet, color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Text('R\$ 0,00', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            // Notification Card (Overlap) - Show first available service
            if (_availableServices.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Transform.translate(
                  offset: const Offset(0, -24),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.secondaryOrange.withOpacity(0.3)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: AppTheme.secondaryOrange.withOpacity(0.1), shape: BoxShape.circle),
                          child: const Text('🆕', style: TextStyle(fontSize: 20)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Nova oportunidade!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 4),
                              Text('${_availableServices[0]['category_name']} - ${_availableServices[0]['address']}', 
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.grey, fontSize: 12)
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: () => context.push('/service-details', extra: _availableServices[0]['id']), 
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryPurple,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(120, 36),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Ver detalhes'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
  
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Painel de Serviços', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    // Tabs
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
                      ),
                      child: TabBar(
                        controller: _tabController,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.grey[600],
                        indicator: BoxDecoration(
                          color: AppTheme.primaryPurple,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        tabs: const [
                          Tab(text: 'Disponíveis'),
                          Tab(text: 'Meus'),
                          Tab(text: 'Finalizados'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
  
            // List Content
            SliverFillRemaining(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator()) 
                : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildServiceList(_availableServices, isAvailable: true),
                    _buildServiceList(_myServices.where((s) => s['status'] == 'accepted' || s['status'] == 'in_progress').toList()),
                    _buildServiceList(_myServices.where((s) => s['status'] == 'completed' || s['status'] == 'cancelled').toList()),
                  ],
                ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadData,
        backgroundColor: AppTheme.primaryPurple,
        child: const Icon(LucideIcons.refreshCw),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }
  
  Widget _buildServiceList(List<dynamic> items, {bool isAvailable = false}) {
    if (items.isEmpty) {
      return const Center(child: Text('Nenhum serviço encontrado', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        final price = item['provider_amount'] ?? item['price_estimated'] ?? 0;
        return InkWell(
          onTap: () {
            // Passa o ID para a tela de detalhes
            context.push('/service-details', extra: item['id']);
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['category_name'] ?? 'Serviço', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(LucideIcons.mapPin, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Expanded(child: Text(item['address'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('R\$ $price', style: const TextStyle(color: AppTheme.primaryPurple, fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 8),
                    _buildStatusBadge(item['status'] ?? 'pending'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String text;
    switch (status) {
      case 'inProgress': 
        color = Colors.orange;
        text = 'Em andamento';
        break;
      case 'accepted': 
        color = Colors.blue;
        text = 'Aceito';
        break;
      case 'completed': 
        color = Colors.green;
        text = 'Concluído';
        break;
      case 'cancelled': 
        color = Colors.red;
        text = 'Cancelado';
        break;
      default: 
        color = Colors.grey;
        text = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
