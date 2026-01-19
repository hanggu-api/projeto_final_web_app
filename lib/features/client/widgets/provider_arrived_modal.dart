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
  bool _showPaymentOptions = false;
  bool _isProcessingPayment = false;
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
      final data = await _api.getServiceDetails(widget.serviceId);
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

  Future<void> _processPayment(String method) async {
    setState(() => _isProcessingPayment = true);
    try {
      if (method == 'pix' || method == 'card') {
        final data = _serviceData ?? {};
        final total =
            double.tryParse(data['price_estimated']?.toString() ?? '0') ?? 0.0;
        final upfront =
            double.tryParse(data['price_upfront']?.toString() ?? '') ??
            (total * 0.3);
        final remaining = (total - upfront).clamp(0.0, double.infinity);

        if (mounted) {
          Navigator.of(context).pop();
          context.push(
            '/payment/${widget.serviceId}',
            extra: {
              'serviceId': widget.serviceId,
              'type': 'remaining',
              'amount': remaining,
              'total': total,
              'initialMethod': method == 'pix' ? 'pix' : 'credit',
            },
          );
        }
        return;
      }

      await _api.payRemainingService(widget.serviceId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Pagamento realizado com sucesso!'),
            backgroundColor: Colors.blue[600],
          ),
        );
        Navigator.of(context).pop();
        context.push('/tracking/${widget.serviceId}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao processar pagamento: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
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
                  : 'O prestador está no local do serviço (${_serviceData?['address'] ?? 'Endereço não disponível'}).',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black87),
            ),
            const SizedBox(height: 24),
            if (_showPaymentOptions) ...[
              const Text(
                'Escolha a forma de pagamento:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (_isProcessingPayment)
                const CircularProgressIndicator(color: Colors.black)
              else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _processPayment('card'),
                    icon: const Icon(LucideIcons.creditCard),
                    label: const Text('Cartão de Crédito'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _processPayment('pix'),
                    icon: const Icon(LucideIcons.qrCode),
                    label: const Text('Pix'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ] else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _showPaymentOptions = true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Ver Detalhes / Pagar'),
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'O prestador recebe o valor somente após a conclusão do serviço.',
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
