import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Callback = void Function(MethodCall call);

/// Mock Firebase Core for testing
void setupFirebaseAuthMocks([Callback? customHandlers]) {
  TestWidgetsFlutterBinding.ensureInitialized();

  setupFirebaseCoreMocks();
}

/// Setup Firebase Core mocks
Future<void> setupFirebaseCoreMocks() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock Firebase Core
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/firebase_core'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'Firebase#initializeCore') {
        return [
          {
            'name': '[DEFAULT]',
            'options': {
              'apiKey': 'fake-api-key',
              'appId': 'fake-app-id',
              'messagingSenderId': 'fake-sender-id',
              'projectId': 'fake-project-id',
            },
            'pluginConstants': {},
          }
        ];
      }

      if (methodCall.method == 'Firebase#initializeApp') {
        return {
          'name': methodCall.arguments['appName'],
          'options': methodCall.arguments['options'],
          'pluginConstants': {},
        };
      }

      return null;
    },
  );

  // Mock Firebase Auth - Enhanced with all required methods
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/firebase_auth'),
    (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'Auth#registerIdTokenListener':
        case 'Auth#registerAuthStateListener':
          return {'user': null};
        case 'Auth#signInAnonymously':
        case 'Auth#signInWithCredential':
        case 'Auth#signInWithCustomToken':
        case 'Auth#signInWithEmailAndPassword':
          return {
            'user': {
              'uid': 'test-uid',
              'email': 'test@example.com',
              'displayName': 'Test User',
            },
            'additionalUserInfo': {},
          };
        case 'Auth#signOut':
          return null;
        case 'Auth#currentUser':
          return null;
        default:
          return null;
      }
    },
  );
}
