enum AppConfigCategory { featureFlag, operational, killSwitch, content, unknown }

class AppConfigEntry {
  const AppConfigEntry({
    required this.key,
    required this.value,
    required this.category,
    required this.platformScope,
    required this.isActive,
    required this.revision,
  });

  final String key;
  final dynamic value;
  final AppConfigCategory category;
  final String platformScope;
  final bool isActive;
  final int revision;

  bool matchesPlatform(String platform) {
    final normalizedScope = platformScope.trim().toLowerCase();
    final normalizedPlatform = platform.trim().toLowerCase();
    return normalizedScope.isEmpty ||
        normalizedScope == 'all' ||
        normalizedScope == '*' ||
        normalizedScope == normalizedPlatform;
  }

  bool boolValue({required bool fallback}) {
    final raw = value;
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final text = raw?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
    return fallback;
  }

  Map<String, dynamic> toSnapshotJson() {
    return {
      'key': key,
      'value': value,
      'category': category.name,
      'platform_scope': platformScope,
      'is_active': isActive,
      'revision': revision,
    };
  }

  factory AppConfigEntry.fromRow(Map<String, dynamic> row) {
    return AppConfigEntry(
      key: (row['key'] ?? '').toString().trim(),
      value: row['value'],
      category: _parseCategory(row['category']),
      platformScope: (row['platform_scope'] ?? row['platform'] ?? 'all')
          .toString()
          .trim(),
      isActive: _readBool(row['is_active'], fallback: true),
      revision: _readInt(row['revision'], fallback: 1),
    );
  }

  static AppConfigCategory _parseCategory(dynamic raw) {
    switch (raw?.toString().trim().toLowerCase()) {
      case 'feature_flag':
      case 'feature-flag':
      case 'featureflag':
      case 'flag':
        return AppConfigCategory.featureFlag;
      case 'operational':
      case 'ops':
      case 'config':
        return AppConfigCategory.operational;
      case 'kill_switch':
      case 'kill-switch':
      case 'killswitch':
        return AppConfigCategory.killSwitch;
      case 'content':
        return AppConfigCategory.content;
      default:
        return AppConfigCategory.unknown;
    }
  }

  static bool _readBool(dynamic raw, {required bool fallback}) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final text = raw?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
    return fallback;
  }

  static int _readInt(dynamic raw, {required int fallback}) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }
}
