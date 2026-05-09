class AppRuntimeSnapshot {
  const AppRuntimeSnapshot({
    required this.storeVersion,
    required this.patchVersion,
    required this.environment,
    required this.activeFlags,
    required this.remoteScreenSources,
  });

  final String storeVersion;
  final String patchVersion;
  final String environment;
  final Map<String, bool> activeFlags;
  final Map<String, String> remoteScreenSources;

  Map<String, dynamic> toJson() {
    return {
      'store_version': storeVersion,
      'patch_version': patchVersion,
      'environment': environment,
      'active_flags': activeFlags,
      'remote_screen_sources': remoteScreenSources,
    };
  }

  AppRuntimeSnapshot copyWith({
    String? storeVersion,
    String? patchVersion,
    String? environment,
    Map<String, bool>? activeFlags,
    Map<String, String>? remoteScreenSources,
  }) {
    return AppRuntimeSnapshot(
      storeVersion: storeVersion ?? this.storeVersion,
      patchVersion: patchVersion ?? this.patchVersion,
      environment: environment ?? this.environment,
      activeFlags: activeFlags ?? this.activeFlags,
      remoteScreenSources: remoteScreenSources ?? this.remoteScreenSources,
    );
  }
}
