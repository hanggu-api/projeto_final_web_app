import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:service_101/core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';

class RatingModal extends StatefulWidget {
  final String tripId;
  final int? driverId;
  final Function(int rating, String comment) onSubmit;
  final String title;
  final String subtitle;
  final String skipLabel;
  final String submitLabel;
  final VoidCallback? onSkip;

  const RatingModal({
    super.key,
    required this.tripId,
    this.driverId,
    required this.onSubmit,
    this.title = 'Como foi sua viagem?',
    this.subtitle = 'Sua avaliação ajuda a melhorar o serviço',
    this.skipLabel = 'AGORA NÃO',
    this.submitLabel = 'ENVIAR',
    this.onSkip,
  });

  @override
  State<RatingModal> createState() => _RatingModalState();
}

class _RatingModalState extends State<RatingModal> {
  int rating = 5;
  final TextEditingController commentController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Column(
        children: [
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 2,
            children: List.generate(5, (index) {
              return IconButton(
                icon: Icon(
                  index < rating ? Icons.star : Icons.star_border,
                  color: index < rating ? Colors.amber : Colors.grey.shade300,
                  size: 36,
                ),
                onPressed: () => setState(() => rating = index + 1),
              );
            }),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: commentController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Deixe um comentário (opcional)',
              hintStyle: GoogleFonts.manrope(fontSize: 14, color: Colors.grey),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            if (widget.onSkip != null) {
              widget.onSkip!();
            } else {
              context.go('/home');
            }
          },
          child: Text(
            widget.skipLabel,
            style: GoogleFonts.manrope(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () => widget.onSubmit(rating, commentController.text),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text(
            widget.submitLabel,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}
