class BackendClientHomeState {
  const BackendClientHomeState({
    required this.services,
    required this.activeService,
    required this.pendingFixedPayment,
    required this.upcomingAppointment,
  });

  final List<Map<String, dynamic>> services;
  final Map<String, dynamic>? activeService;
  final Map<String, dynamic>? pendingFixedPayment;
  final Map<String, dynamic>? upcomingAppointment;

  factory BackendClientHomeState.fromJson(Map<String, dynamic> json) {
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? json;
    final snapshot =
        (data['snapshot'] as Map?)?.cast<String, dynamic>() ?? data;

    List<Map<String, dynamic>> readList(String key) {
      final raw = snapshot[key];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .toList();
    }

    Map<String, dynamic>? readMap(String key) {
      final raw = snapshot[key];
      if (raw is! Map) return null;
      return raw.cast<String, dynamic>();
    }

    return BackendClientHomeState(
      services: readList('services'),
      activeService: readMap('activeService'),
      pendingFixedPayment: readMap('pendingFixedPayment'),
      upcomingAppointment: readMap('upcomingAppointment'),
    );
  }
}
