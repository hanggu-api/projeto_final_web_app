class BackendBootstrapState {
  const BackendBootstrapState({
    required this.authenticated,
    required this.userId,
    required this.role,
    required this.isMedical,
    required this.isFixedLocation,
    required this.registerStep,
    required this.nextRoute,
  });

  final bool authenticated;
  final String? userId;
  final String? role;
  final bool isMedical;
  final bool isFixedLocation;
  final int? registerStep;
  final String nextRoute;

  factory BackendBootstrapState.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? json;
    return BackendBootstrapState(
      authenticated: data['authenticated'] == true,
      userId: data['userId']?.toString(),
      role: data['role']?.toString(),
      isMedical: data['isMedical'] == true,
      isFixedLocation: data['isFixedLocation'] == true,
      registerStep: data['registerStep'] is int
          ? data['registerStep'] as int
          : int.tryParse('${data['registerStep'] ?? ''}'),
      nextRoute: (data['nextRoute'] ?? '/login').toString(),
    );
  }
}
