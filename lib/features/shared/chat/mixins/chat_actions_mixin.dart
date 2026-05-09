import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/utils/fixed_schedule_gate.dart';
import '../chat_state.dart';
import '../../../../services/api_service.dart';
import '../../../../services/data_gateway.dart';
import '../../../../services/realtime_service.dart';

mixin ChatActionsMixin<T extends StatefulWidget>
    on State<T>, ChatStateMixin<T> {
  void reconcilePendingMessages() {
    if (pendingMessages.isEmpty) return;
    pendingMessages.removeWhere((pending) {
      if (pending['status'] != 'sent') return false;
      final pContent = pending['content'];
      final pType = pending['type'];
      return messages.any((serverMsg) {
        return serverMsg['content'] == pContent && serverMsg['type'] == pType;
      });
    });
  }

  Future<void> sendMessage(String serviceId, {String? content}) async {
    final text = content ?? messageController.text.trim();
    debugPrint(
      '[ChatActionsMixin] sendMessage called - serviceId: $serviceId, text: $text',
    );
    if (text.isEmpty) {
      debugPrint('[ChatActionsMixin] Mensagem vazia, ignorando.');
      return;
    }

    messageController.clear();

    final tempId = DateTime.now().millisecondsSinceEpoch;
    final optimisticMsg = {
      'id': 'temp_$tempId',
      'content': text,
      'type': 'text',
      'created_at': DateTime.now().toIso8601String(),
      'sender_id': myUserId,
      'status': 'sending',
    };

    setState(() {
      pendingMessages.add(optimisticMsg);
    });

    try {
      await DataGateway().sendChatMessage(
        serviceId,
        text,
        'text',
        recipientId: primaryChatParticipant?['user_id']?.toString(),
      );
      if (mounted) {
        setState(() {
          final index = pendingMessages.indexWhere(
            (m) => m['id'] == 'temp_$tempId',
          );
          if (index != -1) pendingMessages[index]['status'] = 'sent';
        });
      }
      scrollToBottom();
    } catch (e) {
      if (mounted) {
        setState(
          () => pendingMessages.removeWhere((m) => m['id'] == 'temp_$tempId'),
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao enviar: $e')));
      }
    }
  }

  Future<void> confirmSchedule(String serviceId, DateTime date) async {
    try {
      final details = serviceDetails;
      final scope = details == null
          ? ServiceDataScope.auto
          : (isCanonicalFixedServiceRecord(details)
                ? ServiceDataScope.fixedOnly
                : ServiceDataScope.mobileOnly);
      await api.confirmSchedule(serviceId, date, scope: scope);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Agendamento confirmado!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao confirmar: $e')));
      }
    }
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void updateBottomPadding() {
    final inCtx = inputAreaKey.currentContext;
    final inH = (inCtx?.size?.height ?? 0);
    final newVal = inH + 10;
    if (newVal > 0 && (newVal - bottomPadding).abs() > 1) {
      setState(() => bottomPadding = newVal);
      scrollToBottom();
    }
  }

  DateTime parseMessageDate(Map<String, dynamic> msg) {
    try {
      final dateStr = msg['created_at'] ?? msg['sent_at'] ?? msg['createdAt'];
      if (dateStr == null) return DateTime.now();
      return DateTime.parse(dateStr);
    } catch (e) {
      return DateTime.now();
    }
  }

  Future<void> loadServiceInfo(
    String serviceId,
    Function onCalculateOther,
  ) async {
    try {
      final details = await DataGateway().getServiceDetails(serviceId);
      if (mounted) {
        setState(() {
          serviceDetails = details;
          chatParticipants = DataGateway().extractChatParticipants(details);
        });
        unawaited(
          DataGateway().saveChatParticipantsSnapshot(
            serviceId,
            chatParticipants,
          ),
        );
        onCalculateOther();
      }
    } catch (e) {
      debugPrint('[ChatActionsMixin] Erro ao carregar info do serviço: $e');
    }
  }

  void calculateOtherUser(Function(String, Function(bool)) onCheckStatus) {
    if (serviceDetails == null) return;
    if (role == null && myUserId == null) return;

    final s = serviceDetails!;
    bool isMeClient = role == 'client';

    // Logic from the original calculateOtherUser
    if (role == null) {
      final myIdStr = myUserId?.toString();
      dynamic userIdRaw =
          s['user_id'] ?? (s['client'] is Map ? s['client']['id'] : null);
      isMeClient = userIdRaw?.toString() == myIdStr;
    }

    final normalizedParticipants =
        chatParticipants.isNotEmpty
        ? chatParticipants
        : DataGateway().extractChatParticipants(s);
    final myId = myUserId?.toString().trim();

    Map<String, dynamic>? targetParticipant;
    if (isMeClient) {
      targetParticipant = normalizedParticipants.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['role'] == 'provider',
        orElse: () => null,
      );
      targetParticipant ??= normalizedParticipants.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['role'] == 'beneficiary',
        orElse: () => null,
      );
    } else {
      targetParticipant = normalizedParticipants.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['role'] == 'beneficiary',
        orElse: () => null,
      );
      targetParticipant ??= normalizedParticipants.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['role'] == 'requester',
        orElse: () => null,
      );
      targetParticipant ??= normalizedParticipants.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['role'] == 'guardian',
        orElse: () => null,
      );
    }

    if ((targetParticipant == null ||
            '${targetParticipant['user_id'] ?? ''}'.trim().isEmpty) &&
        !isMeClient) {
      targetParticipant = normalizedParticipants.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['role'] == 'requester' &&
            '${item?['user_id'] ?? ''}'.trim().isNotEmpty,
        orElse: () => null,
      );
      targetParticipant ??= normalizedParticipants.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['role'] == 'guardian' &&
            '${item?['user_id'] ?? ''}'.trim().isNotEmpty,
        orElse: () => null,
      );
    }

    if (targetParticipant != null &&
        '${targetParticipant['user_id'] ?? ''}'.trim() == myId) {
      targetParticipant = normalizedParticipants.cast<Map<String, dynamic>?>().firstWhere(
        (item) =>
            item != null &&
            '${item['user_id'] ?? ''}'.trim().isNotEmpty &&
            '${item['user_id'] ?? ''}'.trim() != myId,
        orElse: () => null,
      );
    }

    final targetId = '${targetParticipant?['user_id'] ?? ''}'.trim();

    if (targetId.isNotEmpty && targetId != otherUserId) {
      setState(() {
        otherUserId = targetId;
        primaryChatParticipant = targetParticipant;
      });
      RealtimeService().checkStatus(targetId, (online) {
        if (mounted) setState(() => isOtherOnline = online);
      });
    }
  }
}
