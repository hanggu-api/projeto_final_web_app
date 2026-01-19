import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Initialize Firebase for testing with real Firebase instance
Future<void> initializeFirebaseForTesting() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Setup method channel for Firebase initialization
  const MethodChannel channel = MethodChannel('plugins.flutter.io/firebase_core');
  
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'Firebase#initializeCore') {
      return [
        {
          'name': '[DEFAULT]',
          'options': {
            'apiKey': 'AIzaSyBpkfJqBqYvMZVKMx8VGbL0vZqZqZqZqZq',
            'appId': '1:123456789:android:abcdef',
            'messagingSenderId': '123456789',
            'projectId': 'agencia-9e898',
            'storageBucket': 'agencia-9e898.appspot.com',
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
  });

  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSyBpkfJqBqYvMZVKMx8VGbL0vZqZqZqZqZq',
        appId: '1:123456789:android:abcdef',
        messagingSenderId: '123456789',
        projectId: 'agencia-9e898',
        storageBucket: 'agencia-9e898.appspot.com',
      ),
    );
  } catch (e) {
    // Firebase already initialized
    debugPrint('Firebase already initialized: $e');
  }
}
