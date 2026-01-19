import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';

import '../../services/api_service.dart';

class VideoBubble extends StatefulWidget {
  final String mediaKey;
  final ApiService api;
  final bool isMe;

  const VideoBubble({
    super.key,
    required this.mediaKey,
    required this.api,
    required this.isMe,
  });

  @override
  State<VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<VideoBubble> {
  @override
  void initState() {
    super.initState();
  }

  void _openTheaterMode() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: _TheaterVideoPlayer(mediaKey: widget.mediaKey, api: widget.api),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openTheaterMode,
      child: Container(
        width: 240,
        height: 180,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                color: Colors.black26,
                child: const Center(
                  child: Icon(
                    LucideIcons.video,
                    color: Colors.white54,
                    size: 48,
                  ),
                ),
              ),
              const Center(
                child: Icon(
                  LucideIcons.playCircle,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TheaterVideoPlayer extends StatefulWidget {
  final String mediaKey;
  final ApiService api;

  const _TheaterVideoPlayer({required this.mediaKey, required this.api});

  @override
  State<_TheaterVideoPlayer> createState() => _TheaterVideoPlayerState();
}

class _TheaterVideoPlayerState extends State<_TheaterVideoPlayer> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _isPlaying = false;
  int _bufferPercentage = 0;
  Timer? _bufferTimer;

  @override
  void initState() {
    super.initState();
    _loadVideo();
  }

  Future<void> _loadVideo() async {
    try {
      final url = await widget.api.getMediaViewUrl(widget.mediaKey);
      if (mounted) {
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(url),
          httpHeaders: widget.api.authHeaders,
        );

        // Start checking buffer status
        _bufferTimer = Timer.periodic(const Duration(milliseconds: 500), (
          timer,
        ) {
          if (_controller != null && _controller!.value.isInitialized) {
            final duration = _controller!.value.duration.inMilliseconds;
            if (duration > 0) {
              int maxBuffered = 0;
              for (final range in _controller!.value.buffered) {
                final end = range.end.inMilliseconds;
                if (end > maxBuffered) maxBuffered = end;
              }
              final pct = (maxBuffered / duration * 100).clamp(0, 100).toInt();
              if (mounted && pct != _bufferPercentage) {
                setState(() => _bufferPercentage = pct);
              }
            }
          }
        });

        await _controller!.initialize();
        if (mounted) {
          setState(() {
            _initialized = true;
            _isPlaying = true;
          });
          _controller!.play();
        }
      }
    } catch (e) {
      debugPrint('Error loading video: $e');
    }
  }

  @override
  void dispose() {
    _bufferTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _controller?.value.aspectRatio ?? 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_initialized && _controller != null)
              VideoPlayer(_controller!)
            else
              Container(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        'Carregando... $_bufferPercentage%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (_initialized)
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (_controller!.value.isPlaying) {
                      _controller!.pause();
                      _isPlaying = false;
                    } else {
                      _controller!.play();
                      _isPlaying = true;
                    }
                  });
                },
                child: Container(
                  color: Colors.transparent,
                  child: Center(
                    child: !_isPlaying
                        ? const Icon(
                            LucideIcons.play,
                            color: Colors.white,
                            size: 64,
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
