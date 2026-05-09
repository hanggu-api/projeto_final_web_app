class NotificationEnvelope {
  final String canonicalType;
  final String? title;
  final String? body;
  final Map<String, dynamic> data;
  final bool fromLegacyAlias;

  const NotificationEnvelope({
    required this.canonicalType,
    required this.title,
    required this.body,
    required this.data,
    required this.fromLegacyAlias,
  });

  factory NotificationEnvelope.fromMap(
    Map<String, dynamic> data, {
    required String canonicalType,
    required bool fromLegacyAlias,
  }) {
    return NotificationEnvelope(
      canonicalType: canonicalType,
      title: data['title']?.toString(),
      body: data['body']?.toString(),
      data: Map<String, dynamic>.from(data),
      fromLegacyAlias: fromLegacyAlias,
    );
  }
}
