import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../services/api_service.dart';

class FaceValidationTestScreen extends StatefulWidget {
  const FaceValidationTestScreen({super.key});

  @override
  State<FaceValidationTestScreen> createState() =>
      _FaceValidationTestScreenState();
}

class _FaceValidationTestScreenState extends State<FaceValidationTestScreen> {
  final ApiService _api = ApiService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _serviceIdController = TextEditingController(
    text: const Uuid().v4(),
  );

  XFile? _cnhFile;
  XFile? _selfieFile;
  Uint8List? _cnhBytes;
  Uint8List? _selfieBytes;
  String? _cnhUrl;
  String? _selfieUrl;
  Map<String, dynamic>? _result;
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _serviceIdController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({
    required bool isCnh,
    required ImageSource source,
  }) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        preferredCameraDevice: CameraDevice.front,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (!mounted) return;

      setState(() {
        if (isCnh) {
          _cnhFile = file;
          _cnhBytes = bytes;
          _cnhUrl = null;
        } else {
          _selfieFile = file;
          _selfieBytes = bytes;
          _selfieUrl = null;
        }
        _result = null;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Falha ao selecionar imagem: $e');
    }
  }

  Future<void> _runValidation() async {
    final serviceId = _serviceIdController.text.trim();
    if (serviceId.isEmpty) {
      setState(() => _error = 'Informe um serviceId para o teste.');
      return;
    }
    if (_cnhBytes == null || _selfieBytes == null) {
      setState(() => _error = 'Selecione a foto do documento e a selfie.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _result = null;
    });

    try {
      final cnhUrl = await _api.uploadServiceImage(
        _cnhBytes!,
        filename: _buildFilename('cnh', _cnhFile?.name),
      );
      final selfieUrl = await _api.uploadServiceImage(
        _selfieBytes!,
        filename: _buildFilename('selfie', _selfieFile?.name),
      );

      final result = await _api.validateFaceRecognition(
        serviceId: serviceId,
        cnhImageUrl: cnhUrl,
        selfieImageUrl: selfieUrl,
      );

      if (!mounted) return;
      setState(() {
        _cnhUrl = cnhUrl;
        _selfieUrl = selfieUrl;
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String _buildFilename(String prefix, String? originalName) {
    final base = originalName ?? '$prefix.jpg';
    final ext = base.contains('.') ? base.split('.').last : 'jpg';
    return '${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
  }

  Widget _buildImageCard({
    required String title,
    required XFile? file,
    required Uint8List? bytes,
    required VoidCallback onCamera,
    required VoidCallback onGallery,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 4 / 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: bytes == null
                    ? const Center(
                        child: Text(
                          'Nenhuma imagem selecionada',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(bytes, fit: BoxFit.cover),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            if (file != null)
              Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: onCamera,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Câmera'),
                ),
                OutlinedButton.icon(
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galeria'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final similarity = _result?['similarity'];
    final passed = _result?['passed'];
    final threshold = _result?['threshold'];

    return Card(
      color: passed == true ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Resultado',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text('Aprovado: ${passed == true ? 'sim' : 'não'}'),
            Text('Similaridade: ${similarity ?? '-'}'),
            Text('Threshold: ${threshold ?? '-'}'),
            if (_cnhUrl != null) ...[
              const SizedBox(height: 8),
              SelectableText('CNH URL: $_cnhUrl'),
            ],
            if (_selfieUrl != null) ...[
              const SizedBox(height: 8),
              SelectableText('Selfie URL: $_selfieUrl'),
            ],
            const SizedBox(height: 8),
            SelectableText('Payload: ${_result.toString()}'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teste de Reconhecimento Facial')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _serviceIdController,
            decoration: InputDecoration(
              labelText: 'Service ID',
              helperText:
                  'Pode ser um UUID de teste. O backend usa isso para rastrear a validação.',
              suffixIcon: IconButton(
                onPressed: () {
                  _serviceIdController.text = const Uuid().v4();
                },
                icon: const Icon(Icons.refresh),
                tooltip: 'Gerar novo UUID',
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildImageCard(
            title: 'Foto do documento (CNH)',
            file: _cnhFile,
            bytes: _cnhBytes,
            onCamera: () => _pickImage(isCnh: true, source: ImageSource.camera),
            onGallery: () =>
                _pickImage(isCnh: true, source: ImageSource.gallery),
          ),
          _buildImageCard(
            title: 'Selfie',
            file: _selfieFile,
            bytes: _selfieBytes,
            onCamera: () =>
                _pickImage(isCnh: false, source: ImageSource.camera),
            onGallery: () =>
                _pickImage(isCnh: false, source: ImageSource.gallery),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _runValidation,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.face),
              label: Text(
                _submitting ? 'Validando reconhecimento...' : 'Validar agora',
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  _error!,
                  style: TextStyle(color: Colors.red.shade900),
                ),
              ),
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            _buildResultCard(),
          ],
        ],
      ),
    );
  }
}
