import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/in_app_camera_screen.dart';
import 'package:image_picker/image_picker.dart';

class FacialLivenessStep extends StatefulWidget {
  final Map<String, dynamic> verificationData;
  final Function(Map<String, dynamic>) onChanged;
  final VoidCallback? onSubmit;

  const FacialLivenessStep({
    super.key,
    required this.verificationData,
    required this.onChanged,
    this.onSubmit,
  });

  @override
  State<FacialLivenessStep> createState() => _FacialLivenessStepState();
}

class _FacialLivenessStepState extends State<FacialLivenessStep> {
  File? _selfieFile;
  bool _isValidated = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final path = widget.verificationData['selfie_path'];
    if (path != null && path.toString().isNotEmpty) {
      _selfieFile = File(path.toString());
      _isValidated = widget.verificationData['liveness_validated'] ?? false;
    }
  }

  Future<void> _startLiveness() async {
    try {
      final dynamic result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const InAppCameraScreen(
            isSelfie: true,
            blinkOnly: true, // Modo apenas piscada solicitado pelo usuário
          ),
        ),
      );

      if (result != null && result is XFile) {
        setState(() {
          _selfieFile = File(result.path);
          _isValidated = true;
          _error = null;
        });
        
        widget.onChanged({
          ...widget.verificationData,
          'selfie_path': result.path,
          'liveness_validated': true,
          'validated_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      setState(() => _error = "Erro ao validar: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Prova de Vida',
            style: GoogleFonts.manrope(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Para garantir a segurança da plataforma, precisamos confirmar que você é uma pessoa real.',
            style: GoogleFonts.manrope(
              fontSize: 15,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          
          if (!_isValidated) ...[
            Center(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: AppTheme.primaryYellow.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.center_focus_strong,
                      size: 88,
                      color: AppTheme.primaryYellow,
                    ),
                    Icon(
                      Icons.man_2_outlined,
                      size: 46,
                      color: AppTheme.primaryYellow,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            Text(
              'Instruções:',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            _buildInstructionItem(Icons.videocam, 'Enquadre seu rosto no círculo'),
            _buildInstructionItem(Icons.remove_red_eye, 'Pisque os olhos quando solicitado'),
            _buildInstructionItem(Icons.light_mode, 'Certifique-se de estar em um local iluminado'),
          ] else ...[
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.green, width: 4),
                      image: DecorationImage(
                        image: FileImage(_selfieFile!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, color: Colors.white, size: 30),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Identidade Validada!',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
              textAlign: TextAlign.center,
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: 20),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 48),
          
          ElevatedButton(
            onPressed: _startLiveness,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isValidated ? Colors.grey.shade200 : AppTheme.primaryYellow,
              foregroundColor: AppTheme.textDark,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: Text(
              _isValidated ? 'REPETIR VALIDAÇÃO' : 'INICIAR VALIDAÇÃO',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),

          if (_isValidated) ...[
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: widget.onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryYellow,
                foregroundColor: AppTheme.textDark,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: const Text(
                'CONCLUIR CADASTRO',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInstructionItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.primaryYellow),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.manrope(fontSize: 14, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }
}
