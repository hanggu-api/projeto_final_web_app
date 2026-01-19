import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ProofVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final double? height;

  const ProofVideoPlayer({
    super.key,
    required this.videoUrl,
    this.height = 250,
  });

  @override
  State<ProofVideoPlayer> createState() => _ProofVideoPlayerState();
}

class _ProofVideoPlayerState extends State<ProofVideoPlayer> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _error = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await _controller.initialize();
      if (mounted) {
        setState(() {
          _initialized = true;
          _error = false;
        });
      }
    } catch (e) {
      debugPrint('Error initializing proof video ${widget.videoUrl}: $e');
      if (mounted) {
        setState(() => _error = true);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      _playing = !_playing;
      if (_playing) {
        _controller.play();
      } else {
        _controller.pause();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return Container(
        height: widget.height,
        color: Colors.grey[200],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.videoOff, color: Colors.grey),
              SizedBox(height: 8),
              Text('Erro ao carregar vídeo', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    if (!_initialized) {
      return Container(
        height: widget.height,
        color: Colors.black12,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          ),
          Positioned.fill(
            child: GestureDetector(
              onTap: _togglePlay,
              child: Container(
                color: Colors.transparent,
                child: !_playing
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
          if (_playing)
            Positioned(
              bottom: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.pause, color: Colors.white70),
                onPressed: _togglePlay,
              ),
            ),
        ],
      ),
    );
  }
}
