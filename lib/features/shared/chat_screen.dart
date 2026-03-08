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
  final bool isInline;
  final VoidCallback? onClose;

  const ChatScreen({
    super.key,
    required this.serviceId,
    this.otherName,
    this.otherAvatar,
    this.isInline = false,
    this.onClose,
  });

  static String? activeChatServiceId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with
        ChatStateMixin<ChatScreen>,
        ChatActionsMixin<ChatScreen>,
        ChatMediaMixin<ChatScreen> {
  double _inlineHeight() {
    final totalMessages = messages.length + pendingMessages.length;
    const baseHeight = 260.0;
    const perMessageGrowth = 44.0;
    final rawHeight = baseHeight + (totalMessages * perMessageGrowth);
    final maxHeight =
        MediaQuery.of(context).size.height -
        MediaQuery.of(context).padding.top -
        12;
    return rawHeight.clamp(baseHeight, maxHeight).toDouble();
  }

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    debugPrint(
      '[ChatScreen] _initChat starting for service: ${widget.serviceId}',
    );
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      final storedRole = prefs.getString('user_role');
      debugPrint('[ChatScreen] Stored role: $storedRole');
      setState(() => role = storedRole);
    }

    var id = await api.getMyUserId();
    debugPrint('[ChatScreen] getMyUserId returned: $id');

    if (id == null) {
      debugPrint(
        '[ChatScreen] WARNING: myUserId is null from getMyUserId. Checking api.userId cache.',
      );
      id = api.userId; // Fallback to memory cache
      debugPrint('[ChatScreen] api.userId cache: $id');
    }

    if (mounted) setState(() => myUserId = id);
    if (id != null) {
      debugPrint('[ChatScreen] Authenticating RealtimeService with: $id');
      RealtimeService().authenticate(id);
    }

    debugPrint('[ChatScreen] Calling loadServiceInfo...');
    await loadServiceInfo(widget.serviceId, () {
      debugPrint(
        '[ChatScreen] loadServiceInfo callback - calculating other user',
      );
      calculateOtherUser((targetId, callback) {
        RealtimeService().checkStatus(targetId, callback);
      });
    });
    debugPrint(
      '[ChatScreen] loadServiceInfo finished. serviceDetails: ${serviceDetails != null}',
    );

    RealtimeService().connect();

    debugPrint(
      '[IMPORTANT] Starting signal-based chat subscription for service ${widget.serviceId}',
    );
    chatSubscription = DataGateway().watchChat(widget.serviceId).listen((msgs) {
      debugPrint('[ChatScreen] Received ${msgs.length} messages from stream');
      final previousCount = messages.length;
      final sortedMsgs = List<dynamic>.from(msgs);
      sortedMsgs.sort(
        (a, b) => parseMessageDate(b).compareTo(parseMessageDate(a)),
      );

      if (mounted) {
        setState(() {
          messages = sortedMsgs;
          reconcilePendingMessages();
        });
        if (sortedMsgs.length != previousCount) {
          scrollToBottom();
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => updateBottomPadding());
    debugPrint('[ChatScreen] _initChat complete');
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
    debugPrint(
      '[ChatScreen] Building ChatScreen - isInline: ${widget.isInline}, serviceId: ${widget.serviceId}',
    );
    debugPrint(
      '[ChatScreen] myUserId: $myUserId, serviceDetails: ${serviceDetails != null}',
    );

    if (serviceDetails == null || myUserId == null) {
      debugPrint(
        '[ChatScreen] serviceDetails or myUserId is null. Showing loader.',
      );

      // Mostrar info de debug se estiver demorando muito
      return Container(
        height: widget.isInline
            ? 350
            : MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: AppTheme.backgroundLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Carregando mensagens...',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: AppTheme.textMuted,
                ),
              ),
              if (myUserId == null) ...[
                const SizedBox(height: 8),
                Text(
                  'Aviso: Usuário não identificado',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: Colors.orange,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  debugPrint('[ChatScreen] Manual retry triggered');
                  _initChat();
                },
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    final s = serviceDetails!;
    bool isMeClient = role == 'client';
    if (role == null) {
      final myIdStr = myUserId.toString();
      dynamic userIdRaw =
          s['user_id'] ?? (s['client'] is Map ? s['client']['id'] : null);
      isMeClient = userIdRaw?.toString() == myIdStr;
    }

    String otherName = 'Usuário';
    String? otherAvatar;
    int? otherId;

    if (isMeClient) {
      // Tentar pegar do provider ou motorista
      otherName =
          s['provider_name']?.toString() ??
          s['professional_name']?.toString() ??
          (s['providers'] is Map && s['providers']['users'] is Map
              ? s['providers']['users']['full_name']?.toString()
              : null) ??
          (s['provider'] is Map ? s['provider']['name']?.toString() : null) ??
          widget.otherName ??
          'Motorista / Prestador';

      otherAvatar =
          s['provider_avatar']?.toString() ??
          s['professional_avatar']?.toString() ??
          s['provider_photo']?.toString() ??
          s['provider_image']?.toString() ??
          (s['providers'] is Map && s['providers']['users'] is Map
              ? s['providers']['users']['avatar_url']?.toString()
              : null) ??
          (s['provider'] is Map
              ? (s['provider']['avatar']?.toString() ??
                    s['provider']['photo']?.toString())
              : null) ??
          widget.otherAvatar;
      otherId = otherUserId;
    } else {
      // Tentar pegar do client ou passageiro
      otherName =
          s['client_name']?.toString() ??
          s['user_name']?.toString() ??
          (s['users'] is Map ? s['users']['full_name']?.toString() : null) ??
          (s['client'] is Map ? s['client']['name']?.toString() : null) ??
          widget.otherName ??
          'Passageiro / Cliente';

      otherAvatar =
          s['client_avatar']?.toString() ??
          s['user_avatar']?.toString() ??
          (s['users'] is Map ? s['users']['avatar_url']?.toString() : null) ??
          (s['client'] is Map
              ? (s['client']['avatar']?.toString() ??
                    s['client']['photo']?.toString())
              : null) ??
          widget.otherAvatar;
      otherId = otherUserId;
    }

    final chatBody = _buildChatBody(otherName);

    if (widget.isInline) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        height: _inlineHeight(),
        decoration: BoxDecoration(
          color: AppTheme.backgroundLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      otherName,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        color: AppTheme.textDark,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.onClose != null)
                    GestureDetector(
                      onTap: widget.onClose,
                      child: const Icon(
                        LucideIcons.x,
                        size: 20,
                        color: AppTheme.textDark,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: chatBody),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white.withValues(alpha: 0.9),
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppTheme.textDark),
        title: Row(
          children: [
            UserAvatar(
              avatar: otherAvatar,
              name: otherName,
              userId: otherId,
              showOnlineStatus: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    otherName,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      color: AppTheme.textDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isOtherOnline
                              ? AppTheme.successGreen
                              : Colors.grey.shade400,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isOtherOnline ? 'Online agora' : 'Offline',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: chatBody,
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }

  Widget _buildChatBody(String otherName) {
    return Stack(
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
                  padding: EdgeInsets.only(
                    left: widget.isInline ? 4 : 16,
                    right: widget.isInline ? 4 : 16,
                    top: 10,
                    bottom: widget.isInline ? 120 : 180, // Space for InputArea
                  ),
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
                    final isMe = isPending
                        ? true
                        : (myUserId != null &&
                              senderIdRaw.toString() == myUserId.toString());
                    final type = (msg['type'] ?? 'text').toString();
                    final ts = (msg['created_at'] ?? msg['sent_at'])
                        ?.toString();
                    String time = 'Agora';

                    if (ts != null) {
                      try {
                        final date = DateTime.tryParse(ts);
                        if (date != null) {
                          time = DateFormat('HH:mm').format(date.toLocal());
                        }
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
          ],
        ),

        // Input Area explicitly aligned to bottom
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            key: inputAreaKey,
            padding: EdgeInsets.fromLTRB(
              widget.isInline ? 4 : 20,
              12,
              widget.isInline ? 4 : 20,
              widget.isInline ? 12 : 32,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (messages.isEmpty && pendingMessages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        _buildActionChip(
                          'Estou indo',
                          LucideIcons.messageSquare,
                        ),
                        const SizedBox(width: 8),
                        _buildActionChip(
                          'Espere mais 1 minuto',
                          LucideIcons.clock3,
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () =>
                          openUnifiedCamera(widget.serviceId, scrollToBottom),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          LucideIcons.plus,
                          color: AppTheme.textDark,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: messageController,
                        minLines: 1,
                        maxLines: 4,
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Escreva sua mensagem...',
                          hintStyle: GoogleFonts.manrope(
                            color: Colors.grey.shade400,
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: AppTheme.backgroundLight.withValues(
                            alpha: 0.5,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () =>
                          toggleRecord(widget.serviceId, scrollToBottom),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isRecording
                              ? Colors.red.withValues(alpha: 0.1)
                              : AppTheme.backgroundLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isRecording
                              ? LucideIcons.stopCircle
                              : LucideIcons.mic,
                          color: isRecording ? Colors.red : AppTheme.textDark,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => sendMessage(widget.serviceId),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryYellow,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryYellow.withValues(
                                alpha: 0.3,
                              ),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          LucideIcons.send,
                          color: AppTheme.textDark,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
        if (isUploading)
          Container(
            color: Colors.black12,
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
                      'Enviando $uploadingType...',
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
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
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: InteractiveViewer(
            maxScale: 3.0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(bytes, fit: BoxFit.contain, cacheWidth: 800),
            ),
          ),
        ),
      ),
    );
  }

  void _openImageUrlModal(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: InteractiveViewer(
            maxScale: 3.0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(url, fit: BoxFit.contain, cacheWidth: 800),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionChip(String label, IconData icon) {
    return GestureDetector(
      onTap: () {
        sendMessage(widget.serviceId, content: label);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.primaryYellow),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
              ),
            ),
          ],
        ),
      ),
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
        if (kIsWeb) {
          Uint8List? bytes = localContent is Uint8List ? localContent : null;
          imageWidget = bytes != null
              ? Image.memory(bytes, width: 220, fit: BoxFit.cover)
              : Container(width: 220, height: 140, color: Colors.grey);
        } else {
          imageWidget = localContent is XFile
              ? Image.file(
                  File(localContent.path),
                  width: 220,
                  fit: BoxFit.cover,
                )
              : Container(width: 220, height: 140, color: Colors.grey);
        }
      } else {
        imageWidget = content.startsWith('http')
            ? GestureDetector(
                onTap: () => _openImageUrlModal(content),
                child: Image.network(
                  content,
                  width: 220,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image, color: Colors.white54),
                  loadingBuilder: (_, child, prog) => prog == null
                      ? child
                      : Container(
                          width: 220,
                          height: 140,
                          color: Colors.black12,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                ),
              )
            : FutureBuilder<Uint8List>(
                future: fetchImageBytesCached(content),
                builder: (context, snap) => snap.hasData
                    ? GestureDetector(
                        onTap: () => _openImageModal(snap.data!),
                        child: Image.memory(
                          snap.data!,
                          width: 220,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      )
                    : Container(width: 220, height: 140, color: Colors.black12),
              );
      }
      bubbleChild = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: isPending
            ? Stack(
                alignment: Alignment.center,
                children: [
                  imageWidget,
                  Container(
                    width: 220,
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const CircularProgressIndicator(color: Colors.white),
                ],
              )
            : imageWidget,
      );
    } else if (type == 'video') {
      bubbleChild = VideoMessageBubble(videoUrl: content, isMe: isMe);
    } else if (type == 'audio') {
      bubbleChild = AudioBubble(mediaKey: content, api: api, isMe: isMe);
    } else if (type == 'schedule_proposal') {
      DateTime? schDate;
      try {
        final m = jsonDecode(content);
        if (m['date'] != null) schDate = DateTime.parse(m['date']).toLocal();
      } catch (_) {}
      bubbleChild = schDate != null
          ? ScheduleProposalBubble(
              scheduledDate: schDate,
              isMe: isMe,
              showAction: role == 'client',
              onConfirm: () => confirmSchedule(widget.serviceId, schDate!),
            )
          : const Text('Proposta inválida.');
    } else {
      bubbleChild = Text(
        content,
        style: const TextStyle(color: Colors.black87, fontSize: 15),
      );
    }

    return RepaintBoundary(
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: isImage
              ? const EdgeInsets.all(4)
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * (widget.isInline ? 0.96 : 0.75),
          ),
          decoration: BoxDecoration(
            color: isImage
                ? Colors.transparent
                : (isMe ? const Color(0xFFE0E7FF) : Colors.white),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: isMe ? const Radius.circular(20) : Radius.zero,
              bottomRight: isMe ? Radius.zero : const Radius.circular(20),
            ),
            border: isMe
                ? Border.all(
                    color: const Color(0xFFC7D2FE).withValues(alpha: 0.5),
                  )
                : Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
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
                    style: TextStyle(color: Colors.grey[600], fontSize: 10),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      LucideIcons.checkCheck,
                      size: 14,
                      color: Colors.blueAccent,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
