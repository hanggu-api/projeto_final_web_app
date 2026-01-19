class DataSafety {
  /// Safely converts any value (String, num, null) to a double.
  /// Handles "15", "15,50", 15, 15.5.
  static double safeDouble(dynamic value, {double defaultValue = 0.0}) {
    if (value == null) return defaultValue;
    if (value is num) return value.toDouble();
    if (value is String) {
      if (value.trim().isEmpty) return defaultValue;
      String s = value.trim().replaceAll(',', '.');
      // Remove symbols like 'R$' or whitespace if mixed in
      s = s.replaceAll(RegExp(r'[^0-9\.-]'), ''); 
      return double.tryParse(s) ?? defaultValue;
    }
    return defaultValue;
  }

  /// Safely converts to int.
  static int safeInt(dynamic value, {int defaultValue = 0}) {
    if (value == null) return defaultValue;
    if (value is num) return value.toInt();
    if (value is String) {
      if (value.trim().isEmpty) return defaultValue;
      String s = value.trim().replaceAll(RegExp(r'[^0-9-]'), '');
      return int.tryParse(s) ?? defaultValue;
    }
    return defaultValue;
  }

  /// Safely returns a String, handling nulls.
  static String safeString(dynamic value, {String defaultValue = ''}) {
    if (value == null) return defaultValue;
    return value.toString();
  }
}
