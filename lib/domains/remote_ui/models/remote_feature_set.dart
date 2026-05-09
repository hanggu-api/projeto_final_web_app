class RemoteFeatureSet {
  const RemoteFeatureSet({
    this.enabled = true,
    this.killSwitch = false,
    this.flags = const <String, bool>{},
  });

  final bool enabled;
  final bool killSwitch;
  final Map<String, bool> flags;

  factory RemoteFeatureSet.fromJson(Map<String, dynamic> json) {
    return RemoteFeatureSet(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      killSwitch: json['kill_switch'] is bool
          ? json['kill_switch'] as bool
          : false,
      flags: _readFlags(json['flags']),
    );
  }

  static Map<String, bool> _readFlags(dynamic raw) {
    if (raw is! Map) return const <String, bool>{};
    return raw.map((key, value) => MapEntry(key.toString(), value == true));
  }
}
