class BackendProviderHomeState {
  const BackendProviderHomeState({
    required this.role,
    required this.isFixedLocation,
    required this.isMedical,
    required this.subRole,
    required this.userId,
  });

  final String? role;
  final bool isFixedLocation;
  final bool isMedical;
  final String? subRole;
  final int? userId;

  factory BackendProviderHomeState.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? json;
    final snapshot =
        (data['snapshot'] as Map?)?.cast<String, dynamic>() ?? data;
    final profile =
        (snapshot['profile'] as Map?)?.cast<String, dynamic>() ?? snapshot;

    return BackendProviderHomeState(
      role: profile['role']?.toString(),
      isFixedLocation: profile['isFixedLocation'] == true,
      isMedical: profile['isMedical'] == true,
      subRole: profile['subRole']?.toString(),
      userId: profile['userId'] is int
          ? profile['userId'] as int
          : int.tryParse('${profile['userId'] ?? ''}'),
    );
  }
}
