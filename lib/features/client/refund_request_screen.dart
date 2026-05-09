import 'dart:io' show File;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/theme/app_theme.dart';
import '../../features/shared/in_app_camera_screen.dart';
import '../../services/api_service.dart';
import 'service_complaint_logic.dart';

class RefundRequestScreen extends StatefulWidget {
  final String serviceId;
  final String title;
  final String claimType;
  const RefundRequestScreen({
    super.key,
    required this.serviceId,
    required this.title,
    this.claimType = 'complaint',
  });

  @override
  State<RefundRequestScreen> createState() => _RefundRequestScreenState();
}

class RefundRequestForm extends StatefulWidget {
  final String serviceId;
  final String title;
  final String claimType;
  final VoidCallback? onSubmitted;
  final bool showAppBarHeader;

  const RefundRequestForm({
    super.key,
    required this.serviceId,
    required this.title,
    this.claimType = 'complaint',
    this.onSubmitted,
    this.showAppBarHeader = false,
  });

  @override
  State<RefundRequestForm> createState() => _RefundRequestFormState();
}

class _RefundRequestScreenState extends State<RefundRequestScreen> {
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
      body: RefundRequestForm(
        serviceId: widget.serviceId,
        title: widget.title,
        claimType: widget.claimType,
        onSubmitted: () => Navigator.pop(context, true),
      ),
    );
  }
}

class _RefundRequestFormState extends State<RefundRequestForm> {
  final _commentController = TextEditingController();
  final List<XFile> _attachments = [];
  final ImagePicker _picker = ImagePicker();
  final ApiService _api = ApiService();
  final Map<String, bool> _quickAnswers = {
    'O prestador não executou o serviço corretamente': false,
    'O serviço ficou incompleto ou mal finalizado': false,
    'Houve cobrança indevida ou valor divergente': false,
    'O prestador foi rude ou agiu de forma inadequada': false,
    'Preciso de reanálise do pagamento ou reembolso': false,
  };
  bool _isSubmitting = false;

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
      XFile? image;
      if (source == ImageSource.camera) {
        final dynamic result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const InAppCameraScreen(
              initialVideoMode: false,
            ),
          ),
        );
        if (result is XFile) {
          image = result;
        }
      } else {
        image = await _picker.pickImage(
          source: source,
          imageQuality: 80,
        );
      }

      if (image != null) {
        final pickedImage = image;
        setState(() {
          _attachments.add(pickedImage);
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

  Future<void> _pickVideo(ImageSource source) async {
    try {
      XFile? video;
      if (source == ImageSource.camera) {
        final dynamic result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const InAppCameraScreen(
              initialVideoMode: true,
              maxVideoDuration: Duration(minutes: 2),
            ),
          ),
        );
        if (result is XFile) {
          video = result;
        }
      } else {
        video = await _picker.pickVideo(
          source: source,
          maxDuration: const Duration(minutes: 2),
        );
      }

      if (video != null) {
        final pickedVideo = video;
        setState(() {
          _attachments.add(pickedVideo);
        });
      }
    } catch (e) {
      debugPrint('Error picking video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao selecionar vídeo')),
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
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Gravação de áudio ainda não está disponível no navegador. Use foto, galeria ou vídeo.',
          ),
        ),
      );
      return;
    }

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

    await showDialog(
      context: context,
      barrierDismissible: false,
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

  String get _resolvedClaimType {
    return ServiceComplaintLogic.resolveClaimType(
      claimType: widget.claimType,
      title: widget.title,
    );
  }

  String _attachmentTypeFromPath(String path) {
    return ServiceComplaintLogic.attachmentTypeFromPath(path);
  }

  Future<void> _submitRequest() async {
    if (_isSubmitting) return;
    final quickReasons = _quickAnswers.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
    final observation = _commentController.text.trim();

    if (quickReasons.isEmpty && observation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selecione ao menos uma resposta rápida ou escreva uma observação.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_attachments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anexe pelo menos uma foto, vídeo ou áudio.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final selectedAnswers = {
      for (final entry in _quickAnswers.entries)
        entry.key: quickReasons.contains(entry.key),
    };
    final reason = ServiceComplaintLogic.buildReason(
      quickAnswers: selectedAnswers,
      observation: observation,
    );

    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uploadedAttachments = <Map<String, String>>[];
      for (final attachment in _attachments) {
        final bytes = await attachment.readAsBytes();
        final filename = attachment.name.isNotEmpty
            ? attachment.name
            : 'anexo_${DateTime.now().millisecondsSinceEpoch}';
        final type = _attachmentTypeFromPath(attachment.path);
        final url = await _api.uploadToCloud(
          bytes,
          filename: filename,
          serviceId: widget.serviceId,
          type: 'contest',
        );
        uploadedAttachments.add({'type': type, 'url': url});
      }

      await _api.submitServiceComplaint(
        serviceId: widget.serviceId,
        claimType: _resolvedClaimType,
        reason: reason,
        attachments: uploadedAttachments,
      );

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _resolvedClaimType == 'refund_request'
                ? 'Pedido de devolução enviado para análise.'
                : 'Reclamação enviada para análise.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      widget.onSubmitted?.call();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Erro ao enviar solicitação: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showAppBarHeader) ...[
              Text(
                widget.title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
            ],
            const Text(
              'Abra sua reclamação',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.title == 'Pedir Devolução'
                  ? 'Envie os detalhes do problema e as evidências do serviço para análise da equipe.'
                  : 'Explique o ocorrido, anexe evidências do serviço e responda às perguntas rápidas abaixo.',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7D6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primaryYellow),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Como funciona a análise',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Os dados enviados serão analisados pela equipe da 101 Service. Você receberá a resposta em seu e-mail em até 3 dias úteis.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
            const Divider(height: 48),

            const Text(
              'Perguntas rápidas',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ..._quickAnswers.entries.map(
              (entry) => CheckboxListTile(
                value: entry.value,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppTheme.primaryYellow,
                title: Text(entry.key),
                onChanged: (value) {
                  setState(() {
                    _quickAnswers[entry.key] = value ?? false;
                  });
                },
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Observação',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText:
                    'Descreva o que aconteceu, o motivo da reclamação e qualquer detalhe importante para a análise.',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Media Selection
            const Text(
              'Anexar evidências do serviço:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                _buildMediaButton(
                  LucideIcons.camera,
                  'Foto',
                  () => _pickImage(ImageSource.camera),
                ),
                _buildMediaButton(
                  LucideIcons.image,
                  'Galeria',
                  () => _pickImage(ImageSource.gallery),
                ),
                _buildMediaButton(
                  LucideIcons.video,
                  'Vídeo',
                  () => _pickVideo(ImageSource.camera),
                ),
                if (!kIsWeb)
                  _buildMediaButton(
                    LucideIcons.mic,
                    'Áudio',
                    _showAudioRecorderDialog,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              kIsWeb
                  ? 'Envie fotos ou vídeo mostrando o problema. No navegador, o áudio ainda não está disponível.'
                  : 'Envie fotos, vídeo ou áudio mostrando o problema. Esses dados serão usados na análise.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
                    final lower = file.path.toLowerCase();
                    final isAudio =
                        lower.endsWith('.m4a') ||
                        lower.endsWith('.aac') ||
                        lower.endsWith('.mp3') ||
                        lower.endsWith('.wav');
                    final isVideo =
                        lower.endsWith('.mp4') ||
                        lower.endsWith('.mov') ||
                        lower.endsWith('.webm') ||
                        lower.endsWith('.avi');

                    return Stack(
                      children: [
                        _AttachmentPreview(
                          file: file,
                          isAudio: isAudio,
                          isVideo: isVideo,
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
                onPressed: _isSubmitting ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'ENVIAR SOLICITAÇÃO',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
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
    if (kIsWeb) {
      if (mounted) Navigator.pop(context);
      return;
    }

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
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 420,
          minHeight: 280,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Gravando Áudio',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.mic, color: Colors.red, size: 44),
            ),
            const SizedBox(height: 24),
            Text(
              _tempPath == null
                  ? 'Preparando gravador...'
                  : 'Fale claramente e toque no botão abaixo para finalizar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _tempPath == null ? null : _stop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'PARAR E SALVAR',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  final XFile file;
  final bool isAudio;
  final bool isVideo;

  const _AttachmentPreview({
    required this.file,
    required this.isAudio,
    required this.isVideo,
  });

  @override
  Widget build(BuildContext context) {
    if (isAudio) {
      return _previewShell(
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.mic, color: Colors.blue, size: 32),
              SizedBox(height: 4),
              Text('Áudio', style: TextStyle(fontSize: 10)),
            ],
          ),
        ),
      );
    }

    if (isVideo) {
      return _previewShell(
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.video, color: Colors.deepPurple, size: 32),
              SizedBox(height: 4),
              Text('Vídeo', style: TextStyle(fontSize: 10)),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return _previewShell(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                width: 100,
                height: 100,
                errorBuilder: (_, __, ___) => _previewFallback(),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return _previewShell(child: _previewFallback());
        }

        if (!kIsWeb) {
          return _previewShell(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(file.path),
                fit: BoxFit.cover,
                width: 100,
                height: 100,
                errorBuilder: (_, __, ___) => _previewFallback(),
              ),
            ),
          );
        }

        return _previewShell(
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }

  Widget _previewShell({required Widget child}) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[100],
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: child,
    );
  }

  Widget _previewFallback() {
    return const Center(
      child: Icon(
        Icons.insert_drive_file_outlined,
        size: 28,
        color: Colors.grey,
      ),
    );
  }
}
