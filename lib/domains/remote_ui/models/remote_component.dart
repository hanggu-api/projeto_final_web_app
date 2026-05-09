import 'remote_action.dart';

class RemoteComponent {
  const RemoteComponent({
    required this.id,
    required this.type,
    this.props = const <String, dynamic>{},
    this.children = const <RemoteComponent>[],
    this.action,
  });

  final String id;
  final String type;
  final Map<String, dynamic> props;
  final List<RemoteComponent> children;
  final RemoteAction? action;

  factory RemoteComponent.fromJson(Map<String, dynamic> json) {
    return RemoteComponent(
      id: (json['id'] ?? '').toString().trim(),
      type: (json['type'] ?? '').toString().trim(),
      props: _readMap(json['props']),
      children: _readChildren(json['children']),
      action: json['action'] is Map
          ? RemoteAction.fromJson(_readMap(json['action']))
          : null,
    );
  }

  static Map<String, dynamic> _readMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  static List<RemoteComponent> _readChildren(dynamic raw) {
    if (raw is! List) return const <RemoteComponent>[];
    return raw
        .whereType<Map>()
        .map(
          (child) => RemoteComponent.fromJson(
            child.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList(growable: false);
  }
}
