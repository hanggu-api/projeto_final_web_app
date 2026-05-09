import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

typedef RawMediaFetcher = Future<http.Response> Function(String endpoint);
typedef StorageUrlResolver = String? Function(String? value);
typedef LocalWebEnvironmentResolver = bool Function();
typedef ApiExceptionFactory =
    Exception Function({required String message, required int statusCode});

class ApiMediaStorage {
  ApiMediaStorage({
    required StorageUrlResolver resolveStorageUrl,
    required LocalWebEnvironmentResolver isLocalWebEnvironment,
    required RawMediaFetcher fetchRaw,
    required ApiExceptionFactory exceptionFactory,
  }) : _resolveStorageUrl = resolveStorageUrl,
       _isLocalWebEnvironment = isLocalWebEnvironment,
       _fetchRaw = fetchRaw,
       _exceptionFactory = exceptionFactory;

  final StorageUrlResolver _resolveStorageUrl;
  final LocalWebEnvironmentResolver _isLocalWebEnvironment;
  final RawMediaFetcher _fetchRaw;
  final ApiExceptionFactory _exceptionFactory;
  final Map<String, Future<Uint8List>> _mediaBytesCache = {};

  Future<String> directUpload(
    String bucket,
    String typePath,
    List<int> bytes,
    String filename,
    String? contentType,
  ) async {
    try {
      final ext = filename.split('.').last;
      final uniqueName =
          '${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4().substring(0, 8)}.$ext';
      final path = '$typePath/$uniqueName';

      final supabase = Supabase.instance.client;
      await supabase.storage
          .from(bucket)
          .uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(
              contentType: contentType ?? 'application/octet-stream',
            ),
          );

      final publicUrl = _resolveStorageUrl('$bucket/$path') ?? '$bucket/$path';
      debugPrint('[Supabase Storage] File uploaded successfully: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('❌ [Supabase Storage] Upload error: $e');
      throw _exceptionFactory(
        message: 'Falha no upload para o Supabase: $e',
        statusCode: 500,
      );
    }
  }

  Future<String> uploadServiceImage(
    List<int> bytes, {
    String filename = 'image.jpg',
    String mimeType = 'image/jpeg',
  }) {
    return directUpload('service_media', 'images', bytes, filename, mimeType);
  }

  Future<String> uploadServiceVideo(
    List<int> bytes, {
    String filename = 'video.mp4',
    String? mimeType,
  }) {
    return directUpload(
      'service_media',
      'videos',
      bytes,
      filename,
      mimeType ?? 'video/mp4',
    );
  }

  Future<String> uploadServiceAudio(
    List<int> bytes, {
    String filename = 'audio.m4a',
  }) {
    return directUpload(
      'service_media',
      'audios',
      bytes,
      filename,
      'audio/mp4',
    );
  }

  Future<String> uploadChatImage(
    String serviceId,
    List<int> bytes, {
    String filename = 'chat.jpg',
  }) {
    return directUpload('chat_media', serviceId, bytes, filename, 'image/jpeg');
  }

  Future<String> uploadChatAudio(
    String serviceId,
    List<int> bytes, {
    String filename = 'audio.m4a',
    String mimeType = 'audio/mp4',
  }) {
    return directUpload('chat_media', serviceId, bytes, filename, mimeType);
  }

  Future<String> uploadChatVideo(
    String serviceId,
    List<int> bytes, {
    String filename = 'video.mp4',
    String? mimeType,
  }) {
    return directUpload(
      'chat_media',
      serviceId,
      bytes,
      filename,
      mimeType ?? 'video/mp4',
    );
  }

  Future<String> uploadMediaFromPath(
    String path, {
    required String filename,
    String? serviceId,
    String type = 'image',
    String? mimeType,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('Arquivo não encontrado: $path');
    }
    final bytes = await file.readAsBytes();
    final bucket = type == 'service' ? 'service_media' : 'chat_media';
    final sId = serviceId ?? 'general';
    return directUpload(bucket, sId, bytes, filename, mimeType);
  }

  Future<String> uploadToCloud(
    List<int> bytes, {
    required String filename,
    String? serviceId,
    String type = 'image',
  }) {
    final bucket = type == 'chat' ? 'chat_media' : 'service_media';
    final sId = serviceId ?? 'general';
    return directUpload(bucket, sId, bytes, filename, null);
  }

  Future<String> getMediaViewUrl(String key) async {
    final resolved = _resolveStorageUrl(key);
    if (resolved != null) return resolved;
    return key;
  }

  String getMediaUrl(String key) {
    if (key.isEmpty) return '';
    final resolved = _resolveStorageUrl(key);
    if (resolved != null) return resolved;
    return key;
  }

  Future<Uint8List> getMediaBytes(String key) {
    if (_mediaBytesCache.containsKey(key)) {
      return _mediaBytesCache[key]!;
    }
    final future = _fetchBytes(key);
    _mediaBytesCache[key] = future;
    return future;
  }

  void invalidateMediaBytesCache([String? key]) {
    if (key == null || key.trim().isEmpty) {
      _mediaBytesCache.clear();
      return;
    }
    _mediaBytesCache.remove(key);
  }

  Future<Uint8List> _fetchBytes(String key) async {
    try {
      final resolved = _resolveStorageUrl(key);
      if (resolved != null) {
        final response = await http.get(Uri.parse(resolved));
        if (response.statusCode == 200) {
          return response.bodyBytes;
        }
        throw Exception('Status ${response.statusCode} fetching $resolved');
      }

      if (key.startsWith('http')) {
        final response = await http.get(Uri.parse(key));
        if (response.statusCode == 200) {
          return response.bodyBytes;
        }
        throw Exception('Status ${response.statusCode} fetching $key');
      }

      if (_isLocalWebEnvironment()) {
        throw Exception(
          'Nao foi possivel resolver a midia "$key" para uma URL publica no Flutter Web local.',
        );
      }
      final response = await _fetchRaw(
        '/media/chat/raw?key=${Uri.encodeComponent(key)}',
      );
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      throw Exception('Status ${response.statusCode}');
    } catch (_) {
      unawaited(_mediaBytesCache.remove(key));
      rethrow;
    }
  }
}
