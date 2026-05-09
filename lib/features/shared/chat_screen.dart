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
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chat/chat_state.dart';
import 'chat/mixins/chat_actions_mixin.dart';
import 'chat/mixins/chat_media_mixin.dart';
import 'chat/widgets/audio_bubble.dart';
import 'chat/widgets/video_message_bubble.dart';
import 'widgets/schedule_proposal_bubble.dart';

import '../../core/theme/app_theme.dart';
import '../../services/realtime_service.dart';
import '../../services/data_gateway.dart';
import '../../widgets/user_avatar.dart';

class ChatScreen extends StatefulWidget {
  final String serviceId;
  final String? otherName;
  final String? otherAvatar;
  final List<Map<String, dynamic>> initialParticipants;
  final String? participantContextLabelOverride;
  final bool isInline;
  final VoidCallback? onClose;
  final bool showComposer;

  const ChatScreen({
    super.key,
    required this.serviceId,
    this.otherName,
    this.otherAvatar,
    this.initialParticipants = const [],
    this.participantContextLabelOverride,
    this.isInline = false,
    this.onClose,
    this.showComposer = true,
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
  static const String _navigationPreferenceKey =
      'chat_preferred_navigation_app';

  int _initVersion = 0;
  int? _lastMarkedReadMessageId;
  String? _preferredNavigationAppId;
  List<_NavigationAppOption> _availableNavigationApps = [];
  bool _isAttachmentMenuOpen = false;

  bool get _hasMessages =>
      messages.isNotEmpty || pendingMessages.isNotEmpty || isUploading;

  List<({String label, IconData icon})> _quickReplies() {
    final isClient = role == 'client';
    if (isClient) {
      return const [
        (label: 'Estou chegando', icon: LucideIcons.mapPin),
        (label: 'Pode me confirmar o local?', icon: LucideIcons.map),
        (label: 'Vou me atrasar alguns minutos', icon: LucideIcons.clock3),
      ];
    }
    return const [
      (label: 'Estou indo', icon: LucideIcons.messageSquare),
      (label: 'Espere mais 1 minuto', icon: LucideIcons.clock3),
      (label: 'Já estou no local', icon: LucideIcons.badgeCheck),
    ];
  }

  String _emptyStateTitle() {
    return role == 'client' ? 'Fale com o prestador' : 'Fale com o cliente';
  }

  String _emptyStateSubtitle(String otherName) {
    if (role == 'client') {
      return 'Use esta conversa para combinar detalhes com $otherName, confirmar chegada ou avisar qualquer ajuste no atendimento.';
    }
    return 'Use esta conversa para orientar $otherName, avisar sobre chegada e alinhar detalhes do atendimento.';
  }

  String? _participantContextLabel() {
    if (widget.participantContextLabelOverride != null &&
        widget.participantContextLabelOverride!.trim().isNotEmpty) {
      return widget.participantContextLabelOverride!.trim();
    }
    if (chatParticipants.isEmpty) return null;
    final beneficiary = chatParticipants
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (item) => item?['role'] == 'beneficiary',
          orElse: () => null,
        );
    final requester = chatParticipants.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['role'] == 'requester',
      orElse: () => null,
    );
    if (beneficiary == null) return null;
    final beneficiaryName = '${beneficiary['display_name'] ?? ''}'.trim();
    if (beneficiaryName.isEmpty) return null;
    final requesterId = '${requester?['user_id'] ?? ''}'.trim();
    final beneficiaryId = '${beneficiary['user_id'] ?? ''}'.trim();
    if (requesterId.isNotEmpty && requesterId == beneficiaryId) return null;
    if (role == 'provider') {
      return 'Atendimento para $beneficiaryName';
    }
    return 'Pessoa atendida: $beneficiaryName';
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialParticipants.isNotEmpty) {
      chatParticipants = widget.initialParticipants
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    _clearUnreadBadge();
    _initChat();
  }

  Future<void> _clearUnreadBadge() async {
    await DataGateway().loadUnreadChatCount();
  }

  Future<void> _initChat() async {
    final initRun = ++_initVersion;
    debugPrint(
      '[ChatScreen] _initChat starting for service: ${widget.serviceId}',
    );
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || initRun != _initVersion) return;
    final storedRole = prefs.getString('user_role');
    final preferredApp = prefs.getString(_navigationPreferenceKey);
    debugPrint('[ChatScreen] Stored role: $storedRole');
    debugPrint('[ChatScreen] Preferred navigation app ID: $preferredApp');
    setState(() {
      role = storedRole;
      if (preferredApp != null) {
        _preferredNavigationAppId = preferredApp;
      }
    });

    if (chatParticipants.isEmpty) {
      final cachedParticipants = await DataGateway()
          .loadChatParticipantsSnapshot(widget.serviceId);
      if (!mounted || initRun != _initVersion) return;
      if (cachedParticipants.isNotEmpty) {
        setState(() {
          chatParticipants = cachedParticipants;
        });
      }

      if (chatParticipants.isEmpty) {
        final remoteParticipants = await DataGateway()
            .loadChatParticipantsRemote(widget.serviceId);
        if (!mounted || initRun != _initVersion) return;
        if (remoteParticipants.isNotEmpty) {
          setState(() {
            chatParticipants = remoteParticipants;
          });
          unawaited(
            DataGateway().saveChatParticipantsSnapshot(
              widget.serviceId,
              remoteParticipants,
            ),
          );
        }
      }
    }

    String? id = (await api.getMyUserId())?.toString();
    if (!mounted || initRun != _initVersion) return;
    debugPrint('[ChatScreen] getMyUserId returned: $id');

    if (id == null) {
      debugPrint(
        '[ChatScreen] WARNING: myUserId is null from getMyUserId. Checking api.userId cache.',
      );
      id = api.userId; // Fallback to memory cache
      debugPrint('[ChatScreen] api.userId cache: $id');
    }

    if (!mounted || initRun != _initVersion) return;
    if (mounted) {
      setState(() {
        myUserId = id?.toString();
      });
    }
    if (id != null) {
      debugPrint('[ChatScreen] Authenticating RealtimeService with: $id');
      RealtimeService().authenticate(id);
    }

    debugPrint('[ChatScreen] Calling loadServiceInfo...');
    await loadServiceInfo(widget.serviceId, () {
      if (!mounted || initRun != _initVersion) return;
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
    if (!mounted || initRun != _initVersion) return;

    RealtimeService().connect();

    debugPrint(
      '[IMPORTANT] Starting signal-based chat subscription for service ${widget.serviceId}',
    );
    chatSubscription = DataGateway().watchChat(widget.serviceId).listen((msgs) {
      if (!mounted || initRun != _initVersion) return;
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

        // Marcar como lida a última mensagem recebida do outro usuário.
        _markIncomingMessageAsRead(sortedMsgs);

        if (sortedMsgs.length != previousCount) {
          scrollToBottom();
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || initRun != _initVersion) return;
      updateBottomPadding();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || initRun != _initVersion) return;
      _ensureNavigationAppsLoaded();
    });
    debugPrint('[ChatScreen] _initChat complete');
    ChatScreen.activeChatServiceId = widget.serviceId;
  }

  void _markIncomingMessageAsRead(List<dynamic> sortedMsgs) {
    if (myUserId == null) return;

    // Procurar a mensagem mais recente que não seja do próprio usuário e
    // que ainda não esteja marcada como lida.
    dynamic unread;
    for (final msg in sortedMsgs) {
      final senderId = msg['sender_id'];
      final readAt = msg['read_at'] ?? msg['readAt'];
      if (senderId != null &&
          senderId.toString() != myUserId.toString() &&
          (readAt == null || readAt.toString().isEmpty)) {
        unread = msg;
        break;
      }
    }

    if (unread == null) return;

    final id = unread['id'];
    final idInt = id is int ? id : int.tryParse('$id');
    if (idInt == null) return;

    if (_lastMarkedReadMessageId == idInt) return;
    _lastMarkedReadMessageId = idInt;

    DataGateway().markChatMessageRead(idInt).catchError((e) {
      debugPrint('[ChatScreen] Erro ao marcar mensagem como lida: $e');
    });
  }

  @override
  void dispose() {
    _initVersion++;
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
    String? otherId;

    if (isMeClient) {
      // Tentar pegar do provider ou contato operacional equivalente
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
      otherId = primaryChatParticipant?['user_id']?.toString() ?? otherUserId;
    } else {
      // Tentar pegar do client ou contratante equivalente
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
      otherId = primaryChatParticipant?['user_id']?.toString() ?? otherUserId;
    }

    final participantContextLabel = _participantContextLabel();

    final chatBody = _buildChatBody(otherName);
    final media = MediaQuery.of(context);

    if (widget.isInline) {
      return AnimatedPadding(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight),
              decoration: BoxDecoration(
                color: AppTheme.backgroundLight,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFEEEEEE)),
                      ),
                    ),
                    child: Row(
                      children: [
                        UserAvatar(
                          avatar: otherAvatar,
                          name: otherName,
                          userId: otherId,
                          radius: 16,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                otherName,
                                style: GoogleFonts.manrope(
                                  fontSize: 15,
                                  color: AppTheme.textDark,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (participantContextLabel != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  participantContextLabel,
                                  style: GoogleFonts.manrope(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (widget.onClose != null)
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 20),
                            onPressed: widget.onClose,
                          )
                        else
                          IconButton(
                            icon: const Icon(LucideIcons.chevronDown, size: 20),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                      ],
                    ),
                  ),
                  Expanded(child: chatBody),
                ],
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.9),
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
    );
  }

  Widget _buildChatBody(String otherName) {
    final media = MediaQuery.of(context);
    final listBottomPadding = bottomPadding + 16 + media.padding.bottom;
    final composerBottomPadding = widget.isInline
        ? 8 + media.padding.bottom
        : 12 + media.padding.bottom;

    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [const Color(0xFFF9FAFC), Colors.white],
                ),
              ),
              child: Scrollbar(
                controller: scrollController,
                thumbVisibility: true,
                child: _hasMessages
                    ? ListView.builder(
                        controller: scrollController,
                        reverse: true,
                        padding: EdgeInsets.only(
                          left: widget.isInline ? 4 : 16,
                          right: widget.isInline ? 4 : 16,
                          top: 10,
                          bottom: listBottomPadding,
                        ),
                        itemCount: messages.length + pendingMessages.length,
                        itemBuilder: (context, index) {
                          bool isPending = false;
                          Map<String, dynamic> msg;
                          dynamic localContent;

                          if (index < pendingMessages.length) {
                            isPending = true;
                            msg =
                                pendingMessages[pendingMessages.length -
                                    1 -
                                    index];
                            localContent = msg['localContent'];
                          } else {
                            msg = messages[index - pendingMessages.length];
                          }

                          final senderIdRaw = msg['sender_id'];
                          final isMe = isPending
                              ? true
                              : (myUserId != null &&
                                    senderIdRaw.toString() ==
                                        myUserId.toString());
                          final type = (msg['type'] ?? 'text').toString();
                          final ts = (msg['created_at'] ?? msg['sent_at'])
                              ?.toString();
                          String time = 'Agora';

                          if (ts != null) {
                            try {
                              final date = DateTime.tryParse(ts);
                              if (date != null) {
                                time = DateFormat(
                                  'HH:mm',
                                ).format(date.toLocal());
                              }
                            } catch (_) {}
                          }

                          final isRead =
                              (msg['read_at'] ?? msg['readAt']) != null;
                          final isSent = msg['status'] == 'sent' || isPending;

                          return _buildMessageBubble(
                            (msg['content'] ?? '').toString(),
                            type,
                            isMe,
                            time,
                            isPending: isPending,
                            isSent: isSent,
                            isRead: isRead,
                            localContent: localContent,
                          );
                        },
                      )
                    : SingleChildScrollView(
                        controller: scrollController,
                        reverse: true,
                        padding: EdgeInsets.only(
                          left: widget.isInline ? 16 : 24,
                          right: widget.isInline ? 16 : 24,
                          top: widget.isInline ? 20 : 28,
                          bottom: listBottomPadding,
                        ),
                        child: _buildEmptyConversation(otherName),
                      ),
              ),
            ),
          ),

          if (widget.showComposer)
            Padding(
              key: inputAreaKey,
              padding: EdgeInsets.only(
                left: widget.isInline ? 4 : 20,
                right: widget.isInline ? 4 : 20,
                bottom: composerBottomPadding,
                top: 8,
              ),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.isInline ? 4 : 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_hasMessages)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _quickReplies().map((item) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _buildActionChip(item.label, item.icon),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    if (_isAttachmentMenuOpen)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildAttachmentMenu(),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: _toggleAttachmentMenu,
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
                          child: isRecording
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.backgroundLight.withOpacity(
                                      0.6,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        LucideIcons.mic,
                                        color: Colors.red,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Gravando... ${_formatElapsed()}',
                                          style: GoogleFonts.manrope(
                                            fontSize: 14,
                                            color: Colors.black87,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : TextField(
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
                                    fillColor: AppTheme.backgroundLight
                                        .withOpacity(0.5),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                  onTap: _closeAttachmentMenu,
                                ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            _closeAttachmentMenu();
                            if (isRecording) {
                              toggleRecord(widget.serviceId, scrollToBottom);
                            } else {
                              sendMessage(widget.serviceId);
                            }
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isRecording
                                  ? Colors.redAccent
                                  : AppTheme.primaryYellow,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (isRecording
                                              ? Colors.redAccent
                                              : AppTheme.primaryYellow)
                                          .withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Icon(
                              isRecording
                                  ? LucideIcons.square
                                  : LucideIcons.send,
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
      ),
    );
  }

  Widget _buildEmptyConversation(String otherName) {
    final quickReplies = _quickReplies();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFF0E4A8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primaryYellow.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  LucideIcons.messageCircle,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _emptyStateTitle(),
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _emptyStateSubtitle(otherName),
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Mensagens rápidas',
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: quickReplies
              .map((item) => _buildActionChip(item.label, item.icon))
              .toList(),
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
              color: Colors.black.withOpacity(0.04),
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

  void _toggleAttachmentMenu() {
    setState(() => _isAttachmentMenuOpen = !_isAttachmentMenuOpen);
    WidgetsBinding.instance.addPostFrameCallback((_) => updateBottomPadding());
  }

  void _closeAttachmentMenu() {
    if (!_isAttachmentMenuOpen) return;
    setState(() => _isAttachmentMenuOpen = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => updateBottomPadding());
  }

  Widget _buildAttachmentMenu() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAttachmentMenuItem(
            'Imagem',
            LucideIcons.camera,
            _handleImageSelection,
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          _buildAttachmentMenuItem(
            'Vídeo',
            LucideIcons.video,
            _handleVideoSelection,
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          _buildAttachmentMenuItem(
            'Áudio',
            LucideIcons.mic,
            _handleAudioAction,
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          _buildAttachmentMenuItem(
            'Localização',
            LucideIcons.mapPin,
            _handleLocationAction,
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentMenuItem(
    String label,
    IconData icon,
    Future<void> Function() action,
  ) {
    return InkWell(
      onTap: () async {
        _closeAttachmentMenu();
        await action();
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.backgroundLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: AppTheme.primaryBlue),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 14,
                color: AppTheme.textDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleImageSelection() async {
    _closeAttachmentMenu();
    await openUnifiedCamera(widget.serviceId, scrollToBottom);
  }

  Future<void> _handleVideoSelection() async {
    _closeAttachmentMenu();
    await openUnifiedCamera(
      widget.serviceId,
      scrollToBottom,
      initialVideoMode: true,
    );
  }

  Future<void> _handleAudioAction() async {
    _closeAttachmentMenu();
    await toggleRecord(widget.serviceId, scrollToBottom);
  }

  Future<void> _handleLocationAction() async {
    _closeAttachmentMenu();
    await _shareLocation();
  }

  Future<void> _shareLocation() async {
    _closeAttachmentMenu();
    setState(() {
      isUploading = true;
      uploadingType = 'localização';
    });

    String? tempId;
    String? payload;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Serviço de localização desativado.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Permissão de localização negada.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );

      payload = jsonEncode({
        'lat': position.latitude,
        'lon': position.longitude,
        'accuracy': position.accuracy,
      });
      tempId = 'temp_loc_${DateTime.now().millisecondsSinceEpoch}';

      setState(() {
        pendingMessages.add({
          'id': tempId,
          'content': payload,
          'type': 'location',
          'created_at': DateTime.now().toIso8601String(),
          'sender_id': myUserId,
          'status': 'sending',
          'is_optimistic': true,
        });
      });

      scrollToBottom();

      await DataGateway().sendChatMessage(
        widget.serviceId,
        payload,
        'location',
      );

      if (mounted) {
        setState(() {
          final idx = pendingMessages.indexWhere((m) => m['id'] == tempId);
          if (idx != -1) pendingMessages[idx]['status'] = 'sent';
        });
      }

      scrollToBottom();
    } catch (e) {
      if (mounted) {
        setState(() => pendingMessages.removeWhere((m) => m['id'] == tempId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao compartilhar localização: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isUploading = false;
          uploadingType = '';
        });
      }
    }
  }

  Map<String, dynamic>? _decodeLocationPayload(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Widget _buildLocationBubble(String content) {
    final locationData = _decodeLocationPayload(content);
    final lat = _toDouble(locationData?['lat']);
    final lon = _toDouble(locationData?['lon']);
    final coords = lat != null && lon != null
        ? '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}'
        : 'Coordenadas indisponíveis';
    final label = locationData?['label']?.toString();
    final accuracyValue = locationData?['accuracy'];
    final accuracy = accuracyValue is num
        ? 'Precisão: ${accuracyValue.toStringAsFixed(1)}m'
        : null;

    final preferredApp = _getPreferredNavigationOption();
    final preferredLabel = preferredApp == null
        ? null
        : 'App preferido: ${preferredApp.label}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.mapPin, size: 18, color: AppTheme.primaryYellow),
            const SizedBox(width: 6),
            Text(
              'Localização compartilhada',
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          label ?? coords,
          style: GoogleFonts.manrope(fontSize: 14, color: Colors.black87),
        ),
        if (accuracy != null) ...[
          const SizedBox(height: 4),
          Text(
            accuracy,
            style: GoogleFonts.manrope(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
        if (preferredLabel != null) ...[
          const SizedBox(height: 6),
          Text(
            preferredLabel,
            style: GoogleFonts.manrope(fontSize: 12, color: Colors.grey[700]),
          ),
        ],
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: lat != null && lon != null
              ? () => _handleLocationNavigation(lat, lon)
              : null,
          icon: const Icon(LucideIcons.navigation, size: 16),
          label: const Text('Abrir no mapa'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryYellow,
            foregroundColor: Colors.black87,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        TextButton(
          onPressed: lat != null && lon != null
              ? () => _handleLocationNavigation(lat, lon, forcePicker: true)
              : null,
          child: const Text('Trocar aplicativo de navegação'),
        ),
      ],
    );
  }

  Future<void> _handleLocationNavigation(
    double lat,
    double lon, {
    bool forcePicker = false,
  }) async {
    if (!forcePicker) {
      final option = _getPreferredNavigationOption();
      if (option != null) {
        final launched = await _launchNavigation(option, lat, lon);
        if (launched) return;
      }
    }

    await _showNavigationPicker(lat, lon);
  }

  Future<void> _showNavigationPicker(double lat, double lon) async {
    await _ensureNavigationAppsLoaded();
    if (_availableNavigationApps.isEmpty) return;

    final defaultOption =
        _getPreferredNavigationOption() ?? _availableNavigationApps.first;

    final result = await showModalBottomSheet<_NavigationSelectionResult>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        String selectedId = defaultOption.id;
        bool savePreference = true;
        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Escolha o GPS',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._availableNavigationApps.map((option) {
                    return RadioListTile<String>(
                      value: option.id,
                      groupValue: selectedId,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => selectedId = value);
                      },
                      title: Text(option.label),
                      secondary: Icon(option.icon, color: AppTheme.primaryBlue),
                    );
                  }),
                  SwitchListTile(
                    title: const Text('Salvar como padrão'),
                    value: savePreference,
                    onChanged: (value) =>
                        setState(() => savePreference = value),
                    activeThumbColor: AppTheme.primaryYellow,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final selectedOption = _availableNavigationApps
                                .firstWhere((opt) => opt.id == selectedId);
                            Navigator.of(context).pop(
                              _NavigationSelectionResult(
                                option: selectedOption,
                                savePreference: savePreference,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryYellow,
                            foregroundColor: Colors.black87,
                          ),
                          child: const Text('Abrir com este GPS'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );

    if (result == null) return;
    if (result.savePreference) {
      await _setPreferredNavigationApp(result.option.id);
    }

    await _launchNavigation(result.option, lat, lon);
  }

  Future<void> _ensureNavigationAppsLoaded() async {
    if (_availableNavigationApps.isEmpty) {
      await _detectAvailableNavigationApps();
    }
  }

  Future<void> _detectAvailableNavigationApps() async {
    final options = _navigationAppOptions;
    final List<_NavigationAppOption> available = [];
    for (final option in options) {
      if (option.isFallback) continue;
      final testUri = option.availabilityUri;
      if (testUri == null) continue;
      try {
        if (await canLaunchUrl(testUri)) {
          available.add(option);
        }
      } catch (_) {}
    }

    final fallback = options.firstWhere((opt) => opt.isFallback);
    if (available.isEmpty) {
      available.add(fallback);
    } else if (!available.any((opt) => opt.id == fallback.id)) {
      available.add(fallback);
    }

    if (!mounted) return;
    setState(() => _availableNavigationApps = available);
  }

  Future<void> _setPreferredNavigationApp(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_navigationPreferenceKey, id);
    if (mounted) {
      setState(() => _preferredNavigationAppId = id);
    }
  }

  _NavigationAppOption? _getPreferredNavigationOption() {
    if (_preferredNavigationAppId == null) return null;
    for (final option in _availableNavigationApps) {
      if (option.id == _preferredNavigationAppId) {
        return option;
      }
    }
    return null;
  }

  Future<bool> _launchNavigation(
    _NavigationAppOption option,
    double lat,
    double lon,
  ) async {
    try {
      final uri = option.uriBuilder(lat, lon);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao abrir ${option.label}: $e')),
        );
      }
      return false;
    }
  }

  List<_NavigationAppOption> get _navigationAppOptions {
    return [
      _NavigationAppOption(
        id: 'google_maps',
        label: 'Google Maps',
        icon: LucideIcons.map,
        uriBuilder: (lat, lon) {
          if (kIsWeb) {
            return Uri.parse(
              'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon',
            );
          }
          if (Platform.isIOS) {
            return Uri.parse(
              'comgooglemaps://?daddr=$lat,$lon&directionsmode=driving',
            );
          }
          return Uri.parse('google.navigation:q=$lat,$lon');
        },
        availabilityUri: kIsWeb
            ? null
            : (Platform.isIOS
                  ? Uri.parse('comgooglemaps://')
                  : Uri.parse('google.navigation:?q=0,0')),
      ),
      _NavigationAppOption(
        id: 'waze',
        label: 'Waze',
        icon: LucideIcons.navigation,
        uriBuilder: (lat, lon) =>
            Uri.parse('waze://?ll=$lat,$lon&navigate=yes'),
        availabilityUri: kIsWeb ? null : Uri.parse('waze://'),
      ),
      _NavigationAppOption(
        id: 'apple_maps',
        label: 'Apple Maps',
        icon: LucideIcons.mapPin,
        uriBuilder: (lat, lon) => Platform.isIOS
            ? Uri.parse('maps://?daddr=$lat,$lon&dirflg=d')
            : Uri.parse('https://maps.apple.com/?daddr=$lat,$lon&dirflg=d'),
        availabilityUri: kIsWeb
            ? null
            : (Platform.isIOS ? Uri.parse('maps://') : null),
      ),
      _NavigationAppOption(
        id: 'browser_maps',
        label: 'Navegador',
        icon: LucideIcons.globe,
        uriBuilder: (lat, lon) => Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon',
        ),
        availabilityUri: null,
        isFallback: true,
      ),
    ];
  }

  Widget _buildMessageBubble(
    String content,
    String type,
    bool isMe,
    String time, {
    bool isPending = false,
    bool isSent = true,
    bool isRead = false,
    dynamic localContent,
  }) {
    final isImage = type == 'image';
    final isLocation = type == 'location';
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
                      color: Colors.black.withOpacity(0.4),
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
    } else if (isLocation) {
      bubbleChild = _buildLocationBubble(content);
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
            maxWidth:
                MediaQuery.of(context).size.width *
                (widget.isInline ? 0.96 : 0.75),
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
                ? Border.all(color: const Color(0xFFC7D2FE).withOpacity(0.5))
                : Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
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
                    if (isPending)
                      const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.grey,
                        ),
                      )
                    else if (isRead)
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4CAF50), // Verde de destaque
                          shape: BoxShape.circle,
                        ),
                      )
                    else if (isSent)
                      Icon(
                        LucideIcons.check,
                        size: 14,
                        color: Colors.grey[600],
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

class _NavigationSelectionResult {
  final _NavigationAppOption option;
  final bool savePreference;

  _NavigationSelectionResult({
    required this.option,
    required this.savePreference,
  });
}

class _NavigationAppOption {
  final String id;
  final String label;
  final IconData icon;
  final Uri Function(double lat, double lon) uriBuilder;
  final Uri? availabilityUri;
  final bool isFallback;

  const _NavigationAppOption({
    required this.id,
    required this.label,
    required this.icon,
    required this.uriBuilder,
    this.availabilityUri,
    this.isFallback = false,
  });
}
