import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class AssetVideoPlayer extends StatefulWidget {
  final String assetPath;
  final double? height;
  final BoxFit fit;

  const AssetVideoPlayer({
    super.key,
    required this.assetPath,
    this.height,
    this.fit = BoxFit.contain,
  });

  @override
  State<AssetVideoPlayer> createState() => _AssetVideoPlayerState();
}

class _AssetVideoPlayerState extends State<AssetVideoPlayer> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      _controller = VideoPlayerController.asset(widget.assetPath);
      await _controller.initialize();
      if (mounted) {
        setState(() {
          _initialized = true;
          _error = false;
        });
        _controller.setLooping(true);
        _controller.play();
        _controller.setVolume(0);
      }
    } catch (e) {
      debugPrint('Error initializing video asset ${widget.assetPath}: $e');
      if (mounted) {
        setState(() {
          _error = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text(
                'Buscando os melhores profissionais...',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    if (!_initialized) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
          ),
        ),
      );
    }

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Center(
        child: AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        ),
      ),
    );
  }
}
