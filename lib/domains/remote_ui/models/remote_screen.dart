import 'remote_component.dart';
import 'remote_fallback_policy.dart';
import 'remote_feature_set.dart';

class RemoteScreen {
  const RemoteScreen({
    required this.version,
    required this.screen,
    required this.revision,
    required this.ttlSeconds,
    required this.features,
    required this.layout,
    required this.components,
    required this.fallbackPolicy,
  });

  final int version;
  final String screen;
  final String revision;
  final int ttlSeconds;
  final RemoteFeatureSet features;
  final Map<String, dynamic> layout;
  final List<RemoteComponent> components;
  final RemoteFallbackPolicy fallbackPolicy;

  bool get isEnabled => features.enabled && !features.killSwitch;

  factory RemoteScreen.fromJson(Map<String, dynamic> json) {
    return RemoteScreen(
      version: _readInt(json['version'], fallback: 0),
      screen: (json['screen'] ?? '').toString().trim(),
      revision: (json['revision'] ?? '').toString().trim(),
      ttlSeconds: _readInt(json['ttl_seconds'], fallback: 300),
      features: RemoteFeatureSet.fromJson(_readMap(json['features'])),
      layout: _readMap(json['layout']),
      components: _readComponents(json['components']),
      fallbackPolicy: RemoteFallbackPolicy.fromJson(
        _readMap(json['fallback_policy']),
      ),
    );
  }

  static int _readInt(dynamic raw, {required int fallback}) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  static Map<String, dynamic> _readMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  static List<RemoteComponent> _readComponents(dynamic raw) {
    if (raw is! List) return const <RemoteComponent>[];
    return raw
        .whereType<Map>()
        .map(
          (item) => RemoteComponent.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }
}
