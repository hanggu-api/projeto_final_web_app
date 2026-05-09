class ChatParticipant {
  final String role;
  final String? userId;
  final String displayName;
  final String? avatarUrl;
  final String? phone;
  final bool canSend;
  final bool isPrimaryOperationalContact;

  const ChatParticipant({
    required this.role,
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
    required this.phone,
    required this.canSend,
    required this.isPrimaryOperationalContact,
  });

  factory ChatParticipant.fromMap(Map<String, dynamic> map) {
    return ChatParticipant(
      role: (map['role'] ?? '').toString().trim(),
      userId: (map['user_id'] ?? '').toString().trim().isEmpty
          ? null
          : (map['user_id'] ?? '').toString().trim(),
      displayName: (map['display_name'] ?? '').toString().trim(),
      avatarUrl: (map['avatar_url'] ?? '').toString().trim().isEmpty
          ? null
          : (map['avatar_url'] ?? '').toString().trim(),
      phone: (map['phone'] ?? '').toString().trim().isEmpty
          ? null
          : (map['phone'] ?? '').toString().trim(),
      canSend: map['can_send'] == true,
      isPrimaryOperationalContact:
          map['is_primary_operational_contact'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'role': role,
      'user_id': userId,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'phone': phone,
      'can_send': canSend,
      'is_primary_operational_contact': isPrimaryOperationalContact,
    };
  }
}
