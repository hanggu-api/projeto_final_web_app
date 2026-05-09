import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../widgets/app_dialog_actions.dart';

class ServiceCompletionModal extends StatefulWidget {
  final Future<void> Function(String code, XFile photo) onComplete;

  const ServiceCompletionModal({super.key, required this.onComplete});

  @override
  State<ServiceCompletionModal> createState() => _ServiceCompletionModalState();
}

class _ServiceCompletionModalState extends State<ServiceCompletionModal> {
  final _codeController = TextEditingController();
  XFile? _photo;
  String? _error;
  bool _submitting = false;

  bool get _isFormValid =>
      _codeController.text.isNotEmpty && _photo != null && !_submitting;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Concluir Serviço'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Insira o código de validação e uma foto do serviço realizado.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: 'Código de Validação',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) {
              setState(() {});
            },
          ),
          const SizedBox(height: 16),
          if (_photo != null) ...[
            SizedBox(
              height: 200,
              width: double.infinity,
              child: Stack(
                children: [
                  Image.file(
                    File(_photo!.path),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                      onPressed: () {
                        setState(() => _photo = null);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  if (!mounted) return;
                  try {
                    final picker = ImagePicker();
                    final img = await picker.pickImage(
                      source: ImageSource.camera,
                      maxWidth: 1024,
                      maxHeight: 1024,
                      imageQuality: 85,
                    );
                    if (img != null && mounted) {
                      setState(() => _photo = img);
                    }
                  } catch (e) {
                    debugPrint('Error picking image from camera: $e');
                    if (mounted) {
                      setState(
                        () => _error =
                            'Erro ao abrir câmera. Verifique as permissões.',
                      );
                    }
                  }
                },
                icon: const Icon(Icons.camera_alt),
                label: const Text('Tirar foto do serviço concluído'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black87,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
      actions: [
        AppDialogCancelAction(onPressed: () => Navigator.pop(context)),
        AppDialogPrimaryAction(
          label: 'Concluir',
          onPressed: _isFormValid
              ? () async {
                  setState(() {
                    _error = null;
                    _submitting = true;
                  });
                  try {
                    await widget.onComplete(_codeController.text, _photo!);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  } catch (e) {
                    if (mounted) {
                      setState(() {
                        _error = 'Erro ao concluir serviço: $e';
                        _submitting = false;
                      });
                    }
                  }
                }
              : null,
          isLoading: _submitting,
        ),
      ],
    );
  }
}
