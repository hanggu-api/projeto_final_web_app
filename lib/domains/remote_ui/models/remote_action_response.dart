class RemoteActionResponse {
  const RemoteActionResponse({
    required this.success,
    this.message,
    this.nextScreen,
    this.refreshScreen = false,
    this.updatedState = const <String, dynamic>{},
    this.effects = const <Map<String, dynamic>>[],
    this.handled = false,
  });

  final bool success;
  final String? message;
  final String? nextScreen;
  final bool refreshScreen;
  final Map<String, dynamic> updatedState;
  final List<Map<String, dynamic>> effects;
  final bool handled;

  factory RemoteActionResponse.fromJson(Map<String, dynamic> json) {
    return RemoteActionResponse(
      success: json['success'] == true,
      message: _readString(json['message']),
      nextScreen: _readString(json['next_screen']),
      refreshScreen: json['refresh_screen'] == true,
      updatedState: _readMap(json['updated_state']),
      effects: _readEffects(json['effects']),
      handled: json['handled'] == true,
    );
  }

  static String? _readString(dynamic raw) {
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

  static List<Map<String, dynamic>> _readEffects(dynamic raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
        .toList(growable: false);
  }
}
