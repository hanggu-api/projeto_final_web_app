import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../shared/in_app_camera_screen.dart';
import 'service_video_upload_screen.dart';

class FinishServiceScreen extends StatefulWidget {
  final String serviceId;

  const FinishServiceScreen({super.key, required this.serviceId});

  @override
  State<FinishServiceScreen> createState() => _FinishServiceScreenState();
}

class _FinishServiceScreenState extends State<FinishServiceScreen> {
  final _codeController = TextEditingController();
  final _api = ApiService();
  final ImagePicker _picker = ImagePicker();

  XFile? _video;
  Uint8List? _videoBytesInMemory;
  String? _videoFilenameInMemory;
  VideoPlayerController? _videoController;
  String? _error;
  bool? _isCodeValid;
  bool _validating = false;
  bool _submitting = false;
  double _uploadProgress = 0.0;
  static const Duration _maxEvidenceDuration = Duration(seconds: 45);
  static const int _maxVideoBytes = 20 * 1024 * 1024; // 20MB
  bool _requestedCompletionCode = false;

  // Código é opcional: só exige vídeo
  bool get _isFormValid => _video != null && !_submitting;

  @override
  void initState() {
    super.initState();
    _retrieveLostData();
    _ensureCompletionCodeRequested();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _retrieveLostData() async {
    final LostDataResponse response = await _picker.retrieveLostData();
    if (response.isEmpty) return;
    if (response.file != null && response.type == RetrieveType.video) {
      _setVideo(response.file!);
    } else {
      _handleError(response.exception);
    }
  }

  Future<void> _ensureCompletionCodeRequested() async {
    if (_requestedCompletionCode) return;
    _requestedCompletionCode = true;
    try {
      final details = await _api.getServiceDetails(widget.serviceId);
      final existingCode =
          (details['completion_code'] ?? details['verification_code'] ?? '')
              .toString()
              .trim();
      if (existingCode.isNotEmpty) return;
      await _api.requestServiceCompletion(widget.serviceId);
    } catch (_) {
      // best effort: fluxo continua mesmo sem gerar código.
    }
  }

  Future<void> _setVideo(XFile video) async {
    try {
      final bytes = await video.readAsBytes();
      final controller = kIsWeb
          ? VideoPlayerController.networkUrl(Uri.parse(video.path))
          : VideoPlayerController.file(File(video.path));
      await controller.initialize();
      if (controller.value.duration > _maxEvidenceDuration) {
        await controller.dispose();
        setState(() {
          _error =
              'Vídeo muito longo. Grave no máximo ${_maxEvidenceDuration.inSeconds}s.';
        });
        return;
      }

      if (bytes.length > _maxVideoBytes) {
        await controller.dispose();
        setState(() {
          _error = 'Vídeo muito pesado. Limite: 20MB.';
        });
        return;
      }
      setState(() {
        _video = video;
        _videoBytesInMemory = bytes;
        _videoFilenameInMemory = video.name;
        _videoController = controller;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Erro ao carregar vídeo: $e');
    }
  }

  void _handleError(PlatformException? exception) {
    setState(() {
      _error = exception?.message ?? 'Erro desconhecido ao recuperar dados';
    });
  }

  Future<void> _verifyCode(String code) async {
    if (code.length != 6) {
      if (_isCodeValid != null) setState(() => _isCodeValid = null);
      return;
    }

    setState(() {
      _validating = true;
      _isCodeValid = null;
    });

    try {
      final isValid = await _api.verifyServiceCode(widget.serviceId, code);

      if (mounted) {
        setState(() {
          _isCodeValid = isValid;
          _validating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _validating = false;
          _isCodeValid = false;
          _error = 'Erro ao validar código';
        });
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      XFile? video;
      if (kIsWeb) {
        try {
          video = await _picker.pickVideo(source: ImageSource.camera);
        } catch (_) {
          video = await _picker.pickVideo(source: ImageSource.gallery);
        }
      } else {
        video = await Navigator.push<XFile>(
          context,
          MaterialPageRoute(
            builder: (context) => const InAppCameraScreen(
              initialVideoMode: true,
              maxVideoDuration: _maxEvidenceDuration,
              videoResolutionPreset: ResolutionPreset.medium,
            ),
          ),
        );
      }
      if (video != null) await _setVideo(video);
    } catch (e) {
      setState(() => _error = 'Erro ao abrir câmera: $e');
    }
  }

  Future<void> _removeVideo() async {
    await _videoController?.dispose();
    if (!mounted) return;
    setState(() {
      _video = null;
      _videoBytesInMemory = null;
      _videoFilenameInMemory = null;
      _videoController = null;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!_isFormValid) return;
    setState(() {
      _submitting = true;
      _error = null;
      _uploadProgress = 0;
    });
    try {
      final videoBytes = _videoBytesInMemory;
      if (videoBytes == null || videoBytes.isEmpty) {
        setState(() {
          _error = 'Envie um vídeo do serviço para finalizar.';
          _submitting = false;
        });
        return;
      }

      final enteredCode = _codeController.text.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preparando envio do vídeo...')),
      );
      final uploaded = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ServiceVideoUploadScreen(
            serviceId: widget.serviceId,
            videoBytes: videoBytes,
            filename:
                _videoFilenameInMemory ?? _video?.name ?? 'evidence_video.mp4',
            completionCode: enteredCode.isEmpty ? null : enteredCode,
          ),
        ),
      );

      if (!mounted) return;
      if (uploaded == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Serviço finalizado. Voltando para a home.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/provider-home');
        return;
      } else {
        setState(() => _submitting = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Erro ao concluir serviço: $e';
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Finalizar Atendimento'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 760;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 24,
              compact ? 12 : 24,
              compact ? 16 : 24,
              (compact ? 16 : 24) + media.viewPadding.bottom,
            ),
            child: Column(
              children: [
                _buildMissionHeader(compact: compact),
                SizedBox(height: compact ? 18 : 32),
                _buildCodeSection(compact: compact),
                SizedBox(height: compact ? 18 : 32),
                _buildVideoSection(compact: compact),
                if (_error != null) ...[
                  SizedBox(height: compact ? 12 : 24),
                  _buildErrorBadge(),
                ],
                SizedBox(height: compact ? 18 : 48),
                _buildSubmitButton(compact: compact),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMissionHeader({bool compact = false}) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(compact ? 14 : 20),
          decoration: BoxDecoration(
            color: AppTheme.primaryPurple.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            LucideIcons.rocket,
            color: AppTheme.primaryPurple,
            size: compact ? 24 : 32,
          ),
        ),
        SizedBox(height: compact ? 10 : 16),
        Text(
          'Quase lá!',
          style: TextStyle(
            fontSize: compact ? 20 : 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const Text(
          'Envie as evidências para finalizar o atendimento.',
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildCodeSection({bool compact = false}) {
    Color? borderColor;
    String? helperText = 'Opcional: informe se o cliente possuir o código.';
    Widget? suffix;

    if (_validating) {
      suffix = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (_isCodeValid == true) {
      borderColor = Colors.green;
      helperText = 'Código validado com sucesso!';
      suffix = const Icon(Icons.check_circle, color: Colors.green);
    } else if (_isCodeValid == false) {
      borderColor = Colors.orange;
      helperText = 'Código incorreto (pode finalizar sem ele).';
      suffix = const Icon(Icons.warning_amber_rounded, color: Colors.orange);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'CÓDIGO DE VALIDAÇÃO',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: Colors.grey,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'OPCIONAL',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 8 : 12),
        TextField(
          controller: _codeController,
          maxLength: 6,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
          ),
          decoration:
              AppTheme.inputDecoration(
                'Código de 6 dígitos',
                LucideIcons.lock,
              ).copyWith(
                hintText: '000000',
                counterText: '',
                helperText: helperText,
                helperStyle: TextStyle(color: borderColor ?? Colors.grey),
                suffixIcon: suffix != null
                    ? Padding(padding: const EdgeInsets.all(12), child: suffix)
                    : null,
                enabledBorder: borderColor != null
                    ? OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: borderColor, width: 2),
                      )
                    : null,
                focusedBorder: borderColor != null
                    ? OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: borderColor, width: 2),
                      )
                    : null,
              ),
          onChanged: (v) {
            if (v.length == 6) {
              _verifyCode(v);
            } else {
              if (_isCodeValid != null) setState(() => _isCodeValid = null);
            }
          },
        ),
        SizedBox(height: compact ? 4 : 8),
        Text(
          'Você pode finalizar o serviço sem o código.',
          style: TextStyle(fontSize: compact ? 11 : 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildVideoSection({bool compact = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PROVA MATERIAL (VÍDEO)',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Colors.grey,
          ),
        ),
        SizedBox(height: compact ? 8 : 12),
        if (_video != null && _videoController != null)
          _buildVideoPlayer(compact: compact)
        else
          _buildEmptyVideoState(compact: compact),
      ],
    );
  }

  Widget _buildVideoPlayer({bool compact = false}) {
    final previewHeight = compact ? 220.0 : 300.0;
    return Column(
      children: [
        SizedBox(
          height: previewHeight,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _videoController!.value.size.width,
                      height: _videoController!.value.size.height,
                      child: VideoPlayer(_videoController!),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Material(
                    color: Colors.black26,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _videoController!.value.isPlaying
                              ? _videoController!.pause()
                              : _videoController!.play();
                        });
                      },
                      child: Center(
                        child: Icon(
                          _videoController!.value.isPlaying
                              ? LucideIcons.pause
                              : LucideIcons.play,
                          size: compact ? 52 : 64,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: compact ? 10 : 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Gravar outro vídeo'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryPurple,
              ),
            ),
            TextButton.icon(
              onPressed: _submitting ? null : _removeVideo,
              icon: const Icon(LucideIcons.trash2, size: 16),
              label: const Text('Remover vídeo'),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyVideoState({bool compact = false}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: _pickVideo,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          height: compact ? 132 : 160,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[200]!),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPhoneVideoIcon(size: compact ? 42 : 48),
              const SizedBox(height: 12),
              const Text(
                'Toque para gravar o vídeo',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
              const Text(
                'Máximo de 2 minutos',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneVideoIcon({double size = 48}) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 0.62,
            height: size,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(size * 0.16),
              border: Border.all(
                color: AppTheme.primaryBlue.withOpacity(0.85),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.phone_android_rounded,
              size: size * 0.64,
              color: AppTheme.primaryBlue,
            ),
          ),
          Positioned(
            right: -3,
            bottom: 1,
            child: Container(
              width: size * 0.5,
              height: size * 0.5,
              decoration: BoxDecoration(
                color: AppTheme.primaryYellow,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(
                Icons.videocam_rounded,
                size: size * 0.31,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBadge() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.alertCircle, color: Colors.red, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton({bool compact = false}) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: _isFormValid
            ? [
                BoxShadow(
                  color: AppTheme.primaryBlue.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: ElevatedButton(
        onPressed: _isFormValid ? _submit : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: Size(double.infinity, compact ? 54 : 60),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _submitting
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      value: _uploadProgress > 0 ? _uploadProgress : null,
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    _uploadProgress > 0
                        ? 'ENVIANDO: ${(_uploadProgress * 100).toInt()}%'
                        : 'PROCESSANDO...',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              )
            : const Text(
                'FINALIZAR SERVIÇO',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
      ),
    );
  }
}
