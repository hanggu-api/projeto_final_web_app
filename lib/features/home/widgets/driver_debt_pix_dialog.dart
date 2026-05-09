import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../utils/pix_generator.dart';
import '../../../services/remote_config_service.dart';

class DriverDebtPixDialog extends StatelessWidget {
  final double amount;

  const DriverDebtPixDialog({
    super.key,
    required this.amount,
  });

  @override
  Widget build(BuildContext context) {
    // Busca configurações do RemoteConfig ou usa fallbacks
    final pixKey = RemoteConfigService.getValue('admin_pix_key', '000.000.000-00');
    final merchantName = RemoteConfigService.getValue('admin_pix_name', 'CENTRAL 101');
    final merchantCity = RemoteConfigService.getValue('admin_pix_city', 'IMPERATRIZ');

    final pixPayload = PixGenerator.generatePayload(
      pixKey: pixKey,
      merchantName: merchantName,
      merchantCity: merchantCity,
      amount: amount,
      txid: 'DIVIDA${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.primaryYellow,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.textDark.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.qr_code, color: AppTheme.textDark),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pagar Comissão',
                            style: GoogleFonts.manrope(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.textDark,
                            ),
                          ),
                          Text(
                            'Escaneie o QR Code abaixo',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textDark.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(LucideIcons.x, color: AppTheme.textDark),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    // Valor
                    Text(
                      'Valor a pagar',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'R\$ ${amount.toStringAsFixed(2).replaceAll('.', ',')}',
                      style: GoogleFonts.manrope(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // QR Code
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.grey.shade100, width: 2),
                      ),
                      child: QrImageView(
                        data: pixPayload,
                        version: QrVersions.auto,
                        size: 200.0,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: AppTheme.textDark,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Botão Copia e Cola
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: pixPayload));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Código Pix copiado para a área de transferência!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                        icon: Icon(LucideIcons.copy, size: 20),
                        label: Text(
                          'COPIAR CÓDIGO PIX',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.textDark,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    Text(
                      'Após o pagamento, a comissão será baixada automaticamente em nosso sistema.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> show(BuildContext context, double amount) {
    if (amount <= 0) return Future.value();
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => DriverDebtPixDialog(amount: amount),
    );
  }
}
