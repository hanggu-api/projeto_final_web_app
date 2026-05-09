class RemoteScreenRequest {
  const RemoteScreenRequest({
    required this.screenKey,
    required this.appRole,
    required this.platform,
    required this.appVersion,
    required this.locale,
    this.patchVersion,
    this.environment,
    this.featureSet = const <String, bool>{},
    this.context = const <String, dynamic>{},
  });

  final String screenKey;
  final String appRole;
  final String platform;
  final String appVersion;
  final String locale;
  final String? patchVersion;
  final String? environment;
  final Map<String, bool> featureSet;
  final Map<String, dynamic> context;

  Map<String, dynamic> toJson() {
    return {
      'screen_key': screenKey,
      'app_role': appRole,
      'platform': platform,
      'app_version': appVersion,
      'locale': locale,
      if (patchVersion != null) 'patch_version': patchVersion,
      if (environment != null) 'environment': environment,
      'feature_set': featureSet,
      'context': context,
    };
  }
}
