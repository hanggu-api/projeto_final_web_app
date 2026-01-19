import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/custom_alert.dart';

class CameraModal extends StatefulWidget {
  final bool onlyPhoto;
  const CameraModal({super.key, this.onlyPhoto = false});

  @override
  State<CameraModal> createState() => _CameraModalState();
}

class _CameraModalState extends State<CameraModal> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isRecording = false;
  bool _isStartingRecording = false;
  DateTime? _recordingStartTime;
  Timer? _timer;
  int _recordSeconds = 0;
  XFile? _capturedFile;
  bool _isVideo = false;
  bool _isVideoMode = false; // Toggle between Photo/Video mode
  VideoPlayerController? _videoController;
  int _selectedCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _timer?.cancel();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      if (_cameras.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nenhuma câmera encontrada')),
          );
          Navigator.of(context).pop();
        }
        return;
      }

      // Ensure index is valid
      if (_selectedCameraIndex >= _cameras.length) {
        _selectedCameraIndex = 0;
      }

      // Dispose previous controller if any
      if (_controller != null) {
        await _controller!.dispose();
      }

      _controller = CameraController(
        _cameras[_selectedCameraIndex],
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await _controller!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao iniciar câmera: $e')));
      }
    }
  }

  void _toggleCamera() {
    if (_cameras.length < 2) return;
    setState(() {
      _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    });
    _initCamera();
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isTakingPicture) return;

    try {
      final file = await _controller!.takePicture();
      setState(() {
        _capturedFile = file;
        _isVideo = false;
      });
    } catch (e) {
      debugPrint('Error taking picture: $e');
    }
  }

  Future<void> _startRecording() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _controller!.value.isRecordingVideo ||
        _isStartingRecording ||
        _isStopping) {
      return;
    }

    try {
      _isStartingRecording = true;
      await _controller!.startVideoRecording();
      _recordingStartTime = DateTime.now();
      if (mounted) {
        setState(() {
          _isRecording = true;
          _recordSeconds = 0;
        });
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) setState(() => _recordSeconds++);
        });
      }
    } catch (e) {
      debugPrint('Error starting video: $e');
      _isRecording = false;
    } finally {
      _isStartingRecording = false;
    }
  }

  bool _isStopping = false;

  Future<void> _stopRecording() async {
    // Prevent stopping while starting or if recording hasn't started
    if (_isStartingRecording) {
      while (_isStartingRecording) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    if (_controller == null || !_isRecording || _isStopping) return;

    _isStopping = true;

    // Enforce minimum recording duration (2.0s) to avoid empty/corrupted files
    if (_recordingStartTime != null) {
      final elapsed = DateTime.now().difference(_recordingStartTime!);
      if (elapsed.inMilliseconds < 2000) {
        await Future.delayed(
          Duration(milliseconds: 2000 - elapsed.inMilliseconds),
        );
      }
    }

    if (!mounted) return;

    try {
      final file = await _controller!.stopVideoRecording();
      _timer?.cancel();

      if (kIsWeb) {
        // Force valid extension on Web if missing
        if (!file.path.endsWith('.mp4') && !file.path.endsWith('.webm')) {
          // We can't rename the file easily here, but we can trust _isVideo flag
        }
      }

      setState(() {
        _isRecording = false;
        _capturedFile = file;
        _isVideo = true; // Explicitly set to true for video
      });

      if (kIsWeb) {
        // On Web, use networkUrl for blob
        _videoController = VideoPlayerController.networkUrl(
          Uri.parse(file.path),
        );
        await _videoController!.initialize();
        await _videoController!.setLooping(true);
        await _videoController!.play();
        if (mounted) setState(() {});
      } else {
        _videoController = VideoPlayerController.file(File(file.path));
        await _videoController!.initialize();
        await _videoController!.setLooping(true);
        await _videoController!.play();
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('Error stopping video: $e');
      // Reset state on error so user can try again
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordSeconds = 0;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao salvar vídeo: $e')));
      }
    } finally {
      _isStopping = false;
    }
  }

  Future<void> _confirm() async {
    if (_capturedFile != null) {
      // Safety check: if we have a video controller initialized, it MUST be a video
      if (_videoController != null && _videoController!.value.isInitialized) {
        _isVideo = true;
      }

      debugPrint(
        'CameraModal: Confirming capture. isVideo: $_isVideo, path: ${_capturedFile!.path}',
      );

      if (kIsWeb) {
        final confirm = await CustomAlert.show(
          context: context,
          title: _isVideo ? 'Enviar Vídeo?' : 'Enviar Foto?',
          content: _isVideo
              ? 'O vídeo será enviado para o chat.'
              : 'A foto será enviada para o chat.',
          confirmText: 'Enviar',
          cancelText: 'Cancelar',
          icon: _isVideo ? LucideIcons.video : LucideIcons.camera,
        );

        if (confirm == true) {
          if (!mounted) return;
          Navigator.of(
            context,
          ).pop({'file': _capturedFile, 'isVideo': _isVideo});
        }
      } else {
        Navigator.of(context).pop({'file': _capturedFile, 'isVideo': _isVideo});
      }
    }
  }

  void _retake() {
    setState(() {
      _capturedFile = null;
      _isVideo = false;
      _videoController?.dispose();
      _videoController = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_capturedFile != null) {
      // Review Screen
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_isVideo)
              _videoController != null && _videoController!.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    )
                  : const Center(
                      child: Text(
                        'Vídeo capturado',
                        style: TextStyle(color: Colors.white),
                      ),
                    )
            else
              kIsWeb
                  ? Image.network(_capturedFile!.path)
                  : Image.file(File(_capturedFile!.path)),

            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    onPressed: _retake,
                    icon: const Icon(
                      LucideIcons.x,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  IconButton(
                    onPressed: _confirm,
                    icon: Icon(
                      LucideIcons.check,
                      color: AppTheme.successGreen,
                      size: 32,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Camera Preview Screen
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(child: CameraPreview(_controller!)),
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(LucideIcons.x, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            top: 40,
            left: 20,
            child: IconButton(
              icon: const Icon(
                Icons.flip_camera_android,
                color: Colors.white,
                size: 30,
              ),
              onPressed: _toggleCamera,
            ),
          ),
          if (_isRecording)
            Positioned(
              top: 50,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '00:${_recordSeconds.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

          // Shutter Button
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () {
                  if (_isVideoMode) {
                    if (_isRecording) {
                      _stopRecording();
                    } else {
                      _startRecording();
                    }
                  } else {
                    _takePicture();
                  }
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: _isRecording ? 40 : 70,
                      height: _isRecording ? 40 : 70,
                      decoration: BoxDecoration(
                        color: _isVideoMode ? Colors.red : Colors.white,
                        shape: _isRecording
                            ? BoxShape.rectangle
                            : BoxShape.circle,
                        borderRadius: _isRecording
                            ? BorderRadius.circular(8)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Mode Switcher
          if (!widget.onlyPhoto)
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildModeButton('FOTO', !_isVideoMode, () {
                    if (_isRecording) return;
                    setState(() => _isVideoMode = false);
                  }),
                  const SizedBox(width: 20),
                  _buildModeButton('VÍDEO', _isVideoMode, () {
                    if (_isRecording) return;
                    setState(() => _isVideoMode = true);
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModeButton(String text, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isActive ? Colors.black : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
