class RemoteAction {
  const RemoteAction({
    required this.type,
    this.commandKey,
    this.routeKey,
    this.linkKey,
    this.message,
    this.nativeFlowKey,
    this.arguments = const <String, dynamic>{},
  });

  final String type;
  final String? commandKey;
  final String? routeKey;
  final String? linkKey;
  final String? message;
  final String? nativeFlowKey;
  final Map<String, dynamic> arguments;

  factory RemoteAction.fromJson(Map<String, dynamic> json) {
    return RemoteAction(
      type: (json['type'] ?? '').toString().trim(),
      commandKey: _readNullableString(
        json['command_key'] ?? json['command'],
      ),
      routeKey: _readNullableString(json['route_key']),
      linkKey: _readNullableString(json['link_key']),
      message: _readNullableString(json['message']),
      nativeFlowKey: _readNullableString(json['native_flow_key']),
      arguments: _readMap(json['arguments']),
    );
  }

  static String? _readNullableString(dynamic raw) {
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  static Map<String, dynamic> _readMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }
}
