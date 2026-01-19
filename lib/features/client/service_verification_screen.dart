import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../shared/simple_video_player.dart';
import 'refund_request_screen.dart';

class ServiceVerificationScreen extends StatefulWidget {
  final String serviceId;
  const ServiceVerificationScreen({super.key, required this.serviceId});

  @override
  State<ServiceVerificationScreen> createState() =>
      _ServiceVerificationScreenState();
}

class _ServiceVerificationScreenState extends State<ServiceVerificationScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _service;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    try {
      final res = await _api.getServiceDetails(widget.serviceId);
      if (mounted) {
        setState(() {
          _service = res;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_service == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalhes do Serviço')),
        body: const Center(child: Text('Serviço não encontrado')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Confirmar Serviço'),
        backgroundColor: AppTheme.primaryYellow,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Info
            Text(
              _service!['profession'] ?? _service!['category_name'] ?? 'Serviço',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Prestador: ${_service!['provider_name'] ?? '---'}',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const Divider(height: 32),

            const Text(
              'Prova de Execução:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Proof Photo or Video
            if (_service!['proof_photo'] != null && _service!['proof_photo'].toString().isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: '${ApiService.baseUrl}/media/content?key=${Uri.encodeComponent(_service!['proof_photo'])}',
                  httpHeaders: _api.authHeaders,
                  width: double.infinity,
                  height: 250,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    height: 250,
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => Container(
                    height: 250,
                    color: Colors.grey[200],
                    child: const Center(child: Icon(Icons.broken_image, size: 48, color: Colors.grey)),
                  ),
                ),
              )
            else if (_service!['proof_video'] != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                   height: 250,
                   child: SimpleVideoPlayer(
                     videoUrl: '${ApiService.baseUrl}/media/content?key=${Uri.encodeComponent(_service!['proof_video'])}',
                     headers: _api.authHeaders,
                   ),
                ),
              )
            else
              const Text('Nenhuma foto ou vídeo anexado.'),

            const SizedBox(height: 32),
            
            const Text(
              'Descrição do serviço realizado:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _service!['description'] ?? 'Sem descrição adicional.',
              style: const TextStyle(fontSize: 16),
            ),

            const SizedBox(height: 48),

            // Action Buttons
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => _showRatingDialog(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('CONFIRMAR SERVIÇO', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                       Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RefundRequestScreen(
                            serviceId: widget.serviceId,
                            title: 'Abrir Reclamação',
                          ),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                    child: const Text('ABRIR RECLAMAÇÃO'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RefundRequestScreen(
                            serviceId: widget.serviceId,
                            title: 'Pedir Devolução',
                          ),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('PEDIR DEVOLUÇÃO'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRatingDialog() async {
    int rating = 0;
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Avalie o Serviço'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Como foi sua experiência?'),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return IconButton(
                      onPressed: () => setState(() => rating = index + 1),
                      icon: Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 32,
                      ),
                    );
                  }),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context), // Cancel
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: rating > 0 
                  ? () {
                      Navigator.pop(context);
                      _confirmService(rating);
                    }
                  : null,
                child: const Text('Enviar e Finalizar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmService(int rating) async {
    try {
      // 1. Send Rating (if endpoint exists, or bundle it)
      // For now, let's assume we send it to confirm-final or a separate rate endpoint.
      // Let's just pass it to confirm-final for simplicity in this demo.
      
      final res = await _api.post('/services/${widget.serviceId}/confirm-final', {
        'rating': rating,
      });

      if (res['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Serviço avaliado e finalizado!')),
          );
          context.go('/home');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao confirmar: $e')),
        );
      }
    }
  }
}
