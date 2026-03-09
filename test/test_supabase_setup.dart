import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:service_101/core/config/supabase_config.dart';

Future<void> initializeSupabaseForTests({
  Map<String, Object>? initialPrefs,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(initialPrefs ?? {});
  await SupabaseConfig.initialize(disableAutoRefreshToken: true);
}
