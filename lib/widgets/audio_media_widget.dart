import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/audio_recorder.dart';
import '../utils/file_bytes.dart';

class AudioMediaWidget extends StatefulWidget {
  final List<String> audioKeys;
  final void Function(PlatformFile) onAudioRecorded;
  final VoidCallback? onAudioRemoved;

  const AudioMediaWidget({
    super.key,
    required this.audioKeys,
    List<String>? initialAudioKeys,
    required this.onAudioRecorded,
    this.onAudioRemoved,
  });

  @override
  State<AudioMediaWidget> createState() => _AudioMediaWidgetState();
}

class _AudioMediaWidgetState extends State<AudioMediaWidget> {
  String? _selectedAudioPath;
  Uint8List? _audioBytes; // Store bytes for Web playback of picked files
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  bool _isRecording = false;
  Timer? _timer;
  int _recordDuration = 0;

  // Player state
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  late List<double> _barHeights;

  @override
  void initState() {
    super.initState();
    // Generate random heights for waveform
    final random = Random();
    _barHeights = List.generate(40, (_) => 10.0 + random.nextInt(20));

    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
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
    _timer?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _pickAudio() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: false,
        withData: true,
      );

      if (result != null) {
        final file = result.files.single;
        final path = file.path;
        final bytes = file.bytes;

        setState(() {
          _selectedAudioPath = path ?? file.name;
          _audioBytes = bytes;
          _position = Duration.zero;
          _isPlaying = false;
        });

        // Pre-load duration if possible
        if (!kIsWeb && path != null) {
          await _player.setSource(DeviceFileSource(path));
        } else if (kIsWeb && bytes != null) {
          // On Web with bytes, we might skip pre-loading source
          // or use Data URI if we really want duration immediately.
        }

        widget.onAudioRecorded(file);
      }
    } catch (e) {
      debugPrint('Erro ao selecionar áudio: $e');
    }
  }

  Future<void> _toggleRecording() async {
    try {
      if (_isRecording) {
        final path = await _recorder.stop();
        _timer?.cancel();
        setState(() {
          _isRecording = false;
        });

        if (path != null) {
          // Get bytes using cross-platform helper
          final bytes = await readFileBytes(path);

          setState(() {
            _selectedAudioPath = path;
            _audioBytes = bytes;
            _position = Duration.zero;
            _isPlaying = false;
          });

          if (kIsWeb) {
            await _player.setSource(UrlSource(path));
          } else {
            await _player.setSource(DeviceFileSource(path));
          }

          final platformFile = PlatformFile(
            name: kIsWeb ? 'recorded_audio.webm' : 'recorded_audio.m4a',
            size: bytes.length,
            bytes: bytes,
            path: path,
          );

          widget.onAudioRecorded(platformFile);
        }
      } else {
        String? path;
        if (!kIsWeb) {
          final dir = await getTemporaryDirectory();
          path =
              '${dir.path}/audio_record_${DateTime.now().millisecondsSinceEpoch}.m4a';
        }

        await _recorder.start(path: path);
        setState(() {
          _isRecording = true;
          _recordDuration = 0;
        });
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _recordDuration++;
          });
        });
      }
    } catch (e) {
      debugPrint('Error toggling recording: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro na gravação: $e')));
      }
      setState(() {
        _isRecording = false;
      });
      _timer?.cancel();
    }
  }

  Future<void> _togglePlay() async {
    if (_selectedAudioPath == null) return;

    try {
      if (_isPlaying) {
        await _player.pause();
        setState(() => _isPlaying = false);
      } else {
        if (_player.state == PlayerState.paused) {
          await _player.resume();
        } else {
          if (kIsWeb) {
            // Web Playback Logic
            if (_selectedAudioPath!.startsWith('blob:') ||
                _selectedAudioPath!.startsWith('http')) {
              await _player.play(UrlSource(_selectedAudioPath!));
            } else if (_audioBytes != null) {
              // Fallback for picked files on Web (path is just filename)
              final base64Audio = base64Encode(_audioBytes!);
              // Try to guess mime or default to mpeg/webm
              final mime = _selectedAudioPath!.endsWith('.webm')
                  ? 'audio/webm'
                  : 'audio/mpeg';
              final dataUri = 'data:$mime;base64,$base64Audio';
              await _player.play(UrlSource(dataUri));
            }
          } else {
            // Mobile Logic
            await _player.play(DeviceFileSource(_selectedAudioPath!));
          }
        }
        setState(() => _isPlaying = true);
      }
    } catch (e) {
      debugPrint('Error toggling play: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao reproduzir: $e')));
      }
      setState(() => _isPlaying = false);
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatPlayerDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  void _showOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(LucideIcons.mic),
                title: const Text('Gravar Áudio'),
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleRecording();
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.music),
                title: const Text('Escolher Arquivo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAudio();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlayer() {
    return Expanded(
      child: Row(
        children: [
          // Play/Pause Button
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                _isPlaying ? LucideIcons.pause : LucideIcons.play,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Waveform and Time
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 32,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      const barWidth = 3.0;
                      const barSpacing = 2.0;
                      final maxBars = (width / (barWidth + barSpacing)).floor();
                      final barsToShow = min(_barHeights.length, maxBars);

                      return GestureDetector(
                        onHorizontalDragUpdate: (details) {
                          final box = context.findRenderObject() as RenderBox;
                          final localPos = box.globalToLocal(
                            details.globalPosition,
                          );
                          final p = (localPos.dx / width).clamp(0.0, 1.0);
                          final sec = _duration.inSeconds.toDouble() * p;
                          _player.seek(Duration(seconds: sec.toInt()));
                        },
                        onTapUp: (details) {
                          final box = context.findRenderObject() as RenderBox;
                          final localPos = box.globalToLocal(
                            details.globalPosition,
                          );
                          final p = (localPos.dx / width).clamp(0.0, 1.0);
                          final sec = _duration.inSeconds.toDouble() * p;
                          _player.seek(Duration(seconds: sec.toInt()));
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: List.generate(barsToShow, (index) {
                            final p = index / barsToShow;
                            final currentP = _duration.inSeconds > 0
                                ? _position.inSeconds / _duration.inSeconds
                                : 0.0;
                            final isPlayed = p <= currentP;

                            return Container(
                              width: barWidth,
                              height: _barHeights[index],
                              decoration: BoxDecoration(
                                color: isPlayed
                                    ? Theme.of(context).colorScheme.secondary
                                    : Colors.grey[300],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            );
                          }),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatPlayerDuration(_position),
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _formatPlayerDuration(_duration),
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
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

  @override
  Widget build(BuildContext context) {
    if (_isRecording) {
      return Container(
        width: double.infinity,
        height: 140, // Increased height to prevent overflow
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Gravando...',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _formatDuration(_recordDuration),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            IconButton(
              onPressed: _toggleRecording,
              icon: const Icon(
                LucideIcons.stopCircle,
                color: Colors.red,
                size: 40,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _selectedAudioPath == null ? _showOptions : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _selectedAudioPath != null
                ? Row(
                    children: [
                      _buildPlayer(),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(LucideIcons.x, color: Colors.grey),
                        onPressed: () {
                          _player.stop();
                          setState(() {
                            _selectedAudioPath = null;
                            _isPlaying = false;
                            _position = Duration.zero;
                          });
                          widget.onAudioRemoved?.call();
                        },
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          LucideIcons.mic,
                          color: Colors.purple,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Adicionar Áudio',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Grave ou selecione um áudio',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
