class BackendProfileState {
  const BackendProfileState({
    required this.id,
    required this.supabaseUid,
    required this.email,
    required this.fullName,
    required this.role,
    required this.isMedical,
    required this.isFixedLocation,
    required this.subRole,
    required this.lastSeenAt,
    required this.walletBalance,
  });

  final int? id;
  final String? supabaseUid;
  final String? email;
  final String? fullName;
  final String? role;
  final bool isMedical;
  final bool isFixedLocation;
  final String? subRole;
  final String? lastSeenAt;
  final double walletBalance;

  factory BackendProfileState.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? json;
    final user = (data['user'] as Map?)?.cast<String, dynamic>() ?? data;
    final walletRaw =
        user['wallet_balance_effective'] ??
        user['wallet_balance'] ??
        user['balance'];

    return BackendProfileState(
      id: user['id'] is int ? user['id'] as int : int.tryParse('${user['id'] ?? ''}'),
      supabaseUid: user['supabase_uid']?.toString(),
      email: user['email']?.toString(),
      fullName: user['full_name']?.toString(),
      role: user['role']?.toString(),
      isMedical: user['is_medical'] == true,
      isFixedLocation: user['is_fixed_location'] == true,
      subRole: user['sub_role']?.toString(),
      lastSeenAt: user['last_seen_at']?.toString(),
      walletBalance: walletRaw is num
          ? walletRaw.toDouble()
          : double.tryParse('$walletRaw') ?? 0,
    );
  }

  Map<String, dynamic> toApiUserMap() {
    return {
      'id': id,
      'supabase_uid': supabaseUid,
      'email': email,
      'full_name': fullName,
      'role': role,
      'is_medical': isMedical,
      'is_fixed_location': isFixedLocation,
      'sub_role': subRole,
      'last_seen_at': lastSeenAt,
      'wallet_balance_effective': walletBalance,
      'wallet_balance': walletBalance,
      'balance': walletBalance,
    };
  }
}
