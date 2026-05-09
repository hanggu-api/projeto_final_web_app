import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../services/api_service.dart';

class AudioBubble extends StatefulWidget {
  final String mediaKey;
  final ApiService api;
  final bool isMe;
  const AudioBubble({
    super.key,
    required this.mediaKey,
    required this.api,
    required this.isMe,
  });

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _loadingUrl = true;
  Uint8List? _bytes;
  bool _playing = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.mediaKey.startsWith('http') ||
        (widget.mediaKey.contains('/') && !kIsWeb)) {
      setState(() => _loadingUrl = false);
    } else {
      widget.api
          .getMediaBytes(widget.mediaKey)
          .then((b) {
            if (!mounted) return;
            setState(() {
              _bytes = b;
              _loadingUrl = false;
            });
          })
          .catchError((_) {
            if (mounted) setState(() => _loadingUrl = false);
          });
    }

    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_loadingUrl) return;
    final isLocal =
        !widget.mediaKey.startsWith('http') && widget.mediaKey.contains('/');
    if (!widget.mediaKey.startsWith('http') && !isLocal && _bytes == null) {
      return;
    }

    try {
      if (_playing) {
        await _player.pause();
        setState(() => _playing = false);
      } else {
        if (_player.state == PlayerState.paused) {
          await _player.resume();
        } else {
          if (widget.mediaKey.startsWith('http')) {
            await _player.play(UrlSource(widget.mediaKey));
          } else if (isLocal && !kIsWeb) {
            await _player.play(DeviceFileSource(widget.mediaKey));
          } else if (kIsWeb) {
            final dataUri = 'data:audio/mpeg;base64,${base64Encode(_bytes!)}';
            await _player.play(UrlSource(dataUri));
          } else {
            final tempDir = await getTemporaryDirectory();
            final file = File(
              '${tempDir.path}/audio_${widget.mediaKey.hashCode}.m4a',
            );
            if (!await file.exists()) await file.writeAsBytes(_bytes!);
            await _player.play(DeviceFileSource(file.path));
          }
        }
        setState(() => _playing = true);
      }
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final fgColor = Colors.black87;
    final accentColor = AppTheme.secondaryOrange;

    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _loadingUrl
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      _playing ? LucideIcons.pause : LucideIcons.play,
                      color: Colors.white,
                      size: 24,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 20,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      trackHeight: 3,
                      thumbColor: accentColor,
                      activeTrackColor: accentColor,
                      inactiveTrackColor: Colors.grey.withOpacity(0.3),
                    ),
                    child: Slider(
                      value: _position.inSeconds.toDouble().clamp(
                        0,
                        _duration.inSeconds.toDouble(),
                      ),
                      max: _duration.inSeconds.toDouble() > 0
                          ? _duration.inSeconds.toDouble()
                          : 1.0,
                      onChanged: (v) =>
                          _player.seek(Duration(seconds: v.toInt())),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(_position),
                        style: TextStyle(
                          color: fgColor.withOpacity(0.8),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        _formatDuration(_duration),
                        style: TextStyle(
                          color: fgColor.withOpacity(0.8),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
