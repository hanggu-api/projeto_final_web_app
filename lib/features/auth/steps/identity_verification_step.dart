import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/api_service.dart';
import '../../shared/widgets/in_app_camera_screen.dart';
import '../../../services/ocr_service.dart';

class IdentityVerificationStep extends StatefulWidget {
  final Map<String, dynamic> verificationData;
  final Function(Map<String, dynamic>) onChanged;
  final bool isCardValidation;

  const IdentityVerificationStep({
    super.key,
    required this.verificationData,
    required this.onChanged,
    this.isCardValidation = false,
  });

  @override
  State<IdentityVerificationStep> createState() =>
      _IdentityVerificationStepState();
}

class _IdentityVerificationStepState extends State<IdentityVerificationStep> {
  final ImagePicker _picker = ImagePicker();
  File? _cnhFile;
  File? _selfieFile;
  String? _cnhFilename;
  bool _cnhIsPdf = false;
  List<int>? _cnhBytes;

  bool _isUploading = false;
  bool _isValidated = false;
  String? _error;
  double _similarity = 0.0;
  Map<String, dynamic>? _localOcrData;

  @override
  void initState() {
    super.initState();
    // Recuperar dados perdidos se a atividade foi morta pelo Android
    _retrieveLostData();
  }

  Future<void> _retrieveLostData() async {
    final LostDataResponse response = await _picker.retrieveLostData();
    if (response.isEmpty) {
      return;
    }
    if (response.file != null) {
      setState(() {
        // Como o image_picker não sabe qual campo estávamos preenchendo,
        // vamos tentar inferir ou deixar o usuário escolher de novo se for ambíguo.
        // No fluxo de cadastro, geralmente a selfie é a última.
        // Mas por segurança, só vamos restaurar se houver apenas um arquivo.
        _selfieFile = File(response.file!.path);
      });
    } else {
      setState(() {
        _error = "Erro ao recuperar imagem: ${response.exception?.code}";
      });
    }
  }

  Future<void> _pickImage(bool isSelfie) async {
    try {
      final dynamic result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => InAppCameraScreen(isSelfie: isSelfie),
        ),
      );

      if (result != null) {
        XFile? image;
        if (result is XFile) {
          image = result;
        } else if (result is Map) {
          image = result['file'] as XFile?;
        }

        if (image != null) {
          setState(() {
            if (isSelfie) {
              _selfieFile = File(image!.path);
            } else {
              _cnhFile = File(image!.path);
              _cnhIsPdf = false;
              _cnhFilename = null;
              _cnhBytes = null;
              if (result is Map && result['data'] != null) {
                if (result['data'] is CNHData) {
                  _localOcrData = (result['data'] as CNHData).toMap();
                  // Adicionar rawText explicitamente se necessário
                  _localOcrData?['rawText'] =
                      (result['data'] as CNHData).rawText;
                } else {
                  _localOcrData = result['data'] as Map<String, dynamic>;
                }
                debugPrint('✅ Dados OCR capturados localmente: $_localOcrData');
              }
            }
            _isValidated = false;
            _error = null;
          });
          _updateParent();

          // Inicia a validação automaticamente se ambas as fotos estiverem presentes
          // OU se for validação de cartão e tiver a selfie
          if ((_cnhFile != null && _selfieFile != null) || (widget.isCardValidation && _selfieFile != null)) {
            debugPrint(
              '🚀 Requisitos de captura atendidos. Iniciando validação automática...',
            );
            _verifyIdentity();
          }
        }
      }
    } catch (e) {
      setState(() => _error = "Erro ao capturar imagem: $e");
    }
  }

  void _updateParent() {
    widget.onChanged({
      'cnh_path': widget.verificationData['cnh_path'],
      'selfie_path': widget.verificationData['selfie_path'],
      'is_validated': _isValidated,
      'document_type': _cnhIsPdf ? 'pdf' : 'image',
      'document_filename': _cnhFilename,
      'similarity': _similarity,
      'local_ocr_data': _localOcrData,
    });
  }

  Future<void> _pickPdfDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;
      final bytes = picked.bytes ??
          (picked.path != null ? await File(picked.path!).readAsBytes() : null);
      if (!mounted) return;
      if (bytes == null) {
        throw Exception("Não foi possível ler o PDF.");
      }

      setState(() {
        _cnhFile = null;
        _cnhIsPdf = true;
        _cnhFilename = picked.name;
        _cnhBytes = bytes;
        _isValidated = false;
        _error = null;
      });
      _updateParent();

      if (_selfieFile != null) {
        _verifyIdentity();
      }
    } catch (e) {
      setState(() => _error = "Erro ao selecionar PDF: $e");
    }
  }

  Future<void> _verifyIdentity() async {
    if (!widget.isCardValidation &&
        ((_cnhFile == null && !_cnhIsPdf) || _selfieFile == null)) {
      setState(() => _error = "Por favor, selecione ambas as fotos.");
      return;
    }
    if (widget.isCardValidation && _selfieFile == null) {
      setState(() => _error = "Por favor, capture sua selfie.");
      return;
    }

    setState(() {
      _isUploading = true;
      _error = null;
    });

    try {
      final api = ApiService();

      // 1. Upload CNH (apenas se necessário) Marina! Marina! Marina!
      String? cnhRemotePath;
      if (!widget.isCardValidation) {
        if (_cnhIsPdf) {
          if ((_cnhBytes == null || _cnhBytes!.isEmpty) ||
              _cnhFilename == null) {
            throw Exception('Arquivo PDF não encontrado.');
          }
          cnhRemotePath = await api.uploadIdDocument(
            _cnhBytes!,
            _cnhFilename!,
          );
        } else if (_cnhFile != null) {
          cnhRemotePath = await api.uploadIdDocument(
            await _cnhFile!.readAsBytes(),
            'cnh_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );
        }
      }

      // 2. Upload Selfie (Sempre necessário) Marina! Marina! Marina!
      final selfieRemotePath = await api.uploadIdDocument(
        await _selfieFile!.readAsBytes(),
        'selfie_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      // 2.1 Persistir paths imediatamente no Supabase
      await api.saveDriverDocumentPaths(
        selfiePath: selfieRemotePath,
        documentPath: cnhRemotePath,
      );

      // 3. Chamar verificação Marina! Marina! Marina!
      if (_cnhIsPdf) {
        setState(() {
          _isValidated = true;
          _similarity = 0.0;
          _isUploading = false;
        });
        widget.onChanged({
          'cnh_path': cnhRemotePath,
          'selfie_path': selfieRemotePath,
          'is_validated': true,
          'document_type': 'pdf',
          'document_filename': _cnhFilename,
          'similarity': 0.0,
          'local_ocr_data': _localOcrData,
        });
      } else {
        dynamic result;
        if (widget.isCardValidation) {
          result = await api.verifyCardFace(selfiePath: selfieRemotePath);
        } else {
          result = await api.verifyFace(
            cnhPath: cnhRemotePath!,
            selfiePath: selfieRemotePath,
          );
        }

        if (result['success'] == true && result['match'] == true) {
          setState(() {
            _isValidated = true;
            _similarity = (result['similarity'] as num?)?.toDouble() ?? 0.0;
            _isUploading = false;
          });

          widget.onChanged({
            'cnh_path': cnhRemotePath,
            'selfie_path': selfieRemotePath,
            'is_validated': true,
            'similarity': _similarity,
            'extracted_data': result['extractedData'],
            'local_ocr_data': _localOcrData,
          });
        } else {
          setState(() {
            _isValidated = false;
            _isUploading = false;
            _error = result['match'] == false
                ? "Identidade não confirmada. As fotos não coincidem."
                : "Erro na verificação: ${result['error'] ?? 'Erro desconhecido'}";
          });
        }
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
        _error = "Erro técnico: $e";
      });
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
            'Verificação de Identidade',
            style: GoogleFonts.manrope(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Para sua segurança e dos passageiros, precisamos validar sua foto com o documento.',
            style: GoogleFonts.manrope(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          if (!widget.isCardValidation) ...[
            _buildPhotoCard(
              title: "Foto da CNH",
              subtitle: "Frente do documento aberta",
              file: _cnhFile,
              icon: Icons.badge,
              onTap: () => _pickImage(false),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isUploading ? null : _pickPdfDocument,
              icon: const Icon(Icons.picture_as_pdf),
              label: Text(
                _cnhIsPdf ? "PDF selecionado" : "Enviar CNH em PDF",
              ),
            ),
            if (_cnhIsPdf && _cnhFilename != null) ...[
              const SizedBox(height: 8),
              Text(
                "Arquivo: $_cnhFilename",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
          ],

          _buildPhotoCard(
            title: "Sua Selfie",
            subtitle: "Olhe diretamente para a câmera",
            file: _selfieFile,
            icon: Icons.face,
            onTap: () => _pickImage(true),
          ),

          if (_error != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          ],

          if (_isValidated) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    _cnhIsPdf
                        ? "Documento enviado. Validação pendente."
                        : "Identidade Validada! (${_similarity.toStringAsFixed(1)}%)",
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),
          if (!_isValidated)
            SizedBox(
              height: 56,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryYellow.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _isUploading ? null : _verifyIdentity,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryYellow,
                    foregroundColor: AppTheme.textDark,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isUploading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Text(
                          _cnhIsPdf ? "ENVIAR DOCUMENTO" : "VALIDAR AGORA",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoCard({
    required String title,
    required String subtitle,
    required File? file,
    required IconData icon,
    required VoidCallback onTap,
    bool isSelfie = false,
  }) {
    return GestureDetector(
      onTap: _isUploading ? null : onTap,
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: file != null ? AppTheme.primaryYellow : Colors.grey.shade100,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
          image: file != null
              ? DecorationImage(image: FileImage(file), fit: BoxFit.cover)
              : null,
        ),
        child: file == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 40, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelfie
                          ? AppTheme.primaryBlue
                          : AppTheme.textDark,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              )
            : Stack(
                children: [
                  Positioned(
                    right: 8,
                    top: 8,
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        icon: const Icon(
                          Icons.edit,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: onTap,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
