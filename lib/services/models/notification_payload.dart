import '../../core/utils/notification_type_helper.dart';

enum NotificationPayloadChannel {
  generic,
  serviceUpdate,
  serviceOffer,
  chat,
  tripOffer,
  tripUpdate,
}

class NotificationPayload {
  final String type;
  final String? entityId;
  final String title;
  final String body;
  final NotificationPayloadChannel channel;
  final Map<String, dynamic> data;

  const NotificationPayload({
    required this.type,
    required this.title,
    required this.body,
    required this.channel,
    required this.data,
    this.entityId,
  });

  factory NotificationPayload.fromMap(
    Map<String, dynamic> data, {
    String? fallbackTitle,
    String? fallbackBody,
    NotificationPayloadChannel fallbackChannel =
        NotificationPayloadChannel.generic,
  }) {
    final type = data['type']?.toString().trim() ?? 'generic';
    final title = data['title']?.toString().trim().isNotEmpty == true
        ? data['title'].toString().trim()
        : (fallbackTitle?.trim().isNotEmpty == true
              ? fallbackTitle!.trim()
              : '101 Service');
    final body = data['body']?.toString().trim().isNotEmpty == true
        ? data['body'].toString().trim()
        : (fallbackBody?.trim().isNotEmpty == true
              ? fallbackBody!.trim()
              : 'Nova notificacao recebida.');
    final entityId =
        data['service_id']?.toString() ??
        data['trip_id']?.toString() ??
        data['id']?.toString();

    return NotificationPayload(
      type: type,
      entityId: entityId,
      title: title,
      body: body,
      channel: _inferChannel(type, fallbackChannel: fallbackChannel),
      data: Map<String, dynamic>.from(data),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      ...data,
      'type': type,
      'title': title,
      'body': body,
      if (entityId != null) 'entity_id': entityId,
      'channel': channel.name,
    };
  }

  String dedupeKey() => '${channel.name}:$type:${entityId ?? ''}';

  static NotificationPayloadChannel _inferChannel(
    String type, {
    required NotificationPayloadChannel fallbackChannel,
  }) {
    if (type == 'chat_message' || type == 'chat') {
      return NotificationPayloadChannel.chat;
    }
    if (type == 'central_trip_offer') {
      return NotificationPayloadChannel.tripOffer;
    }
    if (type.startsWith('central_trip_')) {
      return NotificationPayloadChannel.tripUpdate;
    }
    if (isServiceOfferNotificationType(type)) {
      return NotificationPayloadChannel.serviceOffer;
    }
    if (type == 'status_update' ||
        type == 'service_started' ||
        type == 'service_completed' ||
        type == 'payment_approved' ||
        type == 'schedule_confirmed' ||
        type == 'schedule_30m_reminder' ||
        type == 'schedule_proposal' ||
        type == 'schedule_proposal_expired' ||
        type == 'scheduled_started') {
      return NotificationPayloadChannel.serviceUpdate;
    }
    return fallbackChannel;
  }
}
