import 'dart:async';
import 'dart:convert';
import 'dart:io';


import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'in_app_camera_screen.dart'; // Unified Camera
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:intl/intl.dart';

import 'widgets/schedule_proposal_bubble.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/realtime_service.dart';
import '../../services/data_gateway.dart';
import '../../utils/file_bytes.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/user_avatar.dart';

class ChatScreen extends StatefulWidget {
  final String serviceId;
  final String? otherName; // Name of the other person (Client/Provider)
  final String? otherAvatar; // Avatar URL of the other person

  const ChatScreen({
    super.key,
    required this.serviceId,
    this.otherName,
    this.otherAvatar,
  });

  static String? activeChatServiceId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _api = ApiService();
  final _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _messages = [];
  final List<Map<String, dynamic>> _pendingMessages = []; // Mensagens sendo enviadas
  // Mostrar a lista invertida para que a última mensagem fique sempre na parte inferior.
  Timer? _pollingTimer;
  StreamSubscription? _chatSubscription;
  Map<String, dynamic>? _serviceDetails;
  int? _myUserId;
  final AudioRecorder _rec = AudioRecorder();
  bool _isRecording = false;
  DateTime? _recordStartAt;
  Timer? _recordTicker;
  String? _role;
  final GlobalKey _inputAreaKey = GlobalKey();

  // Valor inicial ajustado para a altura de apenas a área de input (aprox. 80)
  double _bottomPadding = 80;
  int? _otherUserId;
  bool _isOtherOnline = false;

  // Upload state
  final bool _isUploading = false;
  final String _uploadingType = '';

  final Map<String, Future<Uint8List>> _imageFutureCache = {};

  Future<Uint8List> _fetchImageBytesCached(String key) {
    return _imageFutureCache.putIfAbsent(key, () => _api.getMediaBytes(key));
  }

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() {
          _role = prefs.getString('user_role');
        });
        _calculateOtherUser();
      }
    });

    _api.getMyUserId().then((id) {
      if (mounted) setState(() => _myUserId = id);
      if (id != null) {
        RealtimeService().authenticate(id);
      }
      _calculateOtherUser();
    });
    _loadServiceInfo();
    final rt = RealtimeService();
    rt.connect();

    // D1 Signal-based Chat Stream
    debugPrint('[IMPORTANT] Starting signal-based chat subscription for service ${widget.serviceId}');
    _chatSubscription = DataGateway().watchChat(widget.serviceId).listen((msgs) {
      debugPrint('[IMPORTANT] Chat signal received: ${msgs.length} messages fetched via API');
      
      // Sort: Newest First (index 0)
      final sortedMsgs = List<dynamic>.from(msgs);
      sortedMsgs.sort((a, b) => _parseMessageDate(b).compareTo(_parseMessageDate(a)));

      if (mounted) {
        setState(() {
           _messages = sortedMsgs;
           _reconcilePendingMessages();
        });
        if (_scrollController.hasClients && _scrollController.offset < 100) {
          _scrollToBottom();
        }
      }
    });


    WidgetsBinding.instance.addPostFrameCallback((_) => _updateBottomPadding());
    unawaited(
      SharedPreferences.getInstance().then(
        (p) => p.setInt('unread_chat_count', 0),
      ),
    );
    ChatScreen.activeChatServiceId = widget.serviceId;
  }

  @override
  void dispose() {
    if (ChatScreen.activeChatServiceId == widget.serviceId) {
      ChatScreen.activeChatServiceId = null;
    }
    _chatSubscription?.cancel();
    RealtimeService().leaveService();
    _pollingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _reconcilePendingMessages() {
    if (_pendingMessages.isEmpty) return;
    
    // Remove pending messages that are already in _messages
    // Match by Content (URL for media, Text for text) AND Type
    _pendingMessages.removeWhere((pending) {
       // Only remove if status is 'sent' (API success confirmed)
       if (pending['status'] != 'sent') return false;

       final pContent = pending['content'];
       final pType = pending['type'];

       // Check if ANY message in _messages matches this pending one
       final exists = _messages.any((serverMsg) {
          final sContent = serverMsg['content'];
          final sType = serverMsg['type'];
          // Simple equality check. 
          // For media: pending['content'] becomes URL after upload success.
          return sContent == pContent && sType == pType;
       });
       
       return exists;
    });
  }

  Future<void> _loadServiceInfo() async {
    try {
      final details = await _api.getServiceDetails(widget.serviceId);
      if (mounted) {
        setState(() => _serviceDetails = details);
        _calculateOtherUser();
      }
    } catch (_) {}
  }

  void _calculateOtherUser() {
    if (_serviceDetails == null) return;
    if (_role == null && _myUserId == null) return;

    final s = _serviceDetails!;

    bool isMeClient = false;
    if (_role == 'client') {
      isMeClient = true;
    } else if (_role == 'provider') {
      isMeClient = false;
    } else {
      final myIdStr = _myUserId?.toString();
      dynamic userIdRaw = s['user_id'];
      if (userIdRaw == null && s['client'] is Map) {
        userIdRaw = s['client']['id'];
      }
      final serviceUserIdStr = userIdRaw?.toString();
      isMeClient = serviceUserIdStr != null && myIdStr == serviceUserIdStr;
    }

    int? targetId;
    if (isMeClient) {
      if (s['provider_id'] != null) {
        targetId = s['provider_id'] is int
            ? s['provider_id']
            : int.tryParse(s['provider_id'].toString());
      }
      if (targetId == null && s['provider'] is Map) {
        final pId = s['provider']['id'];
        if (pId != null) {
          targetId = pId is int ? pId : int.tryParse(pId.toString());
        }
      }
    } else {
      if (s['client_id'] != null) {
        targetId = s['client_id'] is int
            ? s['client_id']
            : int.tryParse(s['client_id'].toString());
      }
      if (targetId == null && s['client'] is Map) {
        final cId = s['client']['id'];
        if (cId != null) {
          targetId = cId is int ? cId : int.tryParse(cId.toString());
        }
      }
    }

    if (targetId != null && targetId != _otherUserId) {
      setState(() => _otherUserId = targetId);
      RealtimeService().checkStatus(targetId, (online) {
        if (mounted) setState(() => _isOtherOnline = online);
      });
    }
  }


  Future<void> _sendMessage({String? content}) async {
    final text = content ?? _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    
    // Optimistic UI: Add message locally immediately
    final tempId = DateTime.now().millisecondsSinceEpoch;
    final optimisticMsg = {
      'id': 'temp_$tempId',
      'content': text,
      'type': 'text',
      'created_at': DateTime.now().toIso8601String(),
      'sender_id': _myUserId,
      'status': 'sending',
    };

    setState(() {
      _pendingMessages.add(optimisticMsg);
    });

    try {
      await DataGateway().sendChatMessage(widget.serviceId, text, 'text');
      // Do not remove yet. Wait for stream to confirm.
      if (mounted) {
        setState(() {
            final index = _pendingMessages.indexWhere((m) => m['id'] == 'temp_$tempId');
            if (index != -1) {
              _pendingMessages[index]['status'] = 'sent';
            }
        });
      }
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        setState(() {
           _pendingMessages.removeWhere((m) => m['id'] == 'temp_$tempId');
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao enviar: $e')));
      }
    }
  }

  Future<String?> _uploadToStorage({
    Uint8List? bytes,
    String? path,
    required String filename,
    required String mimeType,
  }) async {
    try {
      // Usar a API para obter URL assinada e fazer upload direto (R2/GCS)
      // Isso evita problemas de autenticação direta com Firebase Storage e usa a lógica do Cloudflare Worker.
      
      if (kIsWeb) {
         if (bytes != null) {
           return await _api.uploadToCloud(
             bytes, 
             filename: filename, 
             serviceId: widget.serviceId,
             type: 'chat'
           );
         }
      } else {
         if (path != null) {
           return await _api.uploadMediaFromPath(
             path,
             filename: filename,
             serviceId: widget.serviceId,
             type: 'chat',
             mimeType: mimeType,
           );
         } else if (bytes != null) {
           // Fallback para bytes no mobile (raro, mas possível)
            return await _api.uploadToCloud(
             bytes, 
             filename: filename, 
             serviceId: widget.serviceId,
             type: 'chat'
           );
         }
      }
      return null;
    } catch (e) {
      debugPrint('Error uploading to R2/Storage: $e');
      return null;
    }
  }

  // Future<void> _sendImage() async { ... } // Removed unused legacy method

  Future<void> _openUnifiedCamera() async {
    try {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const InAppCameraScreen()),
      );

      if (result == null) return;
      
      // Result can be XFile (from camera) or PlatformFile/XFile (from gallery)
      // We need to normalize.
      String path = '';
      Uint8List? bytes;
      String name = '';
      bool isVideo = false;

      if (result is XFile) {
        path = result.path;
        name = result.name;
        // Check extension or mime
        final ext = name.split('.').last.toLowerCase();
        if (['mp4', 'mov', 'avi', 'mkv'].contains(ext)) {
           isVideo = true;
        }
        if (kIsWeb) {
           bytes = await result.readAsBytes();
        }
      } else {
        // Fallback or other types (not expected with current InAppCamera implementation)
      }

      if (isVideo) {
         // Re-use _sendVideo logic but adapting to the file we already have
         await _uploadAndSendVideo(path: path, bytes: bytes, filename: name);
      } else {
         // Image
         // Re-use _sendImage logic. We can wrap it in a list to mimic FilePicker result
         // Or create a specific helper. 
         // Let's create a temporary list of XFile to pass to the existing logic or refactor.
         // Actually, _sendImage uses FilePicker result. Let's create a helper to process a single file.
         _processImageUpload(XFile(path, bytes: bytes, name: name));
      }
    } catch (e) {
      debugPrint('Error in unified camera: $e');
    }
  }

  Future<void> _uploadAndSendVideo({required String path, Uint8List? bytes, required String filename}) async {
    // 1. Optimistic UI
    final tempId = 'temp_vid_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticMsg = {
      'id': tempId,
      'content': path, // Use path for local preview
      'type': 'video', 
      'created_at': DateTime.now().toIso8601String(),
      'sender_id': _myUserId,
      'status': 'sending',
      'is_optimistic': true,
      'localContent': bytes ?? path, // Pass bytes (web) or path (mobile)
    };

    setState(() {
      _pendingMessages.add(optimisticMsg);
    });
    _scrollToBottom();

    try {
      final url = await _uploadToStorage(
        bytes: bytes,
        path: path,
        filename: filename,
        mimeType: 'video/mp4',
      );

      if (url == null) throw Exception('Upload falhou');

      await DataGateway().sendChatMessage(widget.serviceId, url, 'video');
      
      if (mounted) {
        setState(() {
           // Update content to URL so reconciliation can match it
           final index = _pendingMessages.indexWhere((m) => m['id'] == tempId);
           if (index != -1) {
             _pendingMessages[index]['content'] = url;
             _pendingMessages[index]['status'] = 'sent';
           }
        });
      }
    } catch (e) {
      debugPrint('Error uploading video: $e');
      if (mounted) {
        setState(() {
           _pendingMessages.removeWhere((m) => m['id'] == tempId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar vídeo: $e')),
        );
      }
    }
  }

  // Refactored helper for single image
  Future<void> _processImageUpload(XFile f) async {
     final tempId = 'temp_img_${DateTime.now().millisecondsSinceEpoch}';
     final optimisticMsg = {
        'id': tempId,
        'content': f.path, 
        'type': 'image',
        'created_at': DateTime.now().toIso8601String(),
        'sender_id': _myUserId,
        'status': 'sending',
        'is_optimistic': true,
        'localContent': f, // Pass XFile for local preview
     };

     setState(() {
       _pendingMessages.add(optimisticMsg);
     });
     _scrollToBottom();

     try {
       String? url;
       if (kIsWeb) {
         final b = await f.readAsBytes();
         url = await _uploadToStorage(
           bytes: b,
           filename: f.name,
           mimeType: 'image/webp',
         );
       } else {
         url = await _uploadToStorage(
           path: f.path,
           filename: f.name,
           mimeType: 'image/jpeg',
         );
       }

       if (url != null) {
          await DataGateway().sendChatMessage(widget.serviceId, url, 'image');
          if (mounted) {
             setState(() {
                final index = _pendingMessages.indexWhere((m) => m['id'] == tempId);
                if (index != -1) {
                   _pendingMessages[index]['content'] = url;
                   _pendingMessages[index]['status'] = 'sent';
                }
             });
          }
       } else {
          throw Exception('Upload URL is null');
       }
     } catch (e) {
         debugPrint('Error uploading image: $e');
         if (mounted) {
             setState(() {
               _pendingMessages.removeWhere((m) => m['id'] == tempId);
             });
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text('Erro ao enviar imagem: $e')),
             );
         }
     }
  }

  // Keep original _sendVideo as deprecated or remove? 
  // We can keep it or replace its content.
  // The UI no longer calls _sendVideo directly.
  // Future<void> _sendVideo() async { ... } // Removed unused legacy method

  Future<void> _toggleRecord() async {
    try {
      if (!_isRecording) {
        final has = await _rec.hasPermission();
        if (!has) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Permissão de microfone negada')),
            );
          }
          return;
        }
        final config = const RecordConfig();
        final dir = await getTemporaryDirectory();
        final path =
            '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _rec.start(config, path: path);
        setState(() {
          _isRecording = true;
          _recordStartAt = DateTime.now();
          _recordTicker?.cancel();
          _recordTicker = Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          });
        });
      } else {
        // Safety delay to prevent "Stop() called but track is not started" error
        final elapsed = DateTime.now().difference(_recordStartAt!);
        if (elapsed.inMilliseconds < 800) {
          await Future.delayed(Duration(milliseconds: 800 - elapsed.inMilliseconds));
        }
        
        final path = await _rec.stop();
        setState(() {
          _isRecording = false;
          _recordTicker?.cancel();
        });
        if (path == null) return;
        
        // Optimistic UI for Audio
        final tempId = 'temp_audio_${DateTime.now().millisecondsSinceEpoch}';
        final optimisticMsg = {
           'id': tempId,
           'content': path, 
           'type': 'audio',
           'created_at': DateTime.now().toIso8601String(),
           'sender_id': _myUserId,
           'status': 'sending',
           'is_optimistic': true,
           'localContent': path, 
        };

        setState(() {
          _pendingMessages.add(optimisticMsg);
          // Remove _isUploading overlay for better UX
        });
        _scrollToBottom();
        
        try {
          String mime;
          String filename;
          Uint8List? bytes;
          
          if (kIsWeb) {
            mime = 'audio/webm';
            filename = 'audio.webm';
            bytes = await readFileBytes(path);
          } else {
            if (path.endsWith('.m4a')) {
              mime = 'audio/x-m4a';
            } else if (path.endsWith('.aac')) {
              mime = 'audio/aac';
            } else if (path.endsWith('.wav')) {
              mime = 'audio/wav';
            } else {
              mime = 'audio/mpeg';
            }
            filename = path.split('/').last;
          }
          
          final url = await _uploadToStorage(
            path: path,
            bytes: bytes,
            filename: filename, 
            mimeType: mime
          );
          if (url == null) throw Exception('Upload falhou');
          
          await DataGateway().sendChatMessage(widget.serviceId, url, 'audio');
          if (mounted) {
             setState(() {
               final index = _pendingMessages.indexWhere((m) => m['id'] == tempId);
               if (index != -1) {
                 _pendingMessages[index]['content'] = url;
                 _pendingMessages[index]['status'] = 'sent';
               }
             });
          }
        } catch (e) {
          if (mounted) {
             setState(() {
                _pendingMessages.removeWhere((m) => m['id'] == tempId);
             });
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Erro de gravação: $e')));
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro de gravação: $e')));
      }
    }
  }

  // --- Schedule Proposal Logic ---
  Future<void> _confirmSchedule(DateTime date) async {
    try {
      await _api.confirmSchedule(widget.serviceId, date);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Agendamento confirmado!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao confirmar: $e')),
        );
      }
    }
  }

  // Debug Helper: Send Fake Proposal (Remove in Prod or keep for dev)
  Future<void> _sendDebugProposal() async {
    final now = DateTime.now().add(const Duration(hours: 24));
    // Simulate sending a JSON string or specific format for proposal
    // For simplicity, we use JSON in 'content' field for type 'schedule_proposal'
    final content = jsonEncode({'date': now.toIso8601String()});
    await DataGateway().sendChatMessage(widget.serviceId, content, 'schedule_proposal');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0, // Because reversed: true, 0.0 is the bottom
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _updateBottomPadding() {
    final inCtx = _inputAreaKey.currentContext;
    final inH = (inCtx?.size?.height ?? 0);
    final newVal = inH + 10;
    if (newVal > 0 && (newVal - _bottomPadding).abs() > 1) {
      setState(() => _bottomPadding = newVal);
      _scrollToBottom();
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_serviceDetails == null || _myUserId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final s = _serviceDetails!;

    // 1. Determine who I am (Client vs Provider)
    bool isMeClient = false;
    if (_role == 'client') {
      isMeClient = true;
    } else if (_role == 'provider') {
      isMeClient = false;
    } else {
      // Fallback: compare IDs
      final myIdStr = _myUserId.toString();
      dynamic userIdRaw = s['user_id'];
      if (userIdRaw == null && s['client'] is Map) {
        userIdRaw = s['client']['id'];
      }
      final serviceUserIdStr = userIdRaw?.toString();
      isMeClient = serviceUserIdStr != null && myIdStr == serviceUserIdStr;
    }

    String otherName;
    String? otherAvatar;
    int? otherId;

    if (isMeClient) {
      // I am Client -> Show Provider
      otherName =
          s['provider_name']?.toString() ??
          s['professional_name']?.toString() ??
          (s['provider'] is Map ? s['provider']['name']?.toString() : null) ??
          widget.otherName ??
          'Prestador';

      otherAvatar =
          s['provider_avatar']?.toString() ??
          s['professional_avatar']?.toString() ??
          s['provider_photo']?.toString() ??
          s['provider_image']?.toString() ??
          (s['provider'] is Map
              ? (s['provider']['avatar']?.toString() ??
                    s['provider']['photo']?.toString() ??
                    s['provider']['image']?.toString())
              : null) ??
          widget.otherAvatar;

      if (s['provider_id'] != null) {
        otherId = s['provider_id'] is int
            ? s['provider_id']
            : int.tryParse(s['provider_id'].toString());
      }
      if (otherId == null && s['provider'] is Map) {
        final pId = s['provider']['id'];
        if (pId != null) {
          otherId = pId is int ? pId : int.tryParse(pId.toString());
        }
      }
    } else {
      // I am Provider -> Show Client
      otherName =
          s['client_name']?.toString() ??
          s['user_name']?.toString() ??
          (s['client'] is Map ? s['client']['name']?.toString() : null) ??
          widget.otherName ??
          'Cliente';
          
      otherAvatar = 
          s['client_avatar']?.toString() ??
          s['user_avatar']?.toString() ??
          (s['client'] is Map ? (s['client']['avatar']?.toString() ?? s['client']['photo']?.toString()) : null) ??
          widget.otherAvatar;
          
       if (s['client_id'] != null) {
        otherId = s['client_id'] is int
            ? s['client_id']
            : int.tryParse(s['client_id'].toString());
      }
      if (otherId == null && s['client'] is Map) {
        final cId = s['client']['id'];
        if (cId != null) {
          otherId = cId is int ? cId : int.tryParse(cId.toString());
        }
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFE5DDD5), // WhatsApp background color
      appBar: AppBar(
        backgroundColor: AppTheme.primaryYellow,
        elevation: 0,
        iconTheme: IconThemeData(color: AppTheme.darkBlueText),
        title: Row(
          children: [
            UserAvatar(
              avatar: otherAvatar,
              name: otherName,
              userId: otherId,
              showOnlineStatus: true,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    otherName,
                    style: TextStyle(
                      fontSize: 16,
                      color: AppTheme.darkBlueText,
                      fontWeight: FontWeight.bold,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_isOtherOnline)
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppTheme.successGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Online',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Messages Area
              Expanded(
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _scrollController,
                    reverse: true, 
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    itemCount: _messages.length + _pendingMessages.length,
                    itemBuilder: (context, index) {
                      bool isPending = false;
                      Map<String, dynamic> msg;
                      dynamic localContent;

                      if (index < _pendingMessages.length) {
                         // Mensagens pendentes (Index 0 é a mais recente adicionada, se considerarmos que adicionamos no final)
                         // Mas queremos que a MAIS RECENTE fique EM BAIXO (Index 0 da ListView reverse)
                         // Então a lógica é: _pendingMessages.last é a mais recente.
                         isPending = true;
                         msg = _pendingMessages[_pendingMessages.length - 1 - index];
                         localContent = msg['localContent'];
                      } else {
                         // Mensagens do servidor
                         msg = _messages[index - _pendingMessages.length];
                      }

                      final senderIdRaw = msg['sender_id'];
                      final isMe = isPending 
                          ? true 
                          : (_myUserId != null && senderIdRaw.toString() == _myUserId.toString());
                      
                      if (!isPending && index == _pendingMessages.length && _pendingMessages.isEmpty) {
                         // Debug apenas do primeiro item "real" se não houver pendentes
                         // debugPrint('[VERYIMPORTANT] Bottom message...');
                      }

                      final type = (msg['type'] ?? 'text').toString();

                      final ts = (msg['created_at'] ?? msg['sent_at'])?.toString();
                      String time = 'Agora';
                      
                      if (ts != null) {
                        try {
                          final date = DateTime.tryParse(ts);
                          if (date != null) {
                            time = DateFormat('HH:mm').format(date.toLocal());
                          }
                        } catch (e) {
                          // Fallback to substring if parse fails (legacy compatibility)
                          if (ts.length >= 16) time = ts.substring(11, 16);
                        }
                      }
                      
                      return _buildMessageBubble(
                        (msg['content'] ?? '').toString(),
                        type,
                        isMe,
                        time,
                        isPending: isPending,
                        localContent: localContent,
                      );
                    },
                  ),
                ),
              ),

              // Input Area
              Container(
                key: _inputAreaKey,
                padding: const EdgeInsets.fromLTRB(
                  12,
                  8,
                  12,
                  8, // Reduced padding
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Botão Unificado de Câmera (WhatsApp Style)
                    IconButton(
                      icon: const Icon(LucideIcons.camera, size: 26),
                      color: Colors.grey[600],
                      onPressed: _openUnifiedCamera,
                    ),
                    IconButton(
                      icon: Icon(
                        _isRecording ? LucideIcons.stopCircle : LucideIcons.mic,
                      ),
                      color: _isRecording ? Colors.red : Colors.grey[600],
                      onPressed: _toggleRecord,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Mensagem',
                          filled: true,
                          fillColor: Colors.white,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                              color: AppTheme.primaryYellow,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const SizedBox(width: 8),
                    // Provider-only: Schedule Proposal Button
                    const SizedBox(width: 8),
                    // Calendar button removed in favor of ServiceCard acton
                    /*
                    if (_role == 'provider')
                      IconButton(...)
                    */
                    Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF007AFF), // Blue Button
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(
                          LucideIcons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: () => _sendMessage(),
                      ),
                    ),
                  ],
                ),
              ),
              if (_isRecording)
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(LucideIcons.mic, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Text('Gravando... ${_formatElapsed()}'),
                    ],
                  ),
                ),
            ],
          ),
          
          // Loading Overlay
          if (_isUploading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Enviando $_uploadingType...',
                        style: const TextStyle(
                          color: Colors.black87, 
                          fontWeight: FontWeight.bold
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }

  String _formatElapsed() {
    if (_recordStartAt == null) return '00:00';
    final d = DateTime.now().difference(_recordStartAt!);
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  void _openImageModal(Uint8List bytes) {
    showDialog(
      context: context,
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: GestureDetector(
            onTap: () => Navigator.of(ctx).pop(),
            child: SizedBox(
              width: size.width,
              height: size.height * 0.85,
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 1.0,
                maxScale: 4.0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openImageUrlModal(String url) {
    showDialog(
      context: context,
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: GestureDetector(
            onTap: () => Navigator.of(ctx).pop(),
            child: SizedBox(
              width: size.width,
              height: size.height * 0.85,
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 1.0,
                maxScale: 4.0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageBubble(
    String content,
    String type,
    bool isMe,
    String time, {
    bool isPending = false,
    dynamic localContent,
  }) {
    final isImage = type == 'image';
    Widget bubbleChild;
    if (isImage) {
      Widget imageWidget;
      if (isPending && localContent != null) {
        // Renderização de imagem local (Otimista)
        if (kIsWeb) {
             // Web: localContent should be PlatformFile (bytes) or Uint8List
             Uint8List? bytes;
             if (localContent is PlatformFile) {
               bytes = localContent.bytes;
             } else if (localContent is Uint8List) {
               bytes = localContent;
             }
             
             imageWidget = bytes != null 
                 ? Image.memory(bytes, width: 220, fit: BoxFit.cover) 
                 : Container(width: 220, height: 140, color: Colors.grey);
        } else {
             // Mobile: localContent is XFile
             if (localContent is XFile) {
                imageWidget = Image.file(File(localContent.path), width: 220, fit: BoxFit.cover);
             } else {
                imageWidget = Container(width: 220, height: 140, color: Colors.grey);
             }
        }
      } else {
        // Renderização normal (URL)
        imageWidget = content.startsWith('http') 
          ? GestureDetector(
              onTap: () => _openImageUrlModal(content),
              child: Image.network(
                content,
                width: 220,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.broken_image, color: Colors.white54),
                loadingBuilder: (_, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    width: 220, height: 140, color: Colors.black12,
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                },
              ),
            )
          : FutureBuilder<Uint8List>(
              future: _fetchImageBytesCached(content),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return Container(width: 220, height: 140, color: Colors.black12);
                }
                return GestureDetector(
                  onTap: () => _openImageModal(snap.data!),
                  child: Image.memory(
                    snap.data!,
                    width: 220,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                );
              },
            );
      }

      bubbleChild = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: isPending 
            ? Stack(
                alignment: Alignment.center,
                children: [
                  ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      Colors.black.withValues(alpha: 0.4), 
                      BlendMode.darken
                    ),
                    child: imageWidget,
                  ),
                  const CircularProgressIndicator(color: Colors.white),
                ],
              ) 
            : imageWidget,
      );

    } else if (type == 'video') {
      bubbleChild = VideoMessageBubble(
        videoUrl: content,
        isMe: isMe,
      );
    } else if (type == 'audio') {
      bubbleChild = AudioBubble(mediaKey: content, api: _api, isMe: isMe);
    } else if (type == 'schedule_proposal') {
      // Decode content (expected JSON: {"date": "..."})
      DateTime? scheduledDate;
      try {
        final map = jsonDecode(content);
        if (map['date'] != null) {
          scheduledDate = DateTime.parse(map['date']).toLocal();
        }
      } catch (_) {}

      if (scheduledDate != null) {
        // Only CLIENT can confirm. Provider sees it but cannot click.
        // Logic: showAction = (I am Client)
        final isClient = _role == 'client';
        
        bubbleChild = ScheduleProposalBubble(
          scheduledDate: scheduledDate,
          isMe: isMe,
          showAction: isClient,
          onConfirm: () => _confirmSchedule(scheduledDate!),
        );
      } else {
        bubbleChild = const Text('Proposta de agendamento inválida.');
      }
    } else {
      bubbleChild = Text(
        content,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 15,
        ),
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: isImage
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isImage
              ? Colors.transparent
              : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: isMe ? const Radius.circular(18) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            bubbleChild,
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 10,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    LucideIcons.checkCheck,
                    size: 14,
                    color: Colors.blueAccent, // Ou white70 se preferir discreto
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  DateTime _parseMessageDate(Map<String, dynamic> msg) {
    try {
      var val = msg['created_at'] ?? msg['sent_at'] ?? msg['createdAt'] ?? msg['sentAt'] ?? msg['timestamp'];
      if (val == null) return DateTime.fromMillisecondsSinceEpoch(0);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is String) return DateTime.tryParse(val) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return DateTime.fromMillisecondsSinceEpoch(0);
    } catch (e) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }
}

// AudioBubble
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
    if (widget.mediaKey.startsWith('http')) {
      // Direct URL (Firebase Storage)
      setState(() {
        _loadingUrl = false;
      });
    } else if (widget.mediaKey.contains('/') && !kIsWeb) {
       // Local File (Optimistic)
       setState(() {
         _loadingUrl = false;
       });
    } else {
      // Legacy API Key
      widget.api
          .getMediaBytes(widget.mediaKey)
          .then((b) {
            if (!mounted) return;
            setState(() {
              _bytes = b;
              _loadingUrl = false;
            });
          })
          .catchError((e) {
            debugPrint('Error loading audio bytes: $e');
            if (mounted) setState(() => _loadingUrl = false);
          });
    }

    _player.onPlayerComplete.listen(
      (_) => setState(() {
        _playing = false;
        _position = Duration.zero;
      }),
    );
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
    // If not URL and no bytes (legacy fail) AND not local file
    final isLocal = !widget.mediaKey.startsWith('http') && widget.mediaKey.contains('/');
    if (!widget.mediaKey.startsWith('http') && !isLocal && _bytes == null) return;

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
          } else {
            // Legacy Byte Playback or Local File
            if (!widget.mediaKey.startsWith('http') && widget.mediaKey.contains('/') && !kIsWeb) {
               await _player.play(DeviceFileSource(widget.mediaKey));
            } else if (kIsWeb) {
              final base64Audio = base64Encode(_bytes!);
              final mimeType = 'audio/mpeg';
              final dataUri = 'data:$mimeType;base64,$base64Audio';
              await _player.play(UrlSource(dataUri));
            } else {
              final tempDir = await getTemporaryDirectory();
              final file = File(
                '${tempDir.path}/audio_${widget.mediaKey.hashCode}.m4a',
              );
              if (!await file.exists()) {
                await file.writeAsBytes(_bytes!);
              }
              await _player.play(DeviceFileSource(file.path));
            }
          }
        }
        setState(() => _playing = true);
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao reproduzir áudio: $e')));
      }
      setState(() => _playing = false);
    }
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    // final isMe = widget.isMe; // Unused after style change
    // Texto/Ícones baseados no fundo do balão
    final fgColor = Colors.black87;
    // Cor de destaque (Play/Slider) solicitada: Laranja
    final accentColor = AppTheme.secondaryOrange;

    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Botão Play/Pause
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
                    color: Colors.black.withValues(alpha: 0.1),
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

          // Slider e Tempo
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
                      inactiveTrackColor: Colors.grey.withValues(alpha: 0.3),
                    ),
                    child: Slider(
                      value: _position.inSeconds.toDouble().clamp(
                        0,
                        _duration.inSeconds.toDouble(),
                      ),
                      max: _duration.inSeconds.toDouble() > 0
                          ? _duration.inSeconds.toDouble()
                          : 1.0,
                      onChanged: (v) {
                        final pos = Duration(seconds: v.toInt());
                        _player.seek(pos);
                      },
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
                          color: fgColor.withValues(alpha: 0.8),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        _formatDuration(_duration),
                        style: TextStyle(
                          color: fgColor.withValues(alpha: 0.8),
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

class VideoMessageBubble extends StatefulWidget {
  final String videoUrl;
  final bool isMe;
  
  const VideoMessageBubble({
    super.key,
    required this.videoUrl,
    required this.isMe,
  });
  
  @override
  State<VideoMessageBubble> createState() => _VideoMessageBubbleState();
}

class _VideoMessageBubbleState extends State<VideoMessageBubble> {
  late VideoPlayerController _controller;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  
  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }
  
  Future<void> _initializePlayer() async {
    try {
      if (widget.videoUrl.startsWith('http')) {
        _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      } else {
        _controller = VideoPlayerController.file(File(widget.videoUrl));
      }
      await _controller.initialize();
      
      _chewieController = ChewieController(
        videoPlayerController: _controller,
        autoPlay: false,
        looping: false,
        aspectRatio: _controller.value.aspectRatio > 0 ? _controller.value.aspectRatio : 16/9,
        // Hide controls inline
        showControls: false,
        placeholder: Container(
          color: Colors.black12,
          child: const Center(child: CircularProgressIndicator()),
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              'Erro ao carregar vídeo',
              style: const TextStyle(color: Colors.black, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          );
        },
      );
      
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      debugPrint('Error initializing video player: $e');
    }
  }
  
  @override
  void dispose() {
    _controller.dispose();
    _chewieController?.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Container(
        width: 220,
        height: 140,
        color: Colors.black12,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.black,
          ),
        ),
      );
    }
    
    return SizedBox(
      width: 220,
      height: 220 / _controller.value.aspectRatio,
      child: Stack(
        alignment: Alignment.center,
        children: [
           Chewie(controller: _chewieController!),
           // Overlay transparente para capturar o toque
           GestureDetector(
             onTap: () {
               _chewieController?.enterFullScreen();
               _controller.play(); // Auto-play ao entrar em fullscreen
             },
             child: Container(
               color: Colors.transparent,
               child: Center(
                 child: Container(
                   padding: const EdgeInsets.all(12),
                   decoration: BoxDecoration(
                     color: Colors.black.withValues(alpha: 0.5),
                     shape: BoxShape.circle,
                   ),
                   child: const Icon(
                     LucideIcons.play,
                     color: Colors.white,
                     size: 32,
                   ),
                 ),
               ),
             ),
           ),
        ],
      ),
    );
  }
}
