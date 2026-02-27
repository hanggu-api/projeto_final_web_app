import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';

import 'chat/chat_state.dart';
import 'chat/mixins/chat_actions_mixin.dart';
import 'chat/mixins/chat_media_mixin.dart';
import 'chat/widgets/audio_bubble.dart';
import 'chat/widgets/video_message_bubble.dart';
import 'widgets/schedule_proposal_bubble.dart';

import '../../core/theme/app_theme.dart';
import '../../services/realtime_service.dart';
import '../../services/data_gateway.dart';
import '../../widgets/app_bottom_nav.dart';
import '../../widgets/user_avatar.dart';

class ChatScreen extends StatefulWidget {
  final String serviceId;
  final String? otherName;
  final String? otherAvatar;

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

class _ChatScreenState extends State<ChatScreen>
    with ChatStateMixin<ChatScreen>, ChatActionsMixin<ChatScreen>, ChatMediaMixin<ChatScreen> {
  
  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => role = prefs.getString('user_role'));
    }

    final id = await api.getMyUserId();
    if (mounted) setState(() => myUserId = id);
    if (id != null) {
      RealtimeService().authenticate(id);
    }

    await loadServiceInfo(widget.serviceId, () => calculateOtherUser((targetId, callback) {
      RealtimeService().checkStatus(targetId, callback);
    }));

    RealtimeService().connect();

    debugPrint('[IMPORTANT] Starting signal-based chat subscription for service ${widget.serviceId}');
    chatSubscription = DataGateway().watchChat(widget.serviceId).listen((msgs) {
      final sortedMsgs = List<dynamic>.from(msgs);
      sortedMsgs.sort((a, b) => parseMessageDate(b).compareTo(parseMessageDate(a)));

      if (mounted) {
        setState(() {
           messages = sortedMsgs;
           reconcilePendingMessages();
        });
        if (scrollController.hasClients && scrollController.offset < 100) {
          scrollToBottom();
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => updateBottomPadding());
    unawaited(SharedPreferences.getInstance().then((p) => p.setInt('unread_chat_count', 0)));
    ChatScreen.activeChatServiceId = widget.serviceId;
  }

  @override
  void dispose() {
    if (ChatScreen.activeChatServiceId == widget.serviceId) {
      ChatScreen.activeChatServiceId = null;
    }
    RealtimeService().leaveService();
    disposeChatState();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (serviceDetails == null || myUserId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final s = serviceDetails!;
    bool isMeClient = role == 'client';
    if (role == null) {
      final myIdStr = myUserId.toString();
      dynamic userIdRaw = s['user_id'] ?? (s['client'] is Map ? s['client']['id'] : null);
      isMeClient = userIdRaw?.toString() == myIdStr;
    }

    String otherName;
    String? otherAvatar;
    int? otherId;

    if (isMeClient) {
      otherName = s['provider_name']?.toString() ?? s['professional_name']?.toString() ?? (s['provider'] is Map ? s['provider']['name']?.toString() : null) ?? widget.otherName ?? 'Prestador';
      otherAvatar = s['provider_avatar']?.toString() ?? s['professional_avatar']?.toString() ?? s['provider_photo']?.toString() ?? s['provider_image']?.toString() ?? (s['provider'] is Map ? (s['provider']['avatar']?.toString() ?? s['provider']['photo']?.toString()) : null) ?? widget.otherAvatar;
      otherId = otherUserId;
    } else {
      otherName = s['client_name']?.toString() ?? s['user_name']?.toString() ?? (s['client'] is Map ? s['client']['name']?.toString() : null) ?? widget.otherName ?? 'Cliente';
      otherAvatar = s['client_avatar']?.toString() ?? s['user_avatar']?.toString() ?? (s['client'] is Map ? (s['client']['avatar']?.toString() ?? s['client']['photo']?.toString()) : null) ?? widget.otherAvatar;
      otherId = otherUserId;
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.9),
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppTheme.textDark),
        title: Row(
          children: [
            UserAvatar(avatar: otherAvatar, name: otherName, userId: otherId, showOnlineStatus: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(otherName, style: GoogleFonts.manrope(fontSize: 15, color: AppTheme.textDark, fontWeight: FontWeight.w800)),
                  Row(
                    children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: isOtherOnline ? AppTheme.successGreen : Colors.grey.shade400, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(isOtherOnline ? 'Online agora' : 'Offline', style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(LucideIcons.phone, size: 20), onPressed: () {}),
          IconButton(icon: const Icon(LucideIcons.moreVertical, size: 20), onPressed: () {}),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Scrollbar(
                  controller: scrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: scrollController,
                    reverse: true, 
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    itemCount: messages.length + pendingMessages.length,
                    itemBuilder: (context, index) {
                      bool isPending = false;
                      Map<String, dynamic> msg;
                      dynamic localContent;

                      if (index < pendingMessages.length) {
                         isPending = true;
                         msg = pendingMessages[pendingMessages.length - 1 - index];
                         localContent = msg['localContent'];
                      } else {
                         msg = messages[index - pendingMessages.length];
                      }

                      final senderIdRaw = msg['sender_id'];
                      final isMe = isPending ? true : (myUserId != null && senderIdRaw.toString() == myUserId.toString());
                      final type = (msg['type'] ?? 'text').toString();
                      final ts = (msg['created_at'] ?? msg['sent_at'])?.toString();
                      String time = 'Agora';
                      
                      if (ts != null) {
                        try {
                          final date = DateTime.tryParse(ts);
                          if (date != null) time = DateFormat('HH:mm').format(date.toLocal());
                        } catch (_) {}
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
                key: inputAreaKey,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (messages.isEmpty && pendingMessages.isEmpty)
                       Padding(
                         padding: const EdgeInsets.only(bottom: 16),
                         child: Row(
                           children: [
                             _buildActionChip('Agendar visita', LucideIcons.calendar),
                             const SizedBox(width: 8),
                             _buildActionChip('Pedir orçamento', LucideIcons.fileText),
                           ],
                         ),
                       ),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => openUnifiedCamera(widget.serviceId, scrollToBottom),
                          child: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(color: AppTheme.backgroundLight, borderRadius: BorderRadius.circular(12)),
                            child: const Icon(LucideIcons.plus, color: AppTheme.textDark, size: 20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: messageController,
                            minLines: 1, maxLines: 4,
                            style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600),
                            decoration: InputDecoration(
                              hintText: 'Escreva sua mensagem...',
                              hintStyle: GoogleFonts.manrope(color: Colors.grey.shade400, fontSize: 14),
                              filled: true, fillColor: AppTheme.backgroundLight.withOpacity(0.5),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => toggleRecord(widget.serviceId, scrollToBottom),
                          child: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(color: isRecording ? Colors.red.withOpacity(0.1) : AppTheme.backgroundLight, borderRadius: BorderRadius.circular(12)),
                            child: Icon(isRecording ? LucideIcons.stopCircle : LucideIcons.mic, color: isRecording ? Colors.red : AppTheme.textDark, size: 20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () => sendMessage(widget.serviceId),
                          child: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(color: AppTheme.primaryYellow, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: AppTheme.primaryYellow.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]),
                            child: const Icon(LucideIcons.send, color: AppTheme.textDark, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isRecording)
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
          
          if (isUploading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text('Enviando $uploadingType...', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
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
    if (recordStartAt == null) return '00:00';
    final d = DateTime.now().difference(recordStartAt!);
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  void _openImageModal(Uint8List bytes) {
    showDialog(context: context, builder: (ctx) => Dialog(backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.all(12), child: GestureDetector(onTap: () => Navigator.of(ctx).pop(), child: InteractiveViewer(child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(bytes, fit: BoxFit.contain))))));
  }

  void _openImageUrlModal(String url) {
    showDialog(context: context, builder: (ctx) => Dialog(backgroundColor: Colors.transparent, insetPadding: const EdgeInsets.all(12), child: GestureDetector(onTap: () => Navigator.of(ctx).pop(), child: InteractiveViewer(child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(url, fit: BoxFit.contain))))));
  }

  Widget _buildActionChip(String label, IconData icon) {
    return GestureDetector(
      onTap: () {
        if (label == 'Agendar visita') {
          final now = DateTime.now().add(const Duration(hours: 24));
          DataGateway().sendChatMessage(widget.serviceId, jsonEncode({'date': now.toIso8601String()}), 'schedule_proposal');
        } else {
          sendMessage(widget.serviceId, content: 'Gostaria de pedir um orçamento para este serviço.');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.primaryYellow),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(String content, String type, bool isMe, String time, {bool isPending = false, dynamic localContent}) {
    final isImage = type == 'image';
    Widget bubbleChild;
    if (isImage) {
      Widget imageWidget;
      if (isPending && localContent != null) {
        if (kIsWeb) {
             Uint8List? bytes = localContent is Uint8List ? localContent : null;
             imageWidget = bytes != null ? Image.memory(bytes, width: 220, fit: BoxFit.cover) : Container(width: 220, height: 140, color: Colors.grey);
        } else {
             imageWidget = localContent is XFile ? Image.file(File(localContent.path), width: 220, fit: BoxFit.cover) : Container(width: 220, height: 140, color: Colors.grey);
        }
      } else {
        imageWidget = content.startsWith('http') 
          ? GestureDetector(onTap: () => _openImageUrlModal(content), child: Image.network(content, width: 220, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54), loadingBuilder: (_, child, prog) => prog == null ? child : Container(width: 220, height: 140, color: Colors.black12, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)))))
          : FutureBuilder<Uint8List>(future: fetchImageBytesCached(content), builder: (context, snap) => snap.hasData ? GestureDetector(onTap: () => _openImageModal(snap.data!), child: Image.memory(snap.data!, width: 220, fit: BoxFit.cover, gaplessPlayback: true)) : Container(width: 220, height: 140, color: Colors.black12));
      }
      bubbleChild = ClipRRect(borderRadius: BorderRadius.circular(12), child: isPending ? Stack(alignment: Alignment.center, children: [ColorFiltered(colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.4), BlendMode.darken), child: imageWidget), const CircularProgressIndicator(color: Colors.white)]) : imageWidget);
    } else if (type == 'video') {
      bubbleChild = VideoMessageBubble(videoUrl: content, isMe: isMe);
    } else if (type == 'audio') {
      bubbleChild = AudioBubble(mediaKey: content, api: api, isMe: isMe);
    } else if (type == 'schedule_proposal') {
      DateTime? schDate;
      try { final m = jsonDecode(content); if (m['date'] != null) schDate = DateTime.parse(m['date']).toLocal(); } catch (_) {}
      bubbleChild = schDate != null ? ScheduleProposalBubble(scheduledDate: schDate, isMe: isMe, showAction: role == 'client', onConfirm: () => confirmSchedule(widget.serviceId, schDate!)) : const Text('Proposta inválida.');
    } else {
      bubbleChild = Text(content, style: const TextStyle(color: Colors.black87, fontSize: 15));
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: isImage ? const EdgeInsets.all(4) : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isImage ? Colors.transparent : (isMe ? const Color(0xFFE0E7FF) : Colors.white),
          borderRadius: BorderRadius.only(topLeft: const Radius.circular(20), topRight: const Radius.circular(20), bottomLeft: isMe ? const Radius.circular(20) : Radius.zero, bottomRight: isMe ? Radius.zero : const Radius.circular(20)),
          border: isMe ? Border.all(color: const Color(0xFFC7D2FE).withOpacity(0.5)) : Border.all(color: Colors.grey.shade100),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [bubbleChild, const SizedBox(height: 2), Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [Text(time, style: TextStyle(color: Colors.grey[600], fontSize: 10)), if (isMe) ...[const SizedBox(width: 4), const Icon(LucideIcons.checkCheck, size: 14, color: Colors.blueAccent)]])]),
      ),
    );
  }
}
