import 'dart:async';
// import 'dart:async'; // Removed duplicate
// import 'dart:io'; // Removed unused import
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'; // for kIsWeb

class InAppCameraScreen extends StatefulWidget {
  final bool initialVideoMode;

  const InAppCameraScreen({super.key, this.initialVideoMode = false});

  @override
  State<InAppCameraScreen> createState() => _InAppCameraScreenState();
}

class _InAppCameraScreenState extends State<InAppCameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isRecording = false;
  bool _isInitialized = false;
  int _selectedCameraIndex = 0;
  DateTime? _recordingStartedAt;
  
  // Modes
  bool _isVideoMode = false;
  FlashMode _flashMode = FlashMode.off;

  // Video Limits
  static const Duration _maxDuration = Duration(minutes: 2);
  Timer? _recordingTimer;
  Timer? _progressTimer;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isVideoMode = widget.initialVideoMode;
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      
      await _onNewCameraSelected(_cameras[_selectedCameraIndex]);
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _onNewCameraSelected(CameraDescription cameraDescription) async {
    if (_controller != null) {
      await _controller!.dispose();
    }

    _controller = CameraController(
      cameraDescription,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _controller!.initialize();
      await _controller!.setFlashMode(_flashMode);
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      debugPrint('Error initializing controller: $e');
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    try {
      FlashMode newMode;
      if (_flashMode == FlashMode.off) {
        newMode = FlashMode.auto;
      } else if (_flashMode == FlashMode.auto) {
        newMode = FlashMode.always; // On
      } else {
        newMode = FlashMode.off;
      }
      
      await _controller!.setFlashMode(newMode);
      setState(() => _flashMode = newMode);
    } catch (e) {
      debugPrint('Error toggling flash: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      if (kIsWeb) {
        final result = await FilePicker.platform.pickFiles(
          type: _isVideoMode ? FileType.video : FileType.image,
          allowMultiple: false,
        );
        if (result != null && result.files.isNotEmpty) {
           final file = result.files.first;
           // Convert PlatfromFile to XFile-like structure if needed, or stick to XFile
           // ImagePicker returns XFile. Let's consistency use ImagePicker also for Web if possible
           // But FilePicker is often better. For now let's return XFile compatible object.
           // However, navigator pop expects XFile.
           final xfile = XFile(file.name, bytes: file.bytes, length: file.size, name: file.name); // Path is fake on web
           if (mounted) Navigator.pop(context, xfile);
        }
      } else {
         final ImagePicker picker = ImagePicker();
         final XFile? media = _isVideoMode
             ? await picker.pickVideo(source: ImageSource.gallery)
             : await picker.pickImage(source: ImageSource.gallery);
         
         if (media != null && mounted) {
           Navigator.pop(context, media);
         }
      }
    } catch (e) {
      debugPrint('Error picking from gallery: $e');
    }
  }


  Future<void> _capture() async {
    if (!_isInitialized || _controller == null) return;

    if (_isVideoMode) {
      // Toggle Recording
      if (_isRecording) {
        await _stopRecording();
      } else {
        await _startRecording();
      }
    } else {
      // Take Photo
      try {
        final file = await _controller!.takePicture();
        if (mounted) Navigator.pop(context, file);
      } catch (e) {
        debugPrint('Error taking photo: $e');
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      await _controller!.startVideoRecording();
      setState(() {
        _isRecording = true;
        _recordingStartedAt = DateTime.now();
        _progress = 0.0;
      });
      
      // Start timers
      _recordingTimer = Timer(_maxDuration, () {
        if (_isRecording) _stopRecording();
      });
      
      _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!_isRecording) {
          timer.cancel();
          return;
        }
        final elapsed = DateTime.now().difference(_recordingStartedAt!);
        setState(() {
          _progress = elapsed.inMilliseconds / _maxDuration.inMilliseconds;
          if (_progress > 1.0) _progress = 1.0;
        });
      });

    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      _recordingTimer?.cancel();
      _progressTimer?.cancel();
      
      // Safety delay for very short videos
      final elapsed = DateTime.now().difference(_recordingStartedAt!);
      if (elapsed.inMilliseconds < 1000) {
        await Future.delayed(Duration(milliseconds: 1000 - elapsed.inMilliseconds));
      }

      final file = await _controller!.stopVideoRecording();
      setState(() => _isRecording = false);
      if (mounted) Navigator.pop(context, file);
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    }
  }

  void _switchCamera() async {
    if (_cameras.length < 2) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _onNewCameraSelected(_cameras[_selectedCameraIndex]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _progressTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  IconData _getFlashIcon() {
    switch (_flashMode) {
      case FlashMode.off: return Icons.flash_off;
      case FlashMode.auto: return Icons.flash_auto;
      case FlashMode.always: return Icons.flash_on;
      default: return Icons.flash_off;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Preview
          CameraPreview(_controller!),
          
          // 2. Overlay Gradient (Top/Bottom) for visibility
          Positioned.fill(
             child: Column(
               children: [
                 Container(
                   height: 120,
                   decoration: BoxDecoration(
                     gradient: LinearGradient(
                       begin: Alignment.topCenter,
                       end: Alignment.bottomCenter,
                       colors: [
                         Colors.black.withValues(alpha: 0.6),
                         Colors.transparent
                       ]
                     )
                   ),
                 ),
                 const Spacer(),
                 Container(
                   height: 200,
                   decoration: BoxDecoration(
                     gradient: LinearGradient(
                       begin: Alignment.bottomCenter,
                       end: Alignment.topCenter,
                       colors: [
                         Colors.black.withValues(alpha: 0.8),
                         Colors.transparent
                       ]
                     )
                   ),
                 ),
               ],
             ),
          ),

          // 3. Top Controls (Close, Flash)
          Positioned(
            top: 40,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(LucideIcons.x, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
                IconButton(
                  icon: Icon(_getFlashIcon(), color: Colors.white, size: 28),
                  onPressed: _toggleFlash,
                ),
              ],
            ),
          ),

          // 4. Timer (Recording Mode)
          if (_isRecording)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _formatDuration(DateTime.now().difference(_recordingStartedAt ?? DateTime.now())),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ),


          // 5. Bottom Controls
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Column(
              children: [
                // Mode Selector
                 if (!_isRecording)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildModeButton('FOTO', !_isVideoMode),
                      const SizedBox(width: 20),
                      _buildModeButton('VÍDEO', _isVideoMode),
                    ],
                  ),
                
                 const SizedBox(height: 20),

                 Row(
                   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                   children: [
                     // Gallery
                     IconButton(
                       icon: const Icon(LucideIcons.image, color: Colors.white, size: 32),
                       onPressed: _isRecording ? null : _pickFromGallery,
                     ),

                     // Shutter Button
                     GestureDetector(
                       onTap: _capture,
                       child: _buildShutterButton(),
                     ),

                     // Switch Camera
                     IconButton(
                       icon: const Icon(LucideIcons.refreshCcw, color: Colors.white, size: 32),
                       onPressed: _isRecording ? null : _switchCamera,
                     ),
                   ],
                 ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(String text, bool isSelected) {
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          setState(() {
            _isVideoMode = !_isVideoMode;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: isSelected ? BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(16)
        ) : null,
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? Colors.amberAccent : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
            shadows: const [
              Shadow(color: Colors.black, blurRadius: 4)
            ]
          ),
        ),
      ),
    );
  }

  Widget _buildShutterButton() {
     if (_isRecording) {
       return Stack(
         alignment: Alignment.center,
         children: [
           SizedBox(
             width: 80,
             height: 80,
             child: CircularProgressIndicator(
               value: _progress,
               strokeWidth: 4,
               valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
               backgroundColor: Colors.white24,
             ),
           ),
           Container(
             width: 30,
             height: 30,
             decoration: BoxDecoration(
               color: Colors.red,
               borderRadius: BorderRadius.circular(4),
             ),
           )
         ],
       );
     }

     return Container(
       width: 72,
       height: 72,
       decoration: BoxDecoration(
         shape: BoxShape.circle,
         border: Border.all(color: Colors.white, width: 4),
       ),
       child: Center(
         child: Container(
           width: 60,
           height: 60,
           decoration: BoxDecoration(
             color: _isVideoMode ? Colors.red : Colors.white,
             shape: BoxShape.circle,
           ),
         ),
       ),
     );
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}
