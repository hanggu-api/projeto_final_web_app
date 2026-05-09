import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/scheduling/backend_scheduling_api.dart';
import '../models/pix_payment_contract.dart';
import '../models/pending_fixed_booking_policy.dart';
import '../models/pix_payment_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/api_service.dart';
import '../../../services/background_main.dart';
import '../../../services/client_tracking_service.dart';

class PixPaymentScreen extends StatefulWidget {
  final PixPaymentArgs args;

  const PixPaymentScreen({super.key, required this.args});

  @override
  State<PixPaymentScreen> createState() => _PixPaymentScreenState();
}

class _PixPaymentScreenState extends State<PixPaymentScreen>
    with WidgetsBindingObserver {
  final ApiService _api = ApiService();
  final BackendSchedulingApi _schedulingApi = const BackendSchedulingApi();
  Timer? _pollTimer;
  bool _checkingStatus = true;
  bool _isCompleting = false;
  String? _statusMessage;
  bool _isAppInForeground = true;

  PixPaymentArgs get _args => widget.args;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = state == AppLifecycleState.resumed;
    _isAppInForeground = isForeground;
    if (isForeground) {
      _startPolling();
      return;
    }
    _stopPolling();
  }

  void _startPolling() {
    if (!_isAppInForeground) return;
    _checkStatusOnce();
    _pollTimer ??= Timer.periodic(
      const Duration(seconds: 4),
      (_) => _checkStatusOnce(),
    );
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _checkStatusOnce() async {
    if (_isCompleting) return;
    try {
      final detail = _args.statusSource == 'service'
          ? await _api.getServiceDetails(_args.resourceId)
          : await _api.getPendingFixedBookingIntent(_args.resourceId);
      if (!mounted) return;

      if (detail == null) {
        _stopPolling();
        setState(() {
          _checkingStatus = false;
          _statusMessage = 'Não encontramos mais esta cobrança pendente.';
        });
        Navigator.of(context).maybePop(PixPaymentResult.notFound);
        return;
      }

      var effectiveDetail = detail;
      if (_args.statusSource == 'pending_fixed_booking' &&
          PendingFixedBookingPolicy.isPaid(detail) &&
          (detail['created_service_id'] ?? '').toString().trim().isEmpty) {
        final confirmed = await _schedulingApi.confirmBookingIntent(
          _args.resourceId,
        );
        if (confirmed != null) {
          final serviceId = (confirmed['serviceId'] ?? '').toString().trim();
          effectiveDetail = {
            ...detail,
            ...confirmed,
            if (serviceId.isNotEmpty) 'created_service_id': serviceId,
          };
        }
      }

      final fixedDecision = _args.statusSource == 'pending_fixed_booking'
          ? PendingFixedBookingPolicy.evaluate(effectiveDetail)
          : null;
      final createdServiceId = _args.statusSource == 'service'
          ? _args.resourceId
          : (fixedDecision?.createdServiceId ??
                (detail['created_service_id'] ?? '').toString().trim());
      final shouldNavigate = _args.statusSource == 'pending_fixed_booking'
          ? fixedDecision?.shouldNavigateToScheduledService == true
          : (PixPaymentPolicy.isPaid(_args, detail) &&
                createdServiceId.isNotEmpty);
      if (shouldNavigate) {
        _stopPolling();
        _isCompleting = true;
        if (_args.statusSource == 'pending_fixed_booking' &&
            createdServiceId.isNotEmpty) {
          try {
            await initializeBackgroundService();
            final paidService = await _api.getServiceDetails(
              createdServiceId,
              scope: ServiceDataScope.fixedOnly,
              forceRefresh: true,
            );
            await ClientTrackingService.syncTrackingForService(paidService);
          } catch (_) {
            // best effort
          }
        }
        final targetRoute = _args.statusSource == 'pending_fixed_booking'
            ? fixedDecision!.scheduledServiceRoute
            : PixPaymentPolicy.successRoute(_args, createdServiceId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pagamento confirmado. Continuando o fluxo...'),
            backgroundColor: Colors.green,
          ),
        );
        // A tela Pix é uma página centralizada do fluxo. Ao confirmar, ela deve
        // substituir a rota atual pelo próximo passo oficial em vez de apenas
        // voltar para a página anterior, que pode ser o tracking antigo.
        context.go(targetRoute);
        return;
      }

      final shouldClear = _args.statusSource == 'pending_fixed_booking'
          ? fixedDecision?.shouldClearCache == true
          : PixPaymentPolicy.isTerminal(_args, effectiveDetail);
      if (shouldClear) {
        _stopPolling();
        setState(() {
          _checkingStatus = false;
          _statusMessage =
              'A reserva temporária expirou. Volte e escolha um novo horário.';
        });
        Navigator.of(context).maybePop(PixPaymentResult.expired);
        return;
      }

      setState(() {
        _checkingStatus = false;
        _statusMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checkingStatus = false;
        _statusMessage = 'Falha ao verificar o pagamento agora.';
      });
    }
  }

  void _copyPixCode() {
    final code = _args.qrCode.trim();
    if (code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Código Pix copiado!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPayload = _args.qrCode.trim().isNotEmpty;
    final hasImage = _args.qrCodeImage.trim().isNotEmpty;
    final imageUri = hasImage ? Uri.tryParse(_args.qrCodeImage) : null;
    final imageBytes = imageUri?.data?.contentAsBytes();

    return PopScope(
      onPopInvokedWithResult: (_, __) {},
      child: Scaffold(
        appBar: AppBar(title: const Text('Pagamento Pix')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF9E4),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _args.title,
                      style: TextStyle(
                        color: AppTheme.darkBlueText,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _args.description,
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Valor: R\$ ${_args.amount.toStringAsFixed(2).replaceAll('.', ',')}',
                      style: TextStyle(
                        color: AppTheme.darkBlueText,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if ((_args.serviceLabel ?? '').trim().isNotEmpty ||
                        (_args.providerName ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((_args.serviceLabel ?? '').trim().isNotEmpty)
                              Text(
                                'Referencia: ${_args.serviceLabel!.trim()}',
                                style: TextStyle(
                                  color: AppTheme.darkBlueText,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            if ((_args.providerName ?? '')
                                .trim()
                                .isNotEmpty) ...[
                              if ((_args.serviceLabel ?? '').trim().isNotEmpty)
                                const SizedBox(height: 4),
                              Text(
                                'Prestador vinculado: ${_args.providerName!.trim()}',
                                style: TextStyle(
                                  color: AppTheme.darkBlueText.withValues(
                                    alpha: 0.8,
                                  ),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Motivo da cobranca',
                      style: TextStyle(
                        color: Colors.blue.shade900,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      PixPaymentPolicy.buildDetailedPaymentReason(_args),
                      style: TextStyle(
                        color: Colors.blue.shade900,
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.pending_actions_outlined,
                      color: Colors.orange.shade800,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _statusMessage ??
                            'Escaneie o QR Code ou use o código Pix. Esta tela acompanha a confirmação do pagamento automaticamente.',
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    SizedBox(
                      width: 240,
                      height: 240,
                      child: hasPayload
                          ? QrImageView(
                              data: _args.qrCode,
                              version: QrVersions.auto,
                              backgroundColor: Colors.white,
                            )
                          : imageBytes != null
                          ? Image.memory(imageBytes, fit: BoxFit.contain)
                          : hasImage
                          ? Image.network(
                              _args.qrCodeImage,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const Center(child: Text('QR indisponível')),
                            )
                          : const Center(child: Text('QR indisponível')),
                    ),
                    const SizedBox(height: 16),
                    if (hasPayload)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: SelectableText(
                          _args.qrCode,
                          style: TextStyle(
                            color: AppTheme.darkBlueText,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: hasPayload ? _copyPixCode : null,
                  icon: const Icon(LucideIcons.copy, size: 18),
                  label: const Text('Copiar Pix'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _checkingStatus ? null : _checkStatusOnce,
                  icon: const Icon(LucideIcons.refreshCw, size: 18),
                  label: Text(
                    _checkingStatus
                        ? 'Verificando pagamento...'
                        : 'Atualizar status',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.pop(PixPaymentResult.cancelled),
                child: Text(PixPaymentPolicy.backButtonLabel(_args)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
