import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';

import '../../core/constants/trip_statuses.dart';
import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/data_gateway.dart';
import '../../widgets/app_dialog_actions.dart';
import '../shared/in_app_camera_screen.dart';
import 'service_video_upload_screen.dart';
import 'widgets/provider_service_card.dart';

class ProviderActiveServiceMobileScreen extends StatefulWidget {
  final String serviceId;

  const ProviderActiveServiceMobileScreen({super.key, required this.serviceId});

  @override
  State<ProviderActiveServiceMobileScreen> createState() =>
      _ProviderActiveServiceMobileScreenState();
}

class _ProviderActiveServiceMobileScreenState
    extends State<ProviderActiveServiceMobileScreen> {
  final ApiService _api = ApiService();
  final ImagePicker _picker = ImagePicker();
  Timer? _refreshTimer;
  Map<String, dynamic>? _service;
  bool _loading = true;
  bool _showInlineFinish = false;
  bool _submittingFinish = false;
  String? _inlineError;
  XFile? _inlineVideo;

  String? _serviceParticipantContextLabel(Map<String, dynamic>? service) {
    if (service == null) return null;
    final participants = DataGateway().extractChatParticipants(service);
    final beneficiary = participants.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['role'] == 'beneficiary',
      orElse: () => null,
    );
    final requester = participants.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['role'] == 'requester',
      orElse: () => null,
    );
    if (beneficiary == null) return null;
    final beneficiaryName = '${beneficiary['display_name'] ?? ''}'.trim();
    if (beneficiaryName.isEmpty) return null;
    final beneficiaryId = '${beneficiary['user_id'] ?? ''}'.trim();
    final requesterId = '${requester?['user_id'] ?? ''}'.trim();
    if (beneficiaryId.isNotEmpty && beneficiaryId == requesterId) return null;
    return 'Atendimento para $beneficiaryName';
  }
  Uint8List? _inlineVideoBytes;
  VideoPlayerController? _inlineVideoController;
  final TextEditingController _codeController = TextEditingController();
  bool _validatingCode = false;
  bool? _isCodeValid;
  bool _requestedCompletionCode = false;
  bool _serviceMissingHandled = false;
  bool _allowNoCodeFallback = false;

  bool _isConcludingStatus(String status) {
    final normalized = normalizeServiceStatus(status);
    return ServiceStatusSets.providerConcluding.contains(normalized);
  }

  @override
  void initState() {
    super.initState();
    _loadService();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadService(showLoading: false);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _inlineVideoController?.dispose();
    _codeController.dispose();
    super.dispose();
  }

  bool _isMissingService(Map<String, dynamic>? service) {
    if (service == null) return true;
    if (service['not_found'] == true) return true;
    final status = (service['status'] ?? '').toString().toLowerCase().trim();
    return status == 'deleted' || status == 'not_found';
  }

  void _handleMissingService() {
    if (!mounted || _serviceMissingHandled) return;
    _serviceMissingHandled = true;
    _refreshTimer?.cancel();
    setState(() {
      _service = null;
      _loading = false;
    });

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Este serviço não existe mais. Voltando para a home.'),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go('/provider-home');
    });
  }

  Future<void> _loadService({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() => _loading = true);
    }
    try {
      final details = await _api.getServiceDetails(widget.serviceId);
      if (_isMissingService(details)) {
        _handleMissingService();
        return;
      }
      final status = (details['status'] ?? '').toString().toLowerCase().trim();
      if (_isConcludingStatus(status)) {
        final autoConfirmed = await _api.autoConfirmServiceAfterGraceIfEligible(
          widget.serviceId,
          graceMinutes: 720,
        );
        if (autoConfirmed) {
          final latest = await _api.getServiceDetails(widget.serviceId);
          if (_isMissingService(latest)) {
            _handleMissingService();
            return;
          }
          final latestStatus = (latest['status'] ?? '')
              .toString()
              .toLowerCase()
              .trim();
          final showFinishPanel = _isConcludingStatus(latestStatus);
          if (showFinishPanel) {
            await _ensureCompletionCodeRequested();
          }
          if (!mounted) return;
          setState(() {
            _service = latest;
            _loading = false;
            if (showFinishPanel) {
              _showInlineFinish = true;
            }
          });
          return;
        }
      }
      final showFinishPanel = _isConcludingStatus(status);
      if (showFinishPanel) {
        await _ensureCompletionCodeRequested();
      }
      if (!mounted) return;
      setState(() {
        _service = details;
        _loading = false;
        if (showFinishPanel) {
          _showInlineFinish = true;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _service = null;
        _loading = false;
      });
    }
  }

  Future<void> _arrive() async {
    await _api.arriveService(
      widget.serviceId,
      scope: ServiceDataScope.mobileOnly,
    );
    await _loadService(showLoading: false);
  }

  Future<void> _start() async {
    await _api.startService(widget.serviceId);
    await _loadService(showLoading: false);
  }

  Future<void> _proposeSchedule(
    DateTime scheduledAt, {
    String message = '',
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _api.proposeSchedule(
        widget.serviceId,
        scheduledAt,
        scope: ServiceDataScope.mobileOnly,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Proposta enviada para o cliente!')),
      );
      await _loadService(showLoading: false);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Erro ao enviar: $e')));
    }
  }

  Future<void> _confirmSchedule() async {
    final service = _service;
    final rawScheduledAt = service?['scheduled_at']?.toString().trim() ?? '';
    if (rawScheduledAt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Horário proposto não encontrado.')),
      );
      return;
    }

    try {
      final scheduledAt = DateTime.parse(rawScheduledAt);
      await _api.confirmSchedule(
        widget.serviceId,
        scheduledAt,
        scope: ServiceDataScope.mobileOnly,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agendamento confirmado!')),
      );
      await _loadService(showLoading: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Erro ao confirmar: $e')));
    }
  }

  Future<void> _finish() async {
    if (!mounted) return;
    setState(() {
      _showInlineFinish = true;
      _inlineError = null;
      _allowNoCodeFallback = false;
    });
    await _ensureCompletionCodeRequested();
    await _loadService(showLoading: false);
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
      if (existingCode.isEmpty) {
        await _api.requestServiceCompletion(widget.serviceId);
      }
    } catch (_) {
      // best effort
    }
  }

  Future<void> _verifyInlineCode(String code) async {
    final normalized = code.trim();
    if (normalized.length != 6) {
      if (mounted) {
        setState(() => _isCodeValid = null);
      }
      return;
    }
    if (_validatingCode) return;
    setState(() {
      _validatingCode = true;
      _isCodeValid = null;
    });
    try {
      final ok = await _api.verifyServiceCode(widget.serviceId, normalized);
      if (!mounted) return;
      setState(() => _isCodeValid = ok);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCodeValid = false);
    } finally {
      if (mounted) {
        setState(() => _validatingCode = false);
      }
    }
  }

  Future<bool> _confirmFinishDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar finalização'),
        content: const Text(
          'Confirma finalizar o serviço agora? O crédito será liberado na sua carteira.',
        ),
        actions: [
          AppDialogCancelAction(onPressed: () => Navigator.pop(context, false)),
          AppDialogPrimaryAction(
            label: 'Finalizar',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _pickInlineVideo() async {
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
              maxVideoDuration: Duration(seconds: 45),
              videoResolutionPreset: ResolutionPreset.medium,
            ),
          ),
        );
      }
      if (video == null) return;

      final bytes = await video.readAsBytes();
      final controller = kIsWeb
          ? VideoPlayerController.networkUrl(Uri.parse(video.path))
          : VideoPlayerController.file(File(video.path));
      await controller.initialize();

      await _inlineVideoController?.dispose();
      if (!mounted) return;
      setState(() {
        _inlineVideo = video;
        _inlineVideoBytes = bytes;
        _inlineVideoController = controller;
        _inlineError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _inlineError = 'Erro ao gravar vídeo: $e');
    }
  }

  Future<void> _removeInlineVideo() async {
    await _inlineVideoController?.dispose();
    if (!mounted) return;
    setState(() {
      _inlineVideo = null;
      _inlineVideoBytes = null;
      _inlineVideoController = null;
      _inlineError = null;
    });
  }

  Future<void> _submitInlineFinish() async {
    if (_submittingFinish) return;
    if (_inlineVideoBytes == null || _inlineVideoBytes!.isEmpty) {
      setState(
        () => _inlineError = 'Envie um vídeo do serviço para finalizar.',
      );
      return;
    }
    final enteredCode = _codeController.text.trim();
    if (enteredCode.isEmpty && !_allowNoCodeFallback) {
      setState(
        () => _inlineError =
            'Digite o código do cliente para concluir agora ou use a contingência sem código.',
      );
      return;
    }
    if (enteredCode.isNotEmpty && enteredCode.length != 6) {
      setState(
        () => _inlineError =
            'Digite os 6 dígitos do código ou deixe o campo em branco.',
      );
      return;
    }
    if (enteredCode.isNotEmpty && _isCodeValid != true) {
      await _verifyInlineCode(enteredCode);
      if (_isCodeValid != true) {
        setState(
          () => _inlineError = 'Código inválido. Confira e tente novamente.',
        );
        return;
      }
    }
    final confirmed = await _confirmFinishDialog();
    if (!confirmed) return;

    setState(() {
      _submittingFinish = true;
      _inlineError = null;
    });
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preparando envio do vídeo...')),
      );
      final uploaded = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ServiceVideoUploadScreen(
            serviceId: widget.serviceId,
            videoBytes: _inlineVideoBytes!,
            filename: _inlineVideo?.name ?? 'service_evidence.mp4',
            completionCode: enteredCode.isEmpty ? null : enteredCode,
          ),
        ),
      );
      if (uploaded != true) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Serviço finalizado. Voltando para a home.'),
          backgroundColor: Colors.green,
        ),
      );
      context.go('/provider-home');
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _inlineError = 'Erro ao finalizar: $e');
    } finally {
      if (mounted) {
        setState(() => _submittingFinish = false);
      }
    }
  }

  Widget _buildInlineFinishPanel() {
    final hasVideo =
        _inlineVideo != null &&
        _inlineVideoController != null &&
        _inlineVideoController!.value.isInitialized;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildPhoneVideoIcon(size: 32),
              const SizedBox(width: 10),
              const Text(
                'Envie um vídeo do serviço',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickInlineVideo,
            icon: _buildPhoneVideoIcon(size: 26, compact: true),
            label: Text(hasVideo ? 'FILMAR NOVAMENTE' : 'FILMAR O SERVIÇO'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryBlue,
              side: BorderSide(color: AppTheme.primaryBlue.withOpacity(0.65)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
            ),
          ),
          if (hasVideo) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _submittingFinish ? null : _removeInlineVideo,
              icon: const Icon(LucideIcons.trash2, size: 16),
              label: const Text('REMOVER VÍDEO'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.withOpacity(0.22)),
            ),
            child: const Text(
              'Use o fluxo principal com vídeo + código do cliente para concluir o serviço imediatamente.\nSem código, a finalização entra em contingência e aguarda manifestação do cliente por até 12h.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              labelText: 'Código de segurança (opcional)',
              counterText: '',
              border: const OutlineInputBorder(),
              suffixIcon: _validatingCode
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_isCodeValid == true
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : (_isCodeValid == false
                              ? const Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                )
                              : null)),
            ),
            onChanged: (value) {
              if (_allowNoCodeFallback && value.trim().isNotEmpty) {
                setState(() => _allowNoCodeFallback = false);
              }
              if (value.length == 6) {
                _verifyInlineCode(value);
              } else if (_isCodeValid != null) {
                setState(() => _isCodeValid = null);
              }
            },
          ),
          const SizedBox(height: 8),
          if (!_allowNoCodeFallback)
            TextButton.icon(
              onPressed: _submittingFinish
                  ? null
                  : () {
                      setState(() {
                        _allowNoCodeFallback = true;
                        _inlineError = null;
                      });
                    },
              icon: const Icon(LucideIcons.alertTriangle, size: 16),
              label: const Text('USAR CONTINGÊNCIA SEM CÓDIGO'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.orange.shade800,
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.35)),
              ),
              child: const Text(
                'Contingência sem código ativada. O serviço irá para confirmação manual do cliente após o envio do vídeo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          if (hasVideo) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _inlineVideoController!.value.size.width,
                        height: _inlineVideoController!.value.size.height,
                        child: VideoPlayer(_inlineVideoController!),
                      ),
                    ),
                    Material(
                      color: Colors.black26,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _inlineVideoController!.value.isPlaying
                                ? _inlineVideoController!.pause()
                                : _inlineVideoController!.play();
                          });
                        },
                        child: Center(
                          child: Icon(
                            _inlineVideoController!.value.isPlaying
                                ? LucideIcons.pause
                                : LucideIcons.play,
                            size: 44,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_inlineError != null) ...[
            const SizedBox(height: 10),
            Text(
              _inlineError!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: (_inlineVideoBytes != null && !_submittingFinish)
                ? _submitInlineFinish
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 4,
              shadowColor: AppTheme.primaryBlue.withOpacity(0.28),
            ),
            child: _submittingFinish
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Text('FINALIZAR SERVIÇO'),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneVideoIcon({double size = 32, bool compact = false}) {
    final phoneWidth = size * 0.62;
    final phoneHeight = size;
    final cameraSize = compact ? size * 0.48 : size * 0.5;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: phoneWidth,
            height: phoneHeight,
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(compact ? 0.08 : 0.1),
              borderRadius: BorderRadius.circular(size * 0.16),
              border: Border.all(
                color: AppTheme.primaryBlue.withOpacity(0.85),
                width: compact ? 1.5 : 2,
              ),
            ),
            child: Icon(
              Icons.phone_android_rounded,
              size: size * 0.64,
              color: AppTheme.primaryBlue,
            ),
          ),
          Positioned(
            right: compact ? -2 : -3,
            bottom: compact ? 0 : 1,
            child: Container(
              width: cameraSize,
              height: cameraSize,
              decoration: BoxDecoration(
                color: AppTheme.primaryYellow,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(
                Icons.videocam_rounded,
                size: cameraSize * 0.62,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isDoneStatus(String status) {
    return status == 'completed' ||
        status == 'finished' ||
        status == 'cancelled' ||
        status == 'canceled';
  }

  void _openChat() {
    final service = _service;
    if (service == null) return;

    final client = service['client'];
    final otherName =
        (service['client_name'] ??
                (client is Map ? client['name'] : null) ??
                'Cliente')
            .toString();
    final otherAvatar =
        (service['client_avatar'] ??
                (client is Map ? (client['avatar'] ?? client['photo']) : null))
            ?.toString();

    context.push(
      '/chat/${widget.serviceId}',
      extra: {
        'serviceId': widget.serviceId,
        'otherName': otherName,
        'otherAvatar': otherAvatar,
      },
    );
  }

  int _stepForStatus(Map<String, dynamic>? service) {
    final status = (service?['status'] ?? '').toString().toLowerCase().trim();
    final remaining = (service?['payment_remaining_status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    final remainingPaid =
        remaining == 'paid' ||
        remaining == 'paid_manual' ||
        remaining == 'approved';

    if (['accepted', 'provider_near'].contains(status)) return 1;
    if ([
      'waiting_payment_remaining',
      'waiting_remaining_payment',
    ].contains(status)) {
      return remainingPaid ? 2 : 1;
    }
    if (status == 'in_progress') return 2;
    if ([
      'awaiting_confirmation',
      'waiting_client_confirmation',
      'completion_requested',
    ].contains(status)) {
      return 3;
    }
    if (_isDoneStatus(status)) return 3;
    return 0;
  }

  Widget _buildStepper(Map<String, dynamic>? service) {
    final step = _stepForStatus(service);
    final status = (service?['status'] ?? '').toString().toLowerCase().trim();
    final isPaymentPhase = [
      'waiting_payment_remaining',
      'waiting_remaining_payment',
    ].contains(status);
    final isConcludingPhase = [
      'awaiting_confirmation',
      'waiting_client_confirmation',
      'completion_requested',
    ].contains(status);

    Widget dot(
      IconData icon,
      String label,
      int index, {
      bool orange = false,
      bool forceBlue = false,
    }) {
      final active = step == index;
      final done = step > index;
      final useBlue = forceBlue || active;
      return Expanded(
        child: Column(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: orange
                    ? Colors.orange
                    : (done
                          ? AppTheme.primaryYellow
                          : (useBlue
                                ? AppTheme.primaryBlue
                                : Colors.grey.shade200)),
              ),
              child: Icon(
                icon,
                size: 16,
                color: orange
                    ? Colors.white
                    : (done
                          ? Colors.black
                          : (useBlue ? Colors.white : Colors.grey.shade600)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: orange
                    ? Colors.orange.shade700
                    : (forceBlue ? AppTheme.primaryBlue : Colors.black54),
              ),
            ),
          ],
        ),
      );
    }

    Widget line(bool active) => Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 22),
        color: active ? AppTheme.primaryYellow : Colors.grey.shade300,
      ),
    );

    return Row(
      children: [
        dot(Icons.credit_card, 'Reserva', 0),
        line(step >= 1),
        dot(
          isPaymentPhase ? Icons.shield : Icons.navigation,
          isPaymentPhase ? 'Pagamento' : 'Chegada',
          1,
          orange: isPaymentPhase,
        ),
        line(step >= 2),
        dot(Icons.build, 'Execução', 2),
        line(step >= 3),
        dot(
          Icons.check_circle_outline,
          isConcludingPhase ? 'Concluindo' : 'Conclusão',
          3,
          forceBlue: isConcludingPhase,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    final participantContextLabel = _serviceParticipantContextLabel(service);
    final status = service?['status']?.toString().toLowerCase() ?? '';
    final canOpenChat =
        service != null &&
        status.isNotEmpty &&
        !_isDoneStatus(status) &&
        status != 'pending';

    if (_isDoneStatus(status)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/provider-home');
      });
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: _loading && service == null
            ? const Center(child: CircularProgressIndicator())
            : service == null
            ? const Center(child: Text('Não foi possível carregar o serviço.'))
            : SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 24,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Status do Serviço',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (canOpenChat)
                                  IconButton(
                                    onPressed: _openChat,
                                    tooltip: 'Abrir chat com o cliente',
                                    icon: const Icon(LucideIcons.messageCircle),
                                  ),
                                const Text(
                                  '101SERVICE',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                              ],
                            ),
                            if (participantContextLabel != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    participantContextLabel,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.primaryBlue,
                                    ),
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                              child: _buildStepper(service),
                            ),
                            ProviderServiceCard(
                              service: service,
                              isFocusMode: true,
                              onArrive: _arrive,
                              onStart: _start,
                              onFinish: _finish,
                              onSchedule: (scheduledAt, message) =>
                                  _proposeSchedule(
                                    scheduledAt,
                                    message: message,
                                  ),
                              onConfirmSchedule: _confirmSchedule,
                            ),
                            if (_showInlineFinish) _buildInlineFinishPanel(),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
