import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../chat_state.dart';
import '../../../../services/data_gateway.dart';
import '../../../shared/in_app_camera_screen.dart';
import '../../../../utils/file_bytes.dart';

mixin ChatMediaMixin<T extends StatefulWidget> on State<T>, ChatStateMixin<T> {
  Future<Uint8List> fetchImageBytesCached(String key) {
    return imageFutureCache.putIfAbsent(key, () => api.getMediaBytes(key));
  }

  Future<String?> uploadToStorage({
    Uint8List? bytes,
    String? path,
    required String filename,
    required String mimeType,
    required String serviceId,
  }) async {
    try {
      if (kIsWeb) {
        if (bytes != null) {
          return await api.uploadToCloud(bytes, filename: filename, serviceId: serviceId, type: 'chat');
        }
      } else {
        if (path != null) {
          return await api.uploadMediaFromPath(path, filename: filename, serviceId: serviceId, type: 'chat', mimeType: mimeType);
        } else if (bytes != null) {
          return await api.uploadToCloud(bytes, filename: filename, serviceId: serviceId, type: 'chat');
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error uploading: $e');
      return null;
    }
  }

  Future<void> openUnifiedCamera(String serviceId, VoidCallback onScroll) async {
    try {
      final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const InAppCameraScreen()));
      if (result == null) return;
      
      String path = '';
      Uint8List? bytes;
      String name = '';
      bool isVideo = false;

      if (result is XFile) {
        path = result.path;
        name = result.name;
        final ext = name.split('.').last.toLowerCase();
        if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) isVideo = true;
        if (kIsWeb) bytes = await result.readAsBytes();
      }

      if (isVideo) {
        await uploadAndSendVideo(path: path, bytes: bytes, filename: name, serviceId: serviceId, onScroll: onScroll);
      } else {
        await processImageUpload(XFile(path, bytes: bytes, name: name), serviceId: serviceId, onScroll: onScroll);
      }
    } catch (e) {
      debugPrint('Error in unified camera: $e');
    }
  }

  Future<void> uploadAndSendVideo({required String path, Uint8List? bytes, required String filename, required String serviceId, required VoidCallback onScroll}) async {
    final tempId = 'temp_vid_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticMsg = {
      'id': tempId,
      'content': path,
      'type': 'video', 
      'created_at': DateTime.now().toIso8601String(),
      'sender_id': myUserId,
      'status': 'sending',
      'is_optimistic': true,
      'localContent': bytes ?? path,
    };

    setState(() {
      pendingMessages.add(optimisticMsg);
    });
    onScroll();

    try {
      final url = await uploadToStorage(bytes: bytes, path: path, filename: filename, mimeType: 'video/mp4', serviceId: serviceId);
      if (url == null) throw Exception('Upload falhou');

      await DataGateway().sendChatMessage(serviceId, url, 'video');
      
      if (mounted) {
        setState(() {
          final index = pendingMessages.indexWhere((m) => m['id'] == tempId);
          if (index != -1) {
            pendingMessages[index]['content'] = url;
            pendingMessages[index]['status'] = 'sent';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => pendingMessages.removeWhere((m) => m['id'] == tempId));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao enviar vídeo: $e')));
      }
    }
  }

  Future<void> processImageUpload(XFile f, {required String serviceId, required VoidCallback onScroll}) async {
    final tempId = 'temp_img_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      pendingMessages.add({
        'id': tempId,
        'content': f.path, 
        'type': 'image',
        'created_at': DateTime.now().toIso8601String(),
        'sender_id': myUserId,
        'status': 'sending',
        'is_optimistic': true,
        'localContent': f,
      });
    });
    onScroll();

    try {
      String? url;
      if (kIsWeb) {
        final b = await f.readAsBytes();
        url = await uploadToStorage(bytes: b, filename: f.name, mimeType: 'image/webp', serviceId: serviceId);
      } else {
        url = await uploadToStorage(path: f.path, filename: f.name, mimeType: 'image/jpeg', serviceId: serviceId);
      }

      if (url != null) {
        await DataGateway().sendChatMessage(serviceId, url, 'image');
        if (mounted) {
          setState(() {
            final index = pendingMessages.indexWhere((m) => m['id'] == tempId);
            if (index != -1) {
              pendingMessages[index]['content'] = url;
              pendingMessages[index]['status'] = 'sent';
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => pendingMessages.removeWhere((m) => m['id'] == tempId));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao enviar imagem: $e')));
      }
    }
  }

  Future<void> toggleRecord(String serviceId, VoidCallback onScroll) async {
    try {
      if (!isRecording) {
        final has = await rec.hasPermission();
        if (!has) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permissão de microfone negada')));
          return;
        }
        final config = const RecordConfig();
        if (kIsWeb) {
          final path = 'audio_${DateTime.now().millisecondsSinceEpoch}.webm';
          await rec.start(config, path: path);
        } else {
          final dir = await getTemporaryDirectory();
          final path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
          await rec.start(config, path: path);
        }
        setState(() {
          isRecording = true;
          recordStartAt = DateTime.now();
          recordTicker?.cancel();
          recordTicker = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
        });
      } else {
        final elapsed = DateTime.now().difference(recordStartAt!);
        if (elapsed.inMilliseconds < 800) await Future.delayed(Duration(milliseconds: 800 - elapsed.inMilliseconds));
        
        final path = await rec.stop();
        setState(() {
          isRecording = false;
          recordTicker?.cancel();
        });
        if (path == null) return;
        
        final tempId = 'temp_audio_${DateTime.now().millisecondsSinceEpoch}';
        setState(() {
          pendingMessages.add({
            'id': tempId,
            'content': path, 
            'type': 'audio',
            'created_at': DateTime.now().toIso8601String(),
            'sender_id': myUserId,
            'status': 'sending',
            'is_optimistic': true,
            'localContent': path, 
          });
        });
        onScroll();
        
        try {
          String mime = 'audio/mpeg';
          String filename = path.split('/').last;
          Uint8List? bytes;
          
          if (kIsWeb) {
            mime = 'audio/webm';
            filename = 'audio.webm';
            bytes = await readFileBytes(path);
          } else {
            if (path.endsWith('.m4a')) {
              mime = 'audio/x-m4a';
            } else if (path.endsWith('.aac')) mime = 'audio/aac';
            else if (path.endsWith('.wav')) mime = 'audio/wav';
          }
          
          final url = await uploadToStorage(path: path, bytes: bytes, filename: filename, mimeType: mime, serviceId: serviceId);
          if (url == null) throw Exception('Upload falhou');
          
          await DataGateway().sendChatMessage(serviceId, url, 'audio');
          if (mounted) {
            setState(() {
              final index = pendingMessages.indexWhere((m) => m['id'] == tempId);
              if (index != -1) {
                pendingMessages[index]['content'] = url;
                pendingMessages[index]['status'] = 'sent';
              }
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() => pendingMessages.removeWhere((m) => m['id'] == tempId));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro de gravação: $e')));
          }
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro de gravação: $e')));
    }
  }
}
