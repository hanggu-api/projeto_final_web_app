import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/realtime_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/file_bytes.dart';
import '../../utils/audio_recorder.dart';

class ChatScreen extends StatefulWidget {
  final String serviceId;
  const ChatScreen({super.key, required this.serviceId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _api = ApiService();
  final _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _messages = [];
  Timer? _pollingTimer;
  Map<String, dynamic>? _serviceDetails;
  int? _myUserId;
  final AudioRecorder _rec = AudioRecorder();
  bool _isRecording = false;
  DateTime? _recordStartAt;
  Timer? _recordTicker;
  final Map<String, Future<Uint8List>> _imageFutureCache = {};
  // REMOVIDO: final GlobalKey _quickRepliesKey = GlobalKey();
  final GlobalKey _inputAreaKey = GlobalKey();
  
  // Valor inicial ajustado para a altura de apenas a área de input (aprox. 80)
  double _bottomPadding = 80; 

  Future<Uint8List> _fetchImageBytesCached(String key) {
    return _imageFutureCache.putIfAbsent(key, () => _api.getMediaBytes(key));
  }

  @override
  void initState() {
    super.initState();
    _api.getMyUserId().then((id) => _myUserId = id);
    _loadServiceInfo();
    _loadMessages();
    final rt = RealtimeService();
    rt.connect();
    rt.joinService(widget.serviceId);
    rt.on('chat.message', (data) {
      if (mounted) {
        setState(() => _messages.add(data));
        _scrollToBottom();
      }
      final t = (data['type'] ?? 'text').toString();
      if (t == 'image' || t == 'audio') {
        final key = data['content'];
        if (key is String) {
          _api.getMediaBytes(key); // warm cache
        }
      }
      final senderId = data is Map<String, dynamic> ? data['sender_id'] : null;
      if (_myUserId != null && senderId != _myUserId) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nova mensagem')));
        }
        SharedPreferences.getInstance().then((p) async {
          final curr = p.getInt('unread_chat_count') ?? 0;
          await p.setInt('unread_chat_count', curr + 1);
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateBottomPadding());
    SharedPreferences.getInstance().then((p) => p.setInt('unread_chat_count', 0));
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadServiceInfo() async {
    try {
      final details = await _api.getServiceDetails(widget.serviceId);
      if (mounted) setState(() => _serviceDetails = details);
    } catch (_) {}
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await _api.getChatMessages(widget.serviceId);
      if (mounted) {
        setState(() => _messages = msgs);
        if (_messages.isNotEmpty) {
          _scrollToBottom();
        }
      }
    } catch (_) {}
  }

  Future<void> _sendMessage({String? content}) async {
    final text = content ?? _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    try {
      await _api.sendMessage(widget.serviceId, text);
      _loadMessages();
      _scrollToBottom();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao enviar: $e')));
    }
  }

  Future<void> _sendImage() async {
    // Web/Desktop: usar FilePicker
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (res != null && res.files.isNotEmpty && res.files.first.bytes != null) {
        final f = res.files.first;
        final key = await _api.uploadChatImage(widget.serviceId, f.bytes!, filename: f.name);
        await _api.sendMessage(widget.serviceId, key, type: 'image');
        await _loadMessages();
        _scrollToBottom();
        return;
      }
    } catch (_) {}
    // Mobile: ImagePicker
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
      if (xfile != null) {
        final bytes = await xfile.readAsBytes();
        final key = await _api.uploadChatImage(widget.serviceId, bytes, filename: xfile.name);
        await _api.sendMessage(widget.serviceId, key, type: 'image');
        await _loadMessages();
        _scrollToBottom();
      }
    } catch (_) {}
  }
  Future<void> _toggleRecord() async {
    try {
      if (!_isRecording) {
        final has = await _rec.hasPermission();
        if (!has) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permissão de microfone negada')));
          return;
        }
        await _rec.start();
        setState(() {
          _isRecording = true;
          _recordStartAt = DateTime.now();
          _recordTicker?.cancel();
          _recordTicker = Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          });
        });
      } else {
        final path = await _rec.stop();
        setState(() {
          _isRecording = false;
          _recordTicker?.cancel();
        });
        if (path == null) return;
        final bytes = await readFileBytes(path);
        String mime;
        String filename;
        if (kIsWeb) {
          mime = 'audio/webm';
          filename = 'audio.webm';
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
        final key = await _api.uploadChatAudio(widget.serviceId, bytes, filename: filename, mimeType: mime);
        await _api.sendMessage(widget.serviceId, key, type: 'audio');
        await _loadMessages();
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro de gravação: $e')));
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final max = _scrollController.position.maxScrollExtent;
        _scrollController.animateTo(
          max,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
        Future.delayed(const Duration(milliseconds: 350), () {
          if (_scrollController.hasClients) {
            final max2 = _scrollController.position.maxScrollExtent;
            _scrollController.jumpTo(max2);
          }
        });
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
    if (_serviceDetails == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    
    final name = _serviceDetails!['client_name'] ?? 'Cliente';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
             CircleAvatar(
              backgroundColor: AppTheme.secondaryOrange,
              radius: 16,
              backgroundImage: _serviceDetails!['client_avatar'] != null ? NetworkImage(_serviceDetails!['client_avatar']) : null,
              child: _serviceDetails!['client_avatar'] == null ? Text(name[0], style: const TextStyle(color: Colors.white)) : null,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 16)),
                Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.successGreen, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    const Text('Online', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages Area
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              // O padding inferior usa o _bottomPadding calculado com base na altura da área de input
              padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: _bottomPadding), 
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = _myUserId != null && msg['sender_id'] == _myUserId;
                final type = (msg['type'] ?? 'text').toString();
                
                final ts = (msg['created_at'] ?? msg['sent_at'])?.toString();
                final time = ts != null && ts.length >= 16 ? ts.substring(11, 16) : 'Agora';
                return _buildMessageBubble(
                  msg['content'],
                  type,
                  isMe,
                  time,
                );
              },
            ),
          ),
          
          // REMOVIDO: Quick Replies Container (Bloco de código removido)
          
          // Input Area
          Container(
            key: _inputAreaKey,
            // AJUSTE: Adiciona o padding inferior da área segura diretamente no Container de Input.
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + MediaQuery.of(context).padding.bottom), 
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, -2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(icon: const Icon(LucideIcons.image), onPressed: _sendImage),
                    IconButton(icon: Icon(_isRecording ? LucideIcons.stopCircle : LucideIcons.mic), onPressed: _toggleRecord),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Digite uma mensagem...',
                          filled: true,
                          fillColor: Colors.grey[100],
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: const BoxDecoration(color: AppTheme.primaryPurple, shape: BoxShape.circle),
                      child: IconButton(
                        icon: const Icon(LucideIcons.send, color: Colors.white, size: 20),
                        onPressed: () => _sendMessage(),
                      ),
                    ),
                  ],
                ),
                if (_isRecording) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.mic, color: Colors.redAccent, size: 18),
                        const SizedBox(width: 8),
                        Text('Gravando… ${_formatElapsed()}', style: const TextStyle(color: Colors.redAccent)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _toggleRecord,
                          icon: const Icon(LucideIcons.stopCircle, color: Colors.redAccent, size: 18),
                          label: const Text('Parar', style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
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

  Widget _buildMessageBubble(String content, String type, bool isMe, String time) {
    final isImage = type == 'image';
    Widget bubbleChild;
    if (isImage) {
      bubbleChild = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FutureBuilder<Uint8List>(
          future: _fetchImageBytesCached(content),
          builder: (context, snap) {
            if (!snap.hasData) {
              return Container(width: 220, height: 140, color: Colors.black12);
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToBottom();
            });
            return Image.memory(snap.data!, width: 220, fit: BoxFit.cover, gaplessPlayback: true);
          },
        ),
      );
    } else if (type == 'audio') {
      bubbleChild = AudioBubble(mediaKey: content, api: _api, isMe: isMe);
    } else {
      bubbleChild = Text(content, style: TextStyle(color: isMe ? Colors.white : Colors.black87));
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: isImage ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: isImage ? null : const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: isImage ? Colors.transparent : (isMe ? AppTheme.primaryPurple : Colors.white),
          borderRadius: isImage
              ? BorderRadius.zero
              : BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                  bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                ),
          boxShadow: isImage ? [] : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            bubbleChild,
            const SizedBox(height: 4),
            Text(
              time,
              style: TextStyle(color: isImage ? Colors.grey[700] : (isMe ? Colors.white70 : Colors.grey), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
  // REMOVIDO: Widget _buildQuickReply(String text) { ... }
}

// AudioBubble e _AudioBubbleState permanecem inalterados.
// ... (código do AudioBubble)

class AudioBubble extends StatefulWidget {
  final String mediaKey;
  final ApiService api;
  final bool isMe;
  const AudioBubble({super.key, required this.mediaKey, required this.api, required this.isMe});

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _loadingUrl = true;
  Uint8List? _bytes;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    widget.api.getMediaBytes(widget.mediaKey).then((b) {
      if (!mounted) return;
      setState(() {
        _bytes = b;
        _loadingUrl = false;
      });
    });
    _player.onPlayerComplete.listen((_) => setState(() { _playing = false; }));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_loadingUrl || _bytes == null) return;
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
    } else {
      await _player.play(BytesSource(_bytes!));
      setState(() => _playing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isMe ? Colors.white : Colors.black87;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow, color: color),
          onPressed: _togglePlay,
        ),
        const SizedBox(width: 8),
        if (_loadingUrl)
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color))
        else
          Text('Áudio', style: TextStyle(color: color)),
      ],
    );
  }
}