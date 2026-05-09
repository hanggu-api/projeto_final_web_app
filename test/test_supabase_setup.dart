import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:service_101/core/config/supabase_config.dart';

Future<void> initializeSupabaseForTests({
  Map<String, Object>? initialPrefs,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final mockStore = <String, String>{};

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'read':
        return mockStore[call.arguments['key'] as String];
      case 'write':
        mockStore[call.arguments['key'] as String] =
            call.arguments['value'] as String;
        return null;
      case 'delete':
        mockStore.remove(call.arguments['key'] as String);
        return null;
      case 'deleteAll':
        mockStore.clear();
        return null;
      case 'readAll':
        return Map<String, String>.from(mockStore);
      case 'containsKey':
        return mockStore.containsKey(call.arguments['key'] as String);
      default:
        return null;
    }
  });

  SharedPreferences.setMockInitialValues(initialPrefs ?? {});
  await SupabaseConfig.initialize(
    disableAuthAutoRefresh: true,
    detectSessionInUri: false,
  );
}
