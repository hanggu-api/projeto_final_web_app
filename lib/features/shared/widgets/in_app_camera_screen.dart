import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:service_101/services/ocr_service.dart';
import 'package:service_101/services/device_capability_service.dart';

enum LivenessStep {
  centering,
  blinking,
  turningLeft,
  turningRight,
  fixating,
  done,
}

class InAppCameraScreen extends StatefulWidget {
  final bool isSelfie;
  final bool blinkOnly; // Novo parâmetro
  const InAppCameraScreen({
    super.key,
    this.isSelfie = false,
    this.blinkOnly = false,
  });

  @override
  State<InAppCameraScreen> createState() => _InAppCameraScreenState();
}

class _InAppCameraScreenState extends State<InAppCameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isReady = false;
  bool _isCapturing = false;

  // ML Kit Detectors
  FaceDetector? _faceDetector;
  TextRecognizer? _textRecognizer;

  bool _isProcessingImage = false;
  bool _targetDetected = false;
  bool _targetCentered = false;
  DateTime? _targetCenteredStartTime;
  double _captureProgress = 0.0;

  // Liveness State
  LivenessStep _currentStep = LivenessStep.centering;
  bool _leftEyeClosed = false;
  int _blinkCount = 0;
  int _targetBlinks = 1;
  DateTime? _fixatingStartTime;
  String _livenessInstruction = "Aguardando rosto...";
  bool _manualCaptureMode = false;

  // TTS Configuration
  late FlutterTts _flutterTts;
  String _lastSpokenText = "";
  DateTime? _lastSpokenTime;

  @override
  void initState() {
    super.initState();
    _initTts();
    _initializeCamera();
  }

  void _initTts() {
    _flutterTts = FlutterTts();
    _flutterTts.setLanguage("pt-BR");
    _flutterTts.setPitch(1.0);
    _flutterTts.setSpeechRate(0.5);
  }

  Future<void> _speak(String text) async {
    if (text.isEmpty) return;

    // Evita falar o mesmo texto repetidamente em um curto intervalo (3 seg)
    final now = DateTime.now();
    if (_lastSpokenText == text &&
        _lastSpokenTime != null &&
        now.difference(_lastSpokenTime!).inSeconds < 3) {
      return;
    }

    _lastSpokenText = text;
    _lastSpokenTime = now;
    await _flutterTts.speak(text);
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) return;

      final camera = _cameras!.firstWhere(
        (c) => widget.isSelfie
            ? c.lensDirection == CameraLensDirection.front
            : c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        camera,
        DeviceCapabilityService.instance.isLowEndDevice
            ? ResolutionPreset.medium
            : ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: !kIsWeb && Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _controller!.initialize();

      _manualCaptureMode =
          (!widget.isSelfie &&
              DeviceCapabilityService.instance.prefersSimplifiedDocumentScan) ||
          (widget.isSelfie &&
              DeviceCapabilityService.instance.prefersSimplifiedFaceLiveness);

      if (widget.isSelfie) {
        _faceDetector = FaceDetector(
          options: FaceDetectorOptions(
            enableContours: false,
            enableClassification: true,
            performanceMode: FaceDetectorMode.fast,
          ),
        );
      } else {
        _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      }

      if (!_manualCaptureMode) {
        _startImageStream();
      } else {
        _targetDetected = true;
        _livenessInstruction = widget.isSelfie
            ? "Modo leve ativo. Posicione o rosto e toque para capturar."
            : "Modo leve ativo. Enquadre a CNH e toque para capturar.";
      }

      if (mounted) {
        setState(() => _isReady = true);
      }
    } catch (e) {
      debugPrint('❌ Erro ao inicializar câmera: $e');
    }
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _faceDetector?.close();
    _textRecognizer?.close();
    _flutterTts.stop();
    super.dispose();
  }

  void _startImageStream() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    _controller!.startImageStream((CameraImage image) {
      if (_isProcessingImage || !mounted || _isCapturing) return;

      _processImage(image);
    });
  }

  Future<void> _processImage(CameraImage image) async {
    _isProcessingImage = true;

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final InputImageRotation rotation = _getInputImageRotation();
      final InputImageFormat format = _getInputImageFormat(image.format.group);

      final inputImageMetadata = InputImageMetadata(
        size: imageSize,
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: inputImageMetadata,
      );

      if (widget.isSelfie && _faceDetector != null) {
        final List<Face> faces = await _faceDetector!.processImage(inputImage);
        Size effectiveSize = imageSize;
        if (rotation == InputImageRotation.rotation90deg ||
            rotation == InputImageRotation.rotation270deg) {
          effectiveSize = Size(imageSize.height, imageSize.width);
        }

        if (mounted) {
          _analyzeFaces(faces, effectiveSize);
        }
      } else if (!widget.isSelfie && _textRecognizer != null) {
        final RecognizedText recognizedText = await _textRecognizer!
            .processImage(inputImage);
        if (mounted) {
          _analyzeDocument(recognizedText, imageSize);
        }
      }
    } catch (e) {
      debugPrint('❌ Erro processando frame: $e');
    } finally {
      await Future.delayed(
        DeviceCapabilityService.instance.isLowEndDevice
            ? const Duration(milliseconds: 260)
            : const Duration(milliseconds: 150),
      );
      _isProcessingImage = false;
    }
  }

  InputImageRotation _getInputImageRotation() {
    final sensorOrientation = _controller!.description.sensorOrientation;
    switch (sensorOrientation) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  InputImageFormat _getInputImageFormat(ImageFormatGroup group) {
    if (!kIsWeb && Platform.isAndroid) return InputImageFormat.nv21;
    return InputImageFormat.bgra8888;
  }

  void _analyzeFaces(List<Face> faces, Size imageSize) {
    if (faces.isEmpty) {
      if (_targetDetected ||
          _targetCentered ||
          _livenessInstruction != "Aguardando rosto...") {
        setState(() {
          _targetDetected = false;
          _targetCentered = false;
          _captureProgress = 0.0;
          _targetCenteredStartTime = null;
          _currentStep = LivenessStep.centering;
          _livenessInstruction = "Aguardando rosto...";
        });
      }
      return;
    }

    final face = faces.first;
    final rect = face.boundingBox;
    final double centerX = imageSize.width / 2;
    final double centerY = imageSize.height / 2;

    final bool isCentered =
        (rect.center.dx - centerX).abs() < (imageSize.width * 0.25) &&
        (rect.center.dy - centerY).abs() < (imageSize.height * 0.25);
    final bool isCorrectSize =
        rect.width > (imageSize.width * 0.25) &&
        rect.width < (imageSize.width * 0.85);

    final bool currentCentered = isCentered && isCorrectSize;

    if (currentCentered != _targetCentered || !_targetDetected) {
      setState(() {
        _targetDetected = true;
        _targetCentered = currentCentered;
        if (currentCentered) {
          _targetCenteredStartTime ??= DateTime.now();
        } else {
          _targetCenteredStartTime = null;
          _captureProgress = 0.0;
        }
      });
    }

    if (!currentCentered && _currentStep == LivenessStep.centering) {
      String msg = "Aproxime seu rosto";
      if (!isCentered) {
        msg = "Enquadre seu rosto no círculo";
      } else if (rect.width < (imageSize.width * 0.25)) {
        msg = "Aproxime seu rosto da tela";
      } else if (rect.width > (imageSize.width * 0.9)) {
        msg = "Afaste um pouco o rosto";
      }

      if (_livenessInstruction != msg) {
        setState(() => _livenessInstruction = msg);
        _speak(msg);
      }
      return;
    }

    switch (_currentStep) {
      case LivenessStep.centering:
        final elapsed = _targetCenteredStartTime != null
            ? DateTime.now()
                  .difference(_targetCenteredStartTime!)
                  .inMilliseconds
            : 0;
        setState(() {
          _livenessInstruction = "Fique parado...";
          _captureProgress = 0.1;
        });
        if (elapsed > 600) {
          setState(() {
            _currentStep = LivenessStep.blinking;
            _targetBlinks = 1; // Apenas uma piscada agora
            _blinkCount = 0;
            _leftEyeClosed = false;
            _captureProgress = 0.3;
            _livenessInstruction = "Agora pisque os olhos";
          });
          _speak("Agora pisque os olhos");
        }
        break;

      case LivenessStep.blinking:
        final double? leftProb = face.leftEyeOpenProbability;
        final double? rightProb = face.rightEyeOpenProbability;
        if (leftProb != null && rightProb != null) {
          if (leftProb < 0.2 && rightProb < 0.2) {
            if (!_leftEyeClosed) {
              _leftEyeClosed = true;
            }
          }
          if (_leftEyeClosed && leftProb > 0.6 && rightProb > 0.6) {
            _blinkCount++;
            _leftEyeClosed = false;
            if (_blinkCount >= _targetBlinks) {
              if (widget.blinkOnly) {
                // Se for apenas piscada, pula direto para o final
                setState(() {
                  _currentStep = LivenessStep.done;
                  _captureProgress = 1.0;
                  _livenessInstruction = "Perfeito! Capturando...";
                });
                Future.delayed(
                  const Duration(milliseconds: 100),
                  () => _capture(),
                );
              } else {
                setState(() {
                  _currentStep = LivenessStep.turningLeft;
                  _captureProgress = 0.5;
                  _livenessInstruction =
                      "Gire levemente a cabeça para a ESQUERDA";
                });
              }
            } else {
              setState(
                () => _livenessInstruction =
                    "Pisca de novo! (${_targetBlinks - _blinkCount} restante)",
              );
            }
          }
        }
        break;

      case LivenessStep.turningLeft:
        final headYaw = face.headEulerAngleY; // Rotação para os lados
        if (headYaw != null && headYaw > 15) {
          // Virou para a esquerda (yaw positivo no ML Kit para câmera frontal geralmente)
          setState(() {
            _currentStep = LivenessStep.turningRight;
            _captureProgress = 0.7;
            _livenessInstruction = "Gire levemente a cabeça para a DIREITA";
          });
        }
        break;

      case LivenessStep.turningRight:
        final headYaw = face.headEulerAngleY;
        if (headYaw != null && headYaw < -15) {
          // Virou para a direita
          setState(() {
            _currentStep = LivenessStep.fixating;
            _fixatingStartTime = DateTime.now();
            _captureProgress = 0.9;
            _livenessInstruction = "Agora olhe fixo para frente";
          });
        }
        break;

      case LivenessStep.fixating:
        final pitch = face.headEulerAngleX ?? 0;
        final yaw = face.headEulerAngleY ?? 0;
        final roll = face.headEulerAngleZ ?? 0;
        bool isStraight =
            pitch.abs() < 8.0 && yaw.abs() < 8.0 && roll.abs() < 5.0;

        if (isStraight) {
          final elapsed = _fixatingStartTime != null
              ? DateTime.now().difference(_fixatingStartTime!).inMilliseconds
              : 0;
          if (elapsed > 800) {
            setState(() {
              _currentStep = LivenessStep.done;
              _captureProgress = 1.0;
              _livenessInstruction = "Perfeito! Capturando...";
            });
            Future.delayed(const Duration(milliseconds: 100), () => _capture());
          }
        } else {
          _fixatingStartTime = DateTime.now();
          if (_livenessInstruction != "Mantenha a cabeça reta") {
            setState(() => _livenessInstruction = "Mantenha a cabeça reta");
          }
        }
        break;

      case LivenessStep.done:
        break;
    }
  }

  void _analyzeDocument(RecognizedText recognizedText, Size imageSize) {
    final bool hasText =
        recognizedText.blocks.length >=
        2; // Reduzido de 3 para 2 para ser mais responsivo
    if (hasText) {
      if (!_targetCentered || !_targetDetected) {
        setState(() {
          _targetDetected = true;
          _targetCentered = true;
          _targetCenteredStartTime ??= DateTime.now();
        });
      }
      _checkAutoCapture(1500);
    } else {
      if (_targetDetected || _targetCentered) {
        setState(() {
          _targetDetected = false;
          _targetCentered = false;
          _captureProgress = 0.0;
          _targetCenteredStartTime = null;
        });
      }
    }
  }

  void _checkAutoCapture(int durationMs) {
    if (_manualCaptureMode) return;
    if (_targetCentered && _targetCenteredStartTime != null) {
      final elapsed = DateTime.now()
          .difference(_targetCenteredStartTime!)
          .inMilliseconds;
      final progress = (elapsed / durationMs).clamp(0.0, 1.0);
      if (progress != _captureProgress) {
        setState(() => _captureProgress = progress);
      }
      if (progress >= 1.0 && !_isCapturing) {
        _capture();
      }
    }
  }

  Future<void> _capture() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) {
      return;
    }

    setState(() => _isCapturing = true);
    try {
      final XFile imageFile = await _controller!.takePicture();

      if (!widget.isSelfie) {
        final processedFile = await _processDocumentImage(imageFile);
        final ocrService = OcrService();
        final cnhData = await ocrService.processCNH(processedFile.path);
        ocrService.dispose();

        if (mounted) {
          if (cnhData.isValidCNH) {
            Navigator.pop(context, {'file': processedFile, 'data': cnhData});
          } else {
            setState(() {
              _isCapturing = false;
              _livenessInstruction = "Documento não reconhecido como CNH!";
              _captureProgress = 0.0;
              _targetCenteredStartTime = null;
              _targetDetected = _manualCaptureMode;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Por favor, posicione uma CNH válida dentro da moldura.',
                ),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        }
      } else {
        if (mounted) Navigator.pop(context, imageFile);
      }
    } catch (e) {
      debugPrint('❌ Erro ao capturar foto: $e');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<XFile> _processDocumentImage(XFile originalFile) async {
    try {
      final bytes = await originalFile.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return originalFile;

      final int w = image.width;
      final int h = image.height;
      final cropW = (w * 0.9).toInt();
      final cropH = (cropW * 0.65).toInt();
      final startX = (w - cropW) ~/ 2;
      final startY = (h - cropH) ~/ 2;

      img.Image cropped = img.copyCrop(
        image,
        x: startX,
        y: startY,
        width: cropW,
        height: cropH,
      );
      img.Image grayscale = img.grayscale(cropped);
      img.Image processed = img.contrast(grayscale, contrast: 120);

      final tempDir = Directory.systemTemp;
      final processedPath =
          '${tempDir.path}/processed_doc_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final processedBytes = img.encodeJpg(processed, quality: 85);

      final file = File(processedPath);
      await file.writeAsBytes(processedBytes);

      return XFile(processedPath);
    } catch (e) {
      debugPrint('❌ Erro no processamento de imagem: $e');
      return originalFile;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final scale =
                  1 /
                  (_controller!.value.aspectRatio *
                      constraints.maxWidth /
                      constraints.maxHeight);
              return Transform.scale(
                scale: scale < 1 ? 1 / scale : scale,
                child: Center(child: CameraPreview(_controller!)),
              );
            },
          ),
          _buildOverlay(),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    LucideIcons.x,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                GestureDetector(
                  onTap: _capture,
                  child: Container(
                    height: 80,
                    width: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _targetCentered
                            ? const Color(0xFF2196F3)
                            : Colors.white,
                        width: 4,
                      ),
                      color: _targetCentered
                          ? const Color(0xFF2196F3).withOpacity(0.2)
                          : Colors.black26,
                    ),
                    child: Center(
                      child: _isCapturing
                          ? const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            )
                          : Container(
                              height: 60,
                              width: 60,
                              decoration: BoxDecoration(
                                color: _targetCentered
                                    ? const Color(0xFF2196F3)
                                    : Colors.white.withOpacity(0.8),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                LucideIcons.camera,
                                color: Colors.black54,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                widget.isSelfie
                    ? _livenessInstruction
                    : (_targetCentered
                          ? "Documento detectado! Capturando..."
                          : (_manualCaptureMode
                                ? "Enquadre sua CNH e toque para capturar"
                                : "Enquadre sua CNH dentro do retângulo")),
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double holeWidth = widget.isSelfie ? width * 0.7 : width * 0.9;
        final double holeHeight = widget.isSelfie
            ? holeWidth * 1.3
            : holeWidth * 0.65;
        Color borderColor = Colors.white;

        if (_targetCentered) {
          borderColor = const Color(0xFF1976D2); // Azul Royal Forte
        } else if (_targetDetected) {
          borderColor = const Color(0xFF2196F3); // Azul Material
        }

        return Stack(
          children: [
            Align(
              alignment: Alignment.center,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    height: holeHeight,
                    width: holeWidth,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: borderColor,
                        width: 8,
                      ), // Borda Grossa (8px)
                      borderRadius: BorderRadius.circular(
                        widget.isSelfie ? holeWidth / 2 : 16,
                      ),
                      // Removido BoxShadow que criava o efeito de névoa verde/azul sobre o rosto
                    ),
                  ),
                  if (_captureProgress > 0)
                    SizedBox(
                      height: holeHeight + 30,
                      width: holeWidth + 30,
                      child: CircularProgressIndicator(
                        value: _captureProgress,
                        strokeWidth: 6,
                        color: const Color(0xFF2196F3),
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  if (_currentStep == LivenessStep.fixating)
                    const Icon(
                      LucideIcons.target,
                      color: Color(0xFF00FF88),
                      size: 40,
                    ),
                  if (_currentStep == LivenessStep.turningLeft)
                    const Positioned(
                      left: 10,
                      child: Icon(
                        LucideIcons.arrowLeft,
                        color: Color(0xFF00FF88),
                        size: 60,
                      ),
                    ),
                  if (_currentStep == LivenessStep.turningRight)
                    const Positioned(
                      right: 10,
                      child: Icon(
                        LucideIcons.arrowRight,
                        color: Color(0xFF00FF88),
                        size: 60,
                      ),
                    ),
                ],
              ),
            ),
            CustomPaint(
              painter: HolePainter(holeWidth, holeHeight, widget.isSelfie),
            ),
          ],
        );
      },
    );
  }
}

class HolePainter extends CustomPainter {
  final double holeWidth;
  final double holeHeight;
  final bool isCircle;

  HolePainter(this.holeWidth, this.holeHeight, this.isCircle);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black45;
    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final holePath = Path();
    if (isCircle) {
      holePath.addOval(
        Rect.fromCenter(
          center: Offset(size.width / 2, size.height / 2),
          width: holeWidth,
          height: holeHeight,
        ),
      );
    } else {
      holePath.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(size.width / 2, size.height / 2),
            width: holeWidth,
            height: holeHeight,
          ),
          const Radius.circular(16),
        ),
      );
    }

    canvas.drawPath(
      Path.combine(PathOperation.difference, path, holePath),
      paint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
