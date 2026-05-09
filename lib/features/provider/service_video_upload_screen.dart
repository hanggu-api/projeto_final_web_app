import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';

class ServiceVideoUploadScreen extends StatefulWidget {
  final String serviceId;
  final Uint8List videoBytes;
  final String filename;
  final String? completionCode;

  const ServiceVideoUploadScreen({
    super.key,
    required this.serviceId,
    required this.videoBytes,
    required this.filename,
    this.completionCode,
  });

  @override
  State<ServiceVideoUploadScreen> createState() =>
      _ServiceVideoUploadScreenState();
}

class _ServiceVideoUploadScreenState extends State<ServiceVideoUploadScreen> {
  final ApiService _api = ApiService();

  double _progress = 0;
  bool _isUploading = true;
  bool _isCompleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _uploadAndFinish();
  }

  Future<void> _uploadAndFinish() async {
    if (widget.videoBytes.isEmpty) {
      setState(() {
        _isUploading = false;
        _error = 'Vídeo vazio. Grave novamente antes de finalizar.';
      });
      return;
    }

    setState(() {
      _progress = 0;
      _isUploading = true;
      _isCompleting = false;
      _error = null;
    });

    try {
      final videoKey = await _uploadVideoWithRetry();
      if (!mounted) return;

      setState(() {
        _progress = 1;
        _isUploading = false;
        _isCompleting = true;
      });

      await _api.confirmServiceCompletion(
        widget.serviceId,
        code: (widget.completionCode ?? '').trim().isEmpty
            ? null
            : widget.completionCode!.trim(),
        proofVideo: videoKey,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _isCompleting = false;
        _error = 'Não foi possível enviar o vídeo: $e';
      });
    }
  }

  Future<String> _uploadVideoWithRetry() async {
    const maxAttempts = 3;
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await _api.uploadServiceVideo(
          widget.videoBytes,
          filename: widget.filename,
          onProgress: (progress) {
            if (!mounted) return;
            setState(() => _progress = progress.clamp(0, 1).toDouble());
          },
        );
      } catch (e) {
        lastError = e;
        if (attempt >= maxAttempts) break;
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }

    throw Exception('falha após $maxAttempts tentativas: $lastError');
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isUploading || _isCompleting;
    final percent = (_progress * 100).clamp(0, 100).toInt();

    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !busy) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aguarde o envio do vídeo terminar.')),
        );
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          automaticallyImplyLeading: !busy,
          title: const Text(
            'Enviando vídeo',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withOpacity(0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      LucideIcons.uploadCloud,
                      size: 44,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  _isCompleting
                      ? 'Finalizando serviço'
                      : _error != null
                      ? 'Envio interrompido'
                      : 'Enviando vídeo do serviço',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _isCompleting
                      ? 'O vídeo já subiu. Estamos registrando a finalização com segurança.'
                      : _error ??
                            'Mantenha esta tela aberta até terminar. Como o vídeo é grande, isso evita perder o envio antes de fechar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    height: 1.45,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 28),
                if (_error == null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: _isCompleting
                          ? null
                          : (_progress <= 0 ? null : _progress),
                      minHeight: 12,
                      color: AppTheme.primaryBlue,
                      backgroundColor: Colors.grey.shade200,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isCompleting ? 'Processando...' : '$percent% enviado',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.red.shade800,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _uploadAndFinish,
                    icon: const Icon(LucideIcons.refreshCw),
                    label: const Text('TENTAR ENVIAR NOVAMENTE'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (_error == null)
                  Text(
                    _isCompleting
                        ? 'Fechando automaticamente assim que o serviço for marcado como finalizado.'
                        : 'A tela será fechada automaticamente ao concluir.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w700,
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
