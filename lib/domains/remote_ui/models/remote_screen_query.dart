class RemoteScreenQuery {
  const RemoteScreenQuery({
    required this.screenKey,
    this.context = const <String, dynamic>{},
  });

  final String screenKey;
  final Map<String, dynamic> context;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RemoteScreenQuery &&
        other.screenKey == screenKey &&
        _mapEquals(other.context, context);
  }

  @override
  int get hashCode => Object.hash(screenKey, Object.hashAll(_hashEntries()));

  Iterable<int> _hashEntries() => context.entries
      .map((entry) => Object.hash(entry.key, entry.value));

  static bool _mapEquals(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}
