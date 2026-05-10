class BackendProfileState {
  const BackendProfileState({
    required this.id,
    required this.supabaseUid,
    required this.email,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.isMedical,
    required this.isFixedLocation,
    required this.subRole,
    required this.lastSeenAt,
    required this.walletBalance,
    required this.isVerified,
    required this.providers,
    required this.ratingAvg,
    required this.ratingCount,
    required this.completionRate,
    required this.rawUser,
  });

  final int? id;
  final String? supabaseUid;
  final String? email;
  final String? fullName;
  final String? phone;
  final String? role;
  final bool isMedical;
  final bool isFixedLocation;
  final String? subRole;
  final String? lastSeenAt;
  final double walletBalance;
  final bool isVerified;
  final dynamic providers;
  final double? ratingAvg;
  final int? ratingCount;
  final double? completionRate;
  final Map<String, dynamic> rawUser;

  factory BackendProfileState.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? json;
    final user = (data['user'] as Map?)?.cast<String, dynamic>() ?? data;
    final walletRaw =
        user['wallet_balance_effective'] ??
        user['wallet_balance'] ??
        user['balance'];
    final ratingRaw =
        user['rating_avg'] ??
        user['rating'] ??
        user['average_rating'] ??
        user['provider_rating'];
    final ratingCountRaw =
        user['rating_count'] ??
        user['review_count'] ??
        user['reviews_count'] ??
        user['provider_reviews'];
    final completionRaw =
        user['completion_rate'] ??
        user['completion_percentage'] ??
        user['completed_rate'] ??
        user['provider_completion_rate'];

    return BackendProfileState(
      id: user['id'] is int
          ? user['id'] as int
          : int.tryParse('${user['id'] ?? ''}'),
      supabaseUid: user['supabase_uid']?.toString(),
      email: user['email']?.toString(),
      fullName: user['full_name']?.toString(),
      phone: user['phone']?.toString(),
      role: user['role']?.toString(),
      isMedical: user['is_medical'] == true,
      isFixedLocation: user['is_fixed_location'] == true,
      subRole: user['sub_role']?.toString(),
      lastSeenAt: user['last_seen_at']?.toString(),
      walletBalance: walletRaw is num
          ? walletRaw.toDouble()
          : double.tryParse('$walletRaw') ?? 0,
      isVerified: user['is_verified'] == true || user['verified'] == true,
      providers: user['providers'] ?? user['provider'],
      ratingAvg: ratingRaw is num
          ? ratingRaw.toDouble()
          : double.tryParse('${ratingRaw ?? ''}'),
      ratingCount: ratingCountRaw is num
          ? ratingCountRaw.toInt()
          : int.tryParse('${ratingCountRaw ?? ''}'),
      completionRate: completionRaw is num
          ? completionRaw.toDouble()
          : double.tryParse('${completionRaw ?? ''}'),
      rawUser: Map<String, dynamic>.from(user),
    );
  }

  Map<String, dynamic> toApiUserMap() {
    return {
      ...rawUser,
      'id': id,
      'supabase_uid': supabaseUid,
      'email': email,
      'name': fullName,
      'full_name': fullName,
      'phone': phone,
      'role': role,
      'is_medical': isMedical,
      'is_fixed_location': isFixedLocation,
      'sub_role': subRole,
      'last_seen_at': lastSeenAt,
      'is_verified': isVerified,
      'providers': providers,
      'wallet_balance_effective': walletBalance,
      'wallet_balance': walletBalance,
      'balance': walletBalance,
      'rating_avg': ratingAvg,
      'rating_count': ratingCount,
      'completion_rate': completionRate,
    };
  }
}
