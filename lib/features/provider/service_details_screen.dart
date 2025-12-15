import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';

class ServiceDetailsScreen extends StatefulWidget {
  final String serviceId;
  const ServiceDetailsScreen({super.key, required this.serviceId});

  @override
  State<ServiceDetailsScreen> createState() => _ServiceDetailsScreenState();
}

class _ServiceDetailsScreenState extends State<ServiceDetailsScreen> {
  final _api = ApiService();
  bool _isLoading = true;
  Map<String, dynamic>? _service;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    try {
      final data = await _api.getServiceDetails(widget.serviceId);
      if (mounted) {
        setState(() {
          _service = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar detalhes: $e')));
      }
    }
  }

  Future<void> _acceptService() async {
    setState(() => _isLoading = true);
    try {
      await _api.acceptService(widget.serviceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Serviço aceito!'), backgroundColor: Colors.green),
        );
        _loadDetails(); // Recarregar dados para atualizar botões
      }
    } catch (e) {
      if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao aceitar: $e')));
      }
    }
  }

  Future<void> _startService() async {
    setState(() => _isLoading = true);
    try {
      await _api.startService(widget.serviceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Serviço iniciado (em progresso)!'), backgroundColor: Colors.blue),
        );
        _loadDetails();
      }
    } catch (e) {
      if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao iniciar: $e')));
      }
    }
  }

  Future<void> _completeService() async {
    setState(() => _isLoading = true);
    try {
      await _api.completeService(widget.serviceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Serviço finalizado!'), backgroundColor: Colors.green),
        );
        // Após finalizar, pode-se navegar de volta para a lista de serviços
        context.pop(); 
      }
    } catch (e) {
      if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao finalizar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_service == null) {
      return const Scaffold(body: Center(child: Text('Serviço não encontrado')));
    }

    final s = _service!;
    final status = s['status'] as String;

    // Define service status flags
    final bool canAccept = status == 'pending'; // Pending -> Accept button visible
    final bool isAcceptedButNotStarted = status == 'accepted'; // Accepted -> Start button visible
    final bool isInProgress = status == 'in_progress'; // In Progress -> Complete button visible
    final bool isActive = isAcceptedButNotStarted || isInProgress; // Active -> Chat and client phone visible
    final bool isFinished = status == 'completed' || status == 'cancelled'; // Finished/Cancelled -> No buttons

    return Scaffold(
      appBar: AppBar(title: const Text('Detalhes do serviço')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Category Icon / Image
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: AppTheme.primaryPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.wrench, size: 48, color: AppTheme.primaryPurple),
                      const SizedBox(height: 8),
                      Text(s['category_name'] ?? 'Serviço', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryPurple)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Client Info (visible when active)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                          CircleAvatar(
                            backgroundColor: AppTheme.secondaryOrange,
                            backgroundImage: s['client_avatar'] != null ? NetworkImage(s['client_avatar']) : null,
                            child: s['client_avatar'] == null ? Text(s['client_name']?[0] ?? 'C', style: const TextStyle(color: Colors.white)) : null
                          ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s['client_name'] ?? 'Cliente', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              if (isActive) // Show phone only if active
                                Text(s['client_phone'] ?? 'Telefone indisponível', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                              if (isFinished)
                                Text('Status: ${s['status'] == 'completed' ? 'Concluído' : 'Cancelado'}', style: TextStyle(fontSize: 14, color: s['status'] == 'completed' ? Colors.green : Colors.red)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    const Text('Descrição do problema', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text(s['description'] ?? 'Sem descrição'),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Location
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Localização', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(LucideIcons.mapPin, color: Colors.grey, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(isActive ? 'Endereço completo' : 'Endereço aproximado')),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, left: 24),
                      // Full address if active, otherwise showing a sample like City/Neighborhood
                      child: Text(
                        isActive ? s['full_address'] ?? s['address'] ?? 'Não informado' : s['address'] ?? 'Não informado',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Payment
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  // GRADIENT REMOVIDO E SUBSTITUÍDO PELA COR SÓLIDA #9803fc
                  color: const Color(0xFF9803FC), 
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(LucideIcons.dollarSign, color: Colors.white),
                        SizedBox(width: 8),
                        Text('Valor a receber', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'R\$ ${s['provider_amount'] ?? s['price_estimated']}',
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // --- ACTION BUTTONS ---

              // 1. ACCEPT button (Visible only if PENDING)
              if (canAccept)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _acceptService,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryPurple,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 56),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Aceitar serviço'),
                      ),
                    ),
                  ],
                ),

              // 2. CHAT + STATUS buttons (Visible only if ACCEPTED or IN_PROGRESS)
              if (isActive)
                Column(
                  children: [
                    // CHAT button (Always visible when active)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              context.push('/chat', extra: s['id']);
                            },
                            icon: const Icon(LucideIcons.messageCircle),
                            label: const Text('Chat com Cliente'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryPurple,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, 56),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // START button (Visible only if ACCEPTED, not started)
                    if (isAcceptedButNotStarted)
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _startService,
                              icon: const Icon(LucideIcons.play),
                              label: const Text('Iniciar Serviço'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.secondaryOrange,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 56),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                        ],
                      ),

                    // COMPLETE button (Visible only if IN_PROGRESS)
                    if (isInProgress)
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _completeService,
                              icon: const Icon(LucideIcons.checkCircle),
                              label: const Text('Finalizar Serviço'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 56),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }
}