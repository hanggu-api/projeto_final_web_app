import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../payment/models/pix_payment_contract.dart';

enum PendingFixedBookingDetailsAction { editSchedule }

class PendingFixedBookingDetailsArgs {
  final String intentId;
  final String serviceLabel;
  final String providerName;
  final String? professionName;
  final String? address;
  final DateTime? scheduledAt;
  final double upfrontAmount;
  final double totalAmount;
  final String qrCode;
  final String qrCodeImage;

  const PendingFixedBookingDetailsArgs({
    required this.intentId,
    required this.serviceLabel,
    required this.providerName,
    required this.upfrontAmount,
    required this.totalAmount,
    this.professionName,
    this.address,
    this.scheduledAt,
    this.qrCode = '',
    this.qrCodeImage = '',
  });
}

class PendingFixedBookingDetailsScreen extends StatefulWidget {
  final PendingFixedBookingDetailsArgs args;

  const PendingFixedBookingDetailsScreen({super.key, required this.args});

  @override
  State<PendingFixedBookingDetailsScreen> createState() =>
      _PendingFixedBookingDetailsScreenState();
}

class _PendingFixedBookingDetailsScreenState
    extends State<PendingFixedBookingDetailsScreen> {
  final ApiService _api = ApiService();
  bool _openingPix = false;

  String get _dateLabel {
    final scheduledAt = widget.args.scheduledAt;
    if (scheduledAt == null) return 'Horario pendente';
    return DateFormat("EEEE, dd 'de' MMMM", 'pt_BR').format(scheduledAt);
  }

  String get _timeLabel {
    final scheduledAt = widget.args.scheduledAt;
    if (scheduledAt == null) return '--:--';
    return DateFormat('HH:mm', 'pt_BR').format(scheduledAt);
  }

  String _formatCurrency(double value) {
    return 'R\$ ${value.toStringAsFixed(2)}';
  }

  Future<void> _openPixPayment() async {
    if (_openingPix) return;
    setState(() => _openingPix = true);
    try {
      var qrCode = widget.args.qrCode.trim();
      var qrCodeImage = widget.args.qrCodeImage.trim();
      var amount = widget.args.upfrontAmount;

      if (qrCode.isEmpty && qrCodeImage.isEmpty) {
        final pix = await _api.loadPixPayload(
          pendingFixedBookingId: widget.args.intentId,
        );
        qrCode = (pix['payload'] ?? '').toString().trim();
        qrCodeImage = (pix['encodedImage'] ?? pix['image_url'] ?? '')
            .toString()
            .trim();
        amount = double.tryParse('${pix['amount'] ?? ''}') ?? amount;
      }

      if (!mounted) return;
      if (qrCode.isEmpty && qrCodeImage.isEmpty) {
        throw Exception('Nao foi possivel carregar o Pix deste agendamento.');
      }

      context.push(
        '/pix-payment',
        extra: PixPaymentArgs(
          resourceId: widget.args.intentId,
          title: 'Reserva pendente',
          description:
              'Conclua o Pix para confirmar o agendamento e manter este horario reservado.',
          providerName: widget.args.providerName,
          serviceLabel: widget.args.serviceLabel,
          fiscalDescription:
              'Este Pix corresponde à taxa de intermediação e reserva do agendamento ${widget.args.serviceLabel} com ${widget.args.providerName}. O valor é identificado pela plataforma para conciliação operacional e tributária da intermediação, enquanto o restante do atendimento segue vinculado ao serviço presencial.',
          qrCode: qrCode,
          qrCodeImage: qrCodeImage,
          amount: amount,
          statusSource: 'pending_fixed_booking',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao abrir o pagamento Pix: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _openingPix = false);
      }
    }
  }

  Widget _buildFlowStep(IconData icon, String title, String subtitle) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppTheme.secondaryOrange, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    final remainingValue = args.totalAmount - args.upfrontAmount;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Agendamento pendente'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.primaryYellow,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(LucideIcons.calendarClock, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        _dateLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _timeLabel,
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Seu horario esta reservado aguardando o Pix da taxa inicial.',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      args.serviceLabel,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if ((args.professionName ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        args.professionName!,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Icon(Icons.storefront_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            args.providerName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    if ((args.address ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              args.address!,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total do servico'),
                        Text(
                          _formatCurrency(args.totalAmount),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Taxa de agendamento (10%)',
                          style: TextStyle(color: AppTheme.secondaryOrange),
                        ),
                        Text(
                          _formatCurrency(args.upfrontAmount),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.secondaryOrange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Pagar no local (90%)'),
                        Text(
                          _formatCurrency(remainingValue),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Depois de pagar a taxa no Pix, o horario continua confirmado e o restante e pago diretamente no salao no dia do atendimento.',
                        style: TextStyle(
                          color: Colors.blue.shade900,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  'Como funciona?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildFlowStep(
                    LucideIcons.banknote,
                    '1. Reserva',
                    'Pague 10%\nvia Pix',
                  ),
                  const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                  _buildFlowStep(
                    LucideIcons.mapPin,
                    '2. Visita',
                    'Vá ao salão\ne faça check-in',
                  ),
                  const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                  _buildFlowStep(
                    LucideIcons.checkCircle,
                    '3. Final',
                    'Pague 90%\ndiretamente no local',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _openPixPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondaryOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _openingPix
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.qrCode, size: 18),
                label: Text(
                  _openingPix ? 'Carregando Pix...' : 'Abrir pagamento Pix',
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(PendingFixedBookingDetailsAction.editSchedule),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.darkBlueText,
                  side: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Alterar horario'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
