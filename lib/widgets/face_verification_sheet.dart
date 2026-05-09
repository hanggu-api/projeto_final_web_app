import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/security_service.dart';
import '../services/api_service.dart';
import '../core/theme/app_theme.dart';

class FaceVerificationSheet extends StatefulWidget {
  const FaceVerificationSheet({super.key});

  @override
  State<FaceVerificationSheet> createState() => _FaceVerificationSheetState();
}

class _FaceVerificationSheetState extends State<FaceVerificationSheet> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isVerifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() => _error = 'Nenhuma câmera encontrada');
        return;
      }

      // Prioritize front camera for selfie
      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
      if (!mounted) return;
      setState(() => _isInitialized = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Erro ao iniciar câmera: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _processVerification() async {
    if (!_isInitialized || _controller == null || _isVerifying) return;

    setState(() {
      _isVerifying = true;
      _error = null;
    });

    try {
      // 1. Capturar foto
      final XFile photo = await _controller!.takePicture();
      final bytes = await photo.readAsBytes();

      // 2. Upload para o Storage (bucket id-verification - PRIVADO/RESTRITO)
      final ApiService api = ApiService();
      final filename = 'security_check_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final selfiePath = await api.uploadVerificationImage(bytes, filename: filename);

      // 3. Validar biometria via SecurityService
      final result = await SecurityService().verifyFace(selfiePath);

      if (!mounted) return;

      if (result['success'] == true) {
        Navigator.of(context).pop(true); // Sucesso!
      } else {
        setState(() {
          _error = result['error'] ?? 'Não foi possível validar sua identidade.';
          _isVerifying = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().contains('Biometria original não encontrada') 
          ? 'Você ainda não possui biometria cadastrada. Entre em contato com o suporte.'
          : 'Erro na validação: $e';
        _isVerifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
            'Validação de Segurança',
            style: GoogleFonts.manrope(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Posicione seu rosto no centro da câmera para confirmar sua identidade e adicionar o cartão.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 32),
          
          // Camera Circle Preview
          SizedBox(
            width: 250,
            height: 250,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Border
                Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _isVerifying ? AppTheme.primaryBlue : Colors.grey[200]!,
                      width: 4,
                    ),
                  ),
                ),
                // Preview
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: SizedBox(
                    width: 235,
                    height: 235,
                    child: _error != null
                      ? Center(child: Icon(LucideIcons.alertCircle, color: Colors.red, size: 48))
                      : _isInitialized && _controller != null
                        ? CameraPreview(_controller!)
                        : const Center(child: CircularProgressIndicator()),
                  ),
                ),
                // Overlay Loading
                if (_isVerifying)
                  Container(
                    width: 235,
                    height: 235,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Validando...', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 24),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],

          const SizedBox(height: 40),
          
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: (_isInitialized && !_isVerifying) ? _processVerification : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'CAPTURAR E VALIDAR',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isVerifying ? null : () => Navigator.pop(context),
            child: Text(
              'CANCELAR',
              style: GoogleFonts.manrope(
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
