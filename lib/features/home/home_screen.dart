import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import 'widgets/service_card.dart';
import '../../services/api_service.dart';
import '../../services/realtime_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();
  List<dynamic> _services = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadServices();
    final rt = RealtimeService();
    rt.connect();
    rt.on('service.created', (_) => _loadServices());
    rt.on('service.status', (_) => _loadServices());
  }

  Future<void> _loadServices() async {
    try {
      final services = await _api.getMyServices();
      if (mounted) {
        setState(() {
          _services = services;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        // Silently fail or show snackbar in real app
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadServices,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                _buildHeader(),

                const SizedBox(height: 16),

                // CTA Principal
                Center(
                  child: Container(
                    height: 56,
                    width: 200,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primaryPurple, AppTheme.secondaryOrange],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryPurple.withOpacity(0.4),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                           context.push('/create-service');
                        },
                        borderRadius: BorderRadius.circular(30),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.plus, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'Pedir serviço', 
                              style: TextStyle(
                                color: Colors.white, 
                                fontWeight: FontWeight.bold,
                                fontSize: 16
                              )
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 40),

                // Meus Serviços (Real API)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    'Meus Pedidos',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ),
                const SizedBox(height: 16),
                
                SizedBox(
                  height: 160,
                  child: _isLoading 
                    ? const Center(child: CircularProgressIndicator())
                    : _services.isEmpty 
                        ? Center(child: Text('Nenhum pedido recente', style: TextStyle(color: Colors.grey[400])))
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            itemCount: _services.length,
                            separatorBuilder: (context, index) => const SizedBox(width: 16),
                            itemBuilder: (context, index) {
                              final service = _services[index];
                              return ServiceCard(
                                status: service['status'] ?? 'pending',
                                providerName: service['provider_name'] ?? 'Aguardando...',
                                distance: '---', // Calculado real seria via geolocation
                                category: service['category_name'] ?? service['description'] ?? 'Serviço',
                              );
                            },
                          ),
                ),

                const SizedBox(height: 32),

                // Banner Garantia
                _buildWarrantyBanner(),
                
                const SizedBox(height: 80), 
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryPurple, AppTheme.secondaryOrange],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(LucideIcons.user, color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text('Bem-vindo(a),', style: TextStyle(fontSize: 12, color: Colors.grey)),
                   Text('Cliente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                ],
              ),
            ],
          ),
          const Text(
            'Conserta+', 
            style: TextStyle(
              color: AppTheme.primaryPurple,
              fontWeight: FontWeight.bold,
              fontSize: 18
            )
          ),
        ],
      ),
    );
  }

  Widget _buildWarrantyBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primaryPurple, AppTheme.secondaryOrange],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle
              ),
              child: const Center(child: Text('🛡️', style: TextStyle(fontSize: 24))),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Garantia de 7 dias',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Todos os serviços têm garantia. Se algo der errado, resolvemos sem custo adicional.',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
