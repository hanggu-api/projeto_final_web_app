import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../services/api_service.dart';

class ProviderArrivedModal extends StatefulWidget {
  final String serviceId;
  final Map<String, dynamic>? initialData;

  const ProviderArrivedModal({
    super.key,
    required this.serviceId,
    this.initialData,
  });

  @override
  State<ProviderArrivedModal> createState() => _ProviderArrivedModalState();
}

class _ProviderArrivedModalState extends State<ProviderArrivedModal> {
  final _api = ApiService();
  bool _isLoading = true;
  Map<String, dynamic>? _serviceData;

  @override
  void initState() {
    super.initState();
    _loadServiceDetails();
  }

  Future<void> _loadServiceDetails() async {
    // If we have full data (including address), use it
    if (widget.initialData != null &&
        widget.initialData!.containsKey('address')) {
      setState(() {
        _serviceData = widget.initialData;
        _isLoading = false;
      });
      return;
    }

    // Otherwise, fetch from API
    try {
      final data = await _api.getServiceDetails(
        widget.serviceId,
        scope: ServiceDataScope.fixedOnly,
      );
      if (mounted) {
        setState(() {
          _serviceData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar detalhes do serviço: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.black, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.mapPin,
                color: Colors.black,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'O Prestador Chegou!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _isLoading
                  ? 'Carregando detalhes...'
                  : 'Seu agendamento segue confirmado em ${_serviceData?['address'] ?? 'Endereço não disponível'}.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black87),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: const Text(
                'No fluxo fixo, os 90% restantes são pagos diretamente ao prestador no local. O app não recebe esse pagamento final.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/scheduled-service/${widget.serviceId}');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Abrir Agendamento'),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'A taxa via PIX confirma a reserva. O valor final é acertado presencialmente com o prestador.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(foregroundColor: Colors.black),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }
}
