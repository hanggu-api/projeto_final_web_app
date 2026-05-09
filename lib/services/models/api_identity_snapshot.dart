class ApiIdentitySnapshot {
  final int? userId;
  final String? role;
  final bool isMedical;
  final bool isFixedLocation;

  const ApiIdentitySnapshot({
    required this.userId,
    required this.role,
    required this.isMedical,
    required this.isFixedLocation,
  });

  bool get hasIdentity => userId != null || (role?.trim().isNotEmpty ?? false);
}

class ApiStoredSessionSnapshot {
  final String? token;
  final ApiIdentitySnapshot identity;

  const ApiStoredSessionSnapshot({required this.token, required this.identity});
}
