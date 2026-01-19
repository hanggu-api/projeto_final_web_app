
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:service_101/features/provider/provider_home_screen.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

// Mock Client
class MockClient extends Mock implements http.Client {}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Mock Firebase Core
    const MethodChannel channel = MethodChannel('plugins.flutter.io/firebase_core');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'FirebaseApp#initializeApp') {
          return {
            'name': methodCall.arguments['appName'],
            'options': methodCall.arguments['options'],
            'pluginConstants': {},
          };
        }
        return null;
      },
    );
    
    // Mock Messaging
    const MethodChannel messagingChannel = MethodChannel('plugins.flutter.io/firebase_messaging');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      messagingChannel,
      (MethodCall methodCall) async {
        return null;
      },
    );

    // Mock Geolocator
    const MethodChannel geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      geolocatorChannel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'checkPermission') {
          return 3; // LocationPermission.always (index 3) or whileInUse
        }
        if (methodCall.method == 'isLocationServiceEnabled') {
          return true;
        }
        return null;
      },
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'user_role': 'provider', 'user_id': 123});
  });

  testWidgets('ProviderHomeScreen renders correctly', (WidgetTester tester) async {
    // We expect the screen to try loading data. 
    // Since we don't fully mock ApiService here, it might error or show loading.
    // We just want to ensure it builds without crashing.
    
    await tester.pumpWidget(const MaterialApp(
      home: ProviderHomeScreen(loadOnInit: false, connectRealtime: false),
    ));
    
    // Verify basic structure
    expect(find.byType(Scaffold), findsOneWidget);
    // "Saldo disponível" should be present in the header
    expect(find.text('Saldo disponível'), findsOneWidget);
  });
}
