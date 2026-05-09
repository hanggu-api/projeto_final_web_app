import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:service_101/core/theme/app_theme.dart';

class CancelReasonSheet extends StatefulWidget {
  final Function(String) onConfirm;

  const CancelReasonSheet({super.key, required this.onConfirm});

  @override
  State<CancelReasonSheet> createState() => _CancelReasonSheetState();
}

class _CancelReasonSheetState extends State<CancelReasonSheet> {
  String? _selectedReason;
  final TextEditingController _customReasonController = TextEditingController();

  final List<String> _reasons = [
    'O prestador está demorando muito',
    'O prestador está indo para o local errado',
    'Mudei de ideia / Não preciso mais',
    'O prestador pediu para cancelar',
    'Resolvi de outra forma',
    'Preço muito alto',
    'Outro motivo',
  ];

  @override
  void dispose() {
    _customReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Por que você deseja cancelar?',
            style: GoogleFonts.manrope(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.black, // Cor preta Marina!
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _reasons.length,
              itemBuilder: (context, index) {
                final reason = _reasons[index];
                final isSelected = _selectedReason == reason;
                final isOther = reason == 'Outro motivo';

                return Column(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _selectedReason = reason),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : Colors.grey[50], // Branco se selecionado Marina!
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? AppTheme.primaryYellow : Colors.transparent,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05), // Sombra sutil Marina!
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                reason,
                                style: GoogleFonts.manrope(
                                  fontSize: 14,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                  color: Colors.black, // Letras pretas Marina!
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(LucideIcons.checkCircle2, color: AppTheme.primaryYellow, size: 20),
                          ],
                        ),
                      ),
                    ),
                    if (isOther && isSelected)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16, top: 8),
                        child: TextField(
                          controller: _customReasonController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Escreva seu motivo aqui...',
                            hintStyle: GoogleFonts.manrope(fontSize: 14, color: Colors.grey),
                            filled: true,
                            fillColor: Colors.grey[50],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: AppTheme.primaryYellow, width: 1.5),
                            ),
                          ),
                          style: GoogleFonts.manrope(fontSize: 14, color: Colors.black),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedReason == null
                  ? null
                  : () {
                      String finalReason = _selectedReason!;
                      if (_selectedReason == 'Outro motivo' && _customReasonController.text.isNotEmpty) {
                        finalReason = _customReasonController.text;
                      }
                      widget.onConfirm(finalReason);
                      Navigator.pop(context);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textDark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                'ENVIAR',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'VOLTAR',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.grey,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
