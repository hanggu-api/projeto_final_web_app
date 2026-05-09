import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../services/data_gateway.dart';

class OpenChatHelper {
  const OpenChatHelper._();

  static String? participantContextLabelForService(
    Map<String, dynamic>? service,
    String currentRole,
  ) {
    if (service == null) return null;
    final participants = DataGateway().extractChatParticipants(service);
    final beneficiary = participants.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['role'] == 'beneficiary',
      orElse: () => null,
    );
    final requester = participants.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['role'] == 'requester',
      orElse: () => null,
    );
    if (beneficiary == null) return null;
    final beneficiaryName = '${beneficiary['display_name'] ?? ''}'.trim();
    if (beneficiaryName.isEmpty) return null;
    final beneficiaryId = '${beneficiary['user_id'] ?? ''}'.trim();
    final requesterId = '${requester?['user_id'] ?? ''}'.trim();
    if (beneficiaryId.isNotEmpty && beneficiaryId == requesterId) return null;
    return currentRole == 'provider'
        ? 'Atendimento para $beneficiaryName'
        : 'Pessoa atendida: $beneficiaryName';
  }

  static Map<String, dynamic> buildChatExtra({
    required String serviceId,
    Map<String, dynamic>? service,
    String? otherName,
    String? otherAvatar,
    String? currentRole,
  }) {
    final participants = service == null
        ? const <Map<String, dynamic>>[]
        : DataGateway().extractChatParticipants(service);
    return {
      'serviceId': serviceId,
      if (otherName != null) 'otherName': otherName,
      if (otherAvatar != null) 'otherAvatar': otherAvatar,
      if (participants.isNotEmpty) 'participants': participants,
      if (currentRole != null)
        'participantContextLabel': participantContextLabelForService(
          service,
          currentRole,
        ),
    };
  }

  static void push(
    BuildContext context, {
    required String serviceId,
    Map<String, dynamic>? service,
    String? otherName,
    String? otherAvatar,
    String? currentRole,
  }) {
    context.push(
      '/chat/$serviceId',
      extra: buildChatExtra(
        serviceId: serviceId,
        service: service,
        otherName: otherName,
        otherAvatar: otherAvatar,
        currentRole: currentRole,
      ),
    );
  }
}
