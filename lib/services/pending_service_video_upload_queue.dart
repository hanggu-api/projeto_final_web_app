import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'api_service.dart';

class PendingServiceVideoUploadQueue {
  PendingServiceVideoUploadQueue._();

  static final PendingServiceVideoUploadQueue instance =
      PendingServiceVideoUploadQueue._();

  static const String _prefsKey = 'pending_service_video_uploads_v1';
  static bool _processing = false;

  Future<String?> enqueue({
    required String serviceId,
    required Uint8List videoBytes,
    required String filename,
    String? completionCode,
  }) async {
    if (kIsWeb || videoBytes.isEmpty || serviceId.trim().isEmpty) return null;

    final id = const Uuid().v4();
    final dir = await _queueDirectory();
    final safeName = filename.trim().isEmpty
        ? 'service_evidence.mp4'
        : filename;
    final ext = safeName.contains('.') ? safeName.split('.').last : 'mp4';
    final file = File('${dir.path}/$serviceId-$id.$ext');
    await file.writeAsBytes(videoBytes, flush: true);

    final item = _PendingServiceVideoUpload(
      id: id,
      serviceId: serviceId.trim(),
      filePath: file.path,
      filename: safeName,
      completionCode: completionCode?.trim(),
      createdAt: DateTime.now().toUtc(),
      attempts: 0,
      lastError: null,
    );

    final items = await _load();
    items.removeWhere((entry) => entry.id == id);
    items.add(item);
    await _save(items);
    return id;
  }

  Future<void> remove(String? id) async {
    final normalizedId = id?.trim();
    if (normalizedId == null || normalizedId.isEmpty) return;
    final items = await _load();
    final removed = items.where((item) => item.id == normalizedId).toList();
    items.removeWhere((item) => item.id == normalizedId);
    await _save(items);
    for (final item in removed) {
      await _deleteFileQuietly(item.filePath);
    }
  }

  Future<int> processPendingForService(String serviceId) {
    return processPending(serviceId: serviceId);
  }

  Future<int> processPending({String? serviceId}) async {
    if (kIsWeb || _processing) return 0;
    _processing = true;
    var completed = 0;
    try {
      final normalizedServiceId = serviceId?.trim();
      var items = await _load();
      final targets = items.where((item) {
        if (normalizedServiceId == null || normalizedServiceId.isEmpty) {
          return true;
        }
        return item.serviceId == normalizedServiceId;
      }).toList();

      for (final item in targets) {
        final file = File(item.filePath);
        if (!await file.exists()) {
          items.removeWhere((entry) => entry.id == item.id);
          continue;
        }

        try {
          final bytes = await file.readAsBytes();
          final videoUrl = await ApiService().uploadServiceVideo(
            bytes,
            filename: item.filename,
            mimeType: 'video/mp4',
          );
          await ApiService().confirmServiceCompletion(
            item.serviceId,
            code: item.completionCode?.trim().isEmpty == true
                ? null
                : item.completionCode,
            proofVideo: videoUrl,
          );
          items.removeWhere((entry) => entry.id == item.id);
          await _deleteFileQuietly(item.filePath);
          completed++;
        } catch (e) {
          final failed = item.copyWith(
            attempts: item.attempts + 1,
            lastError: e.toString(),
          );
          items = items
              .map((entry) => entry.id == failed.id ? failed : entry)
              .toList();
        }
        await _save(items);
      }
    } finally {
      _processing = false;
    }
    return completed;
  }

  Future<Directory> _queueDirectory() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${baseDir.path}/pending_service_videos');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<_PendingServiceVideoUpload>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((item) => _PendingServiceVideoUpload.fromJson(item))
        .toList();
  }

  Future<void> _save(List<_PendingServiceVideoUpload> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(items.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _deleteFileQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort cleanup.
    }
  }
}

class _PendingServiceVideoUpload {
  const _PendingServiceVideoUpload({
    required this.id,
    required this.serviceId,
    required this.filePath,
    required this.filename,
    required this.completionCode,
    required this.createdAt,
    required this.attempts,
    required this.lastError,
  });

  final String id;
  final String serviceId;
  final String filePath;
  final String filename;
  final String? completionCode;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;

  factory _PendingServiceVideoUpload.fromJson(Map<dynamic, dynamic> json) {
    final completionCode = '${json['completionCode'] ?? ''}'.trim();
    return _PendingServiceVideoUpload(
      id: '${json['id'] ?? ''}'.trim(),
      serviceId: '${json['serviceId'] ?? ''}'.trim(),
      filePath: '${json['filePath'] ?? ''}'.trim(),
      filename: '${json['filename'] ?? 'service_evidence.mp4'}'.trim(),
      completionCode: completionCode.isEmpty ? null : completionCode,
      createdAt:
          DateTime.tryParse('${json['createdAt'] ?? ''}')?.toUtc() ??
          DateTime.now().toUtc(),
      attempts: int.tryParse('${json['attempts'] ?? 0}') ?? 0,
      lastError: '${json['lastError'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['lastError'] ?? ''}'.trim(),
    );
  }

  _PendingServiceVideoUpload copyWith({int? attempts, String? lastError}) {
    return _PendingServiceVideoUpload(
      id: id,
      serviceId: serviceId,
      filePath: filePath,
      filename: filename,
      completionCode: completionCode,
      createdAt: createdAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'serviceId': serviceId,
      'filePath': filePath,
      'filename': filename,
      'completionCode': completionCode,
      'createdAt': createdAt.toIso8601String(),
      'attempts': attempts,
      'lastError': lastError,
    };
  }
}
