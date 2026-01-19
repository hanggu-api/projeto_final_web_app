import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraCaptureModal extends StatefulWidget {
  const CameraCaptureModal({super.key});

  @override
  State<CameraCaptureModal> createState() => _CameraCaptureModalState();
}

class _CameraCaptureModalState extends State<CameraCaptureModal> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
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

      // Prioritize back camera
      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.high,
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

  Future<void> _takePicture() async {
    if (!_isInitialized || _controller == null) return;
    try {
      final image = await _controller!.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(image);
    } catch (e) {
      debugPrint('Error taking picture: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tirar Foto',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            
            // Camera Preview
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
                  : _isInitialized && _controller != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CameraPreview(_controller!),
                        )
                      : const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
            
            // Footer / Capture Button
            Padding(
              padding: const EdgeInsets.all(24),
              child: InkWell(
                onTap: _takePicture,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    color: Colors.transparent,
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
