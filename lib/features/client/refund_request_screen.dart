import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/theme/app_theme.dart';

class RefundRequestScreen extends StatefulWidget {
  final String serviceId;
  final String title;
  const RefundRequestScreen({
    super.key,
    required this.serviceId,
    required this.title,
  });

  @override
  State<RefundRequestScreen> createState() => _RefundRequestScreenState();
}

class _RefundRequestScreenState extends State<RefundRequestScreen> {
  final _commentController = TextEditingController();
  final List<XFile> _attachments = [];
  final ImagePicker _picker = ImagePicker();

  // Audio
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _recordedAudioPath;

  @override
  void dispose() {
    _commentController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );
      if (image != null) {
        setState(() {
          _attachments.add(image);
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao selecionar imagem')),
        );
      }
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      final item = _attachments[index];
      // If it's the audio file, clear reference too
      if (item.path == _recordedAudioPath) {
        _recordedAudioPath = null;
      }
      _attachments.removeAt(index);
    });
  }

  Future<void> _showAudioRecorderDialog() async {
    if (_recordedAudioPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Você já gravou um áudio. Remova o anterior para gravar novo.',
          ),
        ),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AudioRecorderSheet(
        recorder: _audioRecorder,
        onCustomRecordingComplete: (path) {
          setState(() {
            _recordedAudioPath = path;
            _attachments.add(XFile(path));
          });
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Áudio anexado com sucesso!')),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: AppTheme.primaryYellow,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Relate o problema',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.title == 'Pedir Devolução'
                  ? 'Para solicitar a devolução do dinheiro, precisamos que você forneça detalhes e evidências do que aconteceu.'
                  : 'Para abrir uma reclamação, descreva o ocorrido e anexe evidências para análise de nossa equipe.',
              style: const TextStyle(color: Colors.grey),
            ),
            const Divider(height: 48),

            // Text Field
            Text(
              widget.title == 'Pedir Devolução'
                  ? 'Descrição da devolução:'
                  : 'Descrição da reclamação:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'Descreva detalhadamente o motivo...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Media Selection
            const Text(
              'Anexar evidências:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMediaButton(
                  LucideIcons.camera,
                  'Câmera',
                  () => _pickImage(ImageSource.camera),
                ),
                _buildMediaButton(
                  LucideIcons.image,
                  'Galeria',
                  () => _pickImage(ImageSource.gallery),
                ),
                _buildMediaButton(
                  LucideIcons.mic,
                  'Áudio',
                  _showAudioRecorderDialog,
                ),
              ],
            ),

            if (_attachments.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text(
                'Anexos selecionados:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachments.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final file = _attachments[index];
                    final isAudio =
                        file.path.endsWith('.m4a') ||
                        file.path.endsWith('.aac'); // Simple check

                    return Stack(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey[100],
                            border: Border.all(color: Colors.grey[300]!),
                            image: !isAudio
                                ? DecorationImage(
                                    image: FileImage(File(file.path)),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: isAudio
                              ? const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        LucideIcons.mic,
                                        color: Colors.blue,
                                        size: 32,
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Áudio',
                                        style: TextStyle(fontSize: 10),
                                      ),
                                    ],
                                  ),
                                )
                              : null,
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeAttachment(index),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 48),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  if (_commentController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Por favor, descreva o motivo da solicitação.',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  // Logic for submission would go here (Upload attachments, call API)
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Solicitação enviada! (${_attachments.length} anexos)',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'ENVIAR SOLICITAÇÃO',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Icon(icon, color: AppTheme.primaryPurple, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _AudioRecorderSheet extends StatefulWidget {
  final AudioRecorder recorder;
  final Function(String path) onCustomRecordingComplete;

  const _AudioRecorderSheet({
    required this.recorder,
    required this.onCustomRecordingComplete,
  });

  @override
  State<_AudioRecorderSheet> createState() => _AudioRecorderSheetState();
}

class _AudioRecorderSheetState extends State<_AudioRecorderSheet> {
  String? _tempPath;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (await widget.recorder.hasPermission()) {
      final dir = await getTemporaryDirectory();
      _tempPath =
          '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await widget.recorder.start(const RecordConfig(), path: _tempPath!);
      setState(() {});
    } else {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _stop() async {
    final path = await widget.recorder.stop();
    setState(() {});
    if (path != null) {
      widget.onCustomRecordingComplete(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Text(
            'Gravando Áudio',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.mic, color: Colors.red, size: 40),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _stop,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: const Text('PARAR E SALVAR'),
          ),
        ],
      ),
    );
  }
}
