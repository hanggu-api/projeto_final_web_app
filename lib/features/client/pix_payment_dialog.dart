import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';

class PixPaymentDialog extends StatefulWidget {
  final String qrCode;
  final String qrCodeBase64;
  final String serviceId;

  const PixPaymentDialog({
    super.key,
    required this.qrCode,
    required this.qrCodeBase64,
    required this.serviceId,
  });

  @override
  State<PixPaymentDialog> createState() => _PixPaymentDialogState();
}

class _PixPaymentDialogState extends State<PixPaymentDialog> {
  Timer? _timer;
  bool _isChecking = false;
  bool _isPopped = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(seconds: 4), (timer) {
      // Safety: Only clients should poll for payment
      if (ApiService().role == 'provider') {
        debugPrint('PixPolling: Stopping polling as provider role detected');
        timer.cancel();
        return;
      }
      _checkStatus();
    });
  }

  Future<void> _checkStatus() async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      // Tenta verificar status diretamente no gateway via backend (Polling Inteligente)
      // Se falhar (ex: rota não existe), fallback para verificação de serviço normal
      try {
        final checkResp = await ApiService().get(
          '/payment/check/${widget.serviceId}',
        );
        debugPrint('PixPolling: /payment/check => ${checkResp['status']}');
        if (checkResp['success'] == true && checkResp['status'] == 'approved') {
          _timer?.cancel();
          if (mounted && !_isPopped && Navigator.of(context).canPop()) {
            _isPopped = true;
            Navigator.of(context).pop(true);
          }
          return;
        }
      } catch (e) {
        // Ignora erro específico de rota de check, tenta serviço
        debugPrint('Erro ao checar pagamento direto: $e');
      }

      // Fallback: Verifica o status do serviço
      // Se estiver 'pending', significa que o pagamento foi aprovado e o serviço ativado
      final response = await ApiService().get('/services/${widget.serviceId}');

      if (response['success'] == true) {
        // Correctly access the service object from response
        final serviceData = response['service'];
        if (serviceData != null) {
          final status = serviceData['status'];
          debugPrint('PixPolling: /services/${widget.serviceId} => $status');
          if (status == 'pending' ||
              status == 'in_progress' ||
              status == 'finished') {
            _timer?.cancel();
            if (mounted && !_isPopped && Navigator.of(context).canPop()) {
              _isPopped = true;
              Navigator.of(context).pop(true); // Retorna true para indicar sucesso
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao verificar status: $e');
    } finally {
      _isChecking = false;
    }
  }

  void _copyPixCode() {
    Clipboard.setData(ClipboardData(text: widget.qrCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Código Pix copiado!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Decodifica a imagem base64 com tratamento de erro
    Uint8List? imageBytes;
    try {
      imageBytes = base64Decode(widget.qrCodeBase64);
    } catch (e) {
      debugPrint('Erro ao decodificar QR Code: $e');
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Pagamento via Pix',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryPurple,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Escaneie o QR Code ou copie o código abaixo',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // QR Code Image
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: imageBytes != null
                  ? Image.memory(
                      imageBytes,
                      width: 200,
                      height: 200,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const SizedBox(
                          width: 200,
                          height: 200,
                          child: Center(
                            child: Text('Erro ao carregar QR Code'),
                          ),
                        );
                      },
                    )
                  : const SizedBox(
                      width: 200,
                      height: 200,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.qr_code_2, size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text(
                              'QR Code Indisponível\nUse o Copia e Cola',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),

            const SizedBox(height: 24),

            // Copia e Cola
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.qrCode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Monospace',
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      LucideIcons.copy,
                      color: Theme.of(context).primaryColor,
                    ),
                    onPressed: _copyPixCode,
                    tooltip: 'Copiar código',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text(
                  'Aguardando pagamento...',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  try {
                    await ApiService().testApprovePayment(widget.serviceId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Pagamento confirmado via TESTE!'),
                          backgroundColor: Colors.blue,
                        ),
                      );
                      // Force close dialog on test confirmation
                      _timer?.cancel();
                      if (mounted && !_isPopped && Navigator.of(context).canPop()) {
                        _isPopped = true;
                        Navigator.of(context).pop(true);
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Erro ao confirmar: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade100,
                  foregroundColor: Colors.orange.shade900,
                  elevation: 0,
                ),
                child: const Text('Confirmar Pagamento (TESTE)'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(), // Fecha sem confirmar
              child: const Text('Cancelar / Pagar depois'),
            ),
          ],
        ),
      ),
    );
  }
}
