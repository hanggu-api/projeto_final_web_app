import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../features/shared/camera_modal.dart';

class VideoMediaWidget extends StatefulWidget {
  final String? videoKey;
  final void Function(XFile)? onVideoRecorded;
  final void Function()? onVideoRemoved;

  const VideoMediaWidget({
    super.key,
    this.videoKey,
    String? initialVideoKey,
    this.onVideoRecorded,
    this.onVideoRemoved,
  });

  @override
  State<VideoMediaWidget> createState() => _VideoMediaWidgetState();
}

class _VideoMediaWidgetState extends State<VideoMediaWidget> {
  String? _selectedVideoPath;
  final ImagePicker _picker = ImagePicker();
  VideoPlayerController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideoPlayer(String path) async {
    try {
      Uri uri;
      if (kIsWeb) {
        uri = Uri.parse(path);
      } else {
        uri = Uri.file(path);
      }
      _controller = VideoPlayerController.networkUrl(uri);

      await _controller!.initialize();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error initializing video player: $e');
    }
  }

  Future<void> _showSourceSelector() async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Adicionar Vídeo',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('Gravar Vídeo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library),
                title: const Text('Escolher da Galeria'),
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        // Use custom CameraModal for recording
        final result = await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => Container(
            height: MediaQuery.of(context).size.height - 20,
            decoration: const BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: const CameraModal(),
            ),
          ),
        );

        if (result != null && result is Map) {
          final file = result['file'] as XFile?;
          final isVideo = result['isVideo'] as bool? ?? false;

          if (file != null && isVideo) {
            setState(() {
              _selectedVideoPath = file.path;
            });
            _initializeVideoPlayer(file.path);
            widget.onVideoRecorded?.call(file);
          } else if (file != null && !isVideo) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Por favor, grave um vídeo (segure o botão)'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        }
      } else {
        // Use ImagePicker for gallery
        final XFile? video = await _picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(minutes: 2),
        );

        if (video != null) {
          setState(() {
            _selectedVideoPath = video.path;
          });
          _initializeVideoPlayer(video.path);
          if (widget.onVideoRecorded != null) {
            widget.onVideoRecorded!(video);
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao selecionar vídeo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedVideoPath != null &&
        _controller != null &&
        _controller!.value.isInitialized) {
      return Stack(
        children: [
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    if (_controller!.value.isPlaying) {
                      _controller!.pause();
                    } else {
                      _controller!.play();
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _controller!.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () {
                _controller?.pause();
                setState(() {
                  _selectedVideoPath = null;
                  _controller = null;
                });
                widget.onVideoRemoved?.call();
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showSourceSelector,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _selectedVideoPath != null ? Icons.check : Icons.videocam,
                    color: Colors.blue,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedVideoPath != null
                            ? 'Vídeo selecionado'
                            : 'Adicionar Vídeo',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedVideoPath != null
                            ? 'Toque para alterar'
                            : 'Mostre o problema em vídeo',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                    ],
                  ),
                ),
                if (_selectedVideoPath != null)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () {
                      setState(() {
                        _selectedVideoPath = null;
                      });
                      if (widget.onVideoRemoved != null) {
                        widget.onVideoRemoved!();
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
