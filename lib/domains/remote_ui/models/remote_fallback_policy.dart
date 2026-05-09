enum RemoteFallbackMode { useNative, useCacheThenNative }

class RemoteFallbackPolicy {
  const RemoteFallbackPolicy({
    this.mode = RemoteFallbackMode.useCacheThenNative,
    this.allowCache = true,
  });

  final RemoteFallbackMode mode;
  final bool allowCache;

  factory RemoteFallbackPolicy.fromJson(Map<String, dynamic> json) {
    final modeValue = (json['mode'] ?? '').toString().trim().toLowerCase();
    return RemoteFallbackPolicy(
      mode: modeValue == 'use_native'
          ? RemoteFallbackMode.useNative
          : RemoteFallbackMode.useCacheThenNative,
      allowCache: json['allow_cache'] is bool
          ? json['allow_cache'] as bool
          : true,
    );
  }
}
