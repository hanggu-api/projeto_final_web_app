import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:service_101/features/client/service_request_screen.dart';
import 'package:service_101/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_supabase_setup.dart';

// Mock Geolocator
class MockGeolocatorPlatform extends GeolocatorPlatform {
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.always;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    return Position(
      latitude: -23.5505,
      longitude: -46.6333,
      timestamp: DateTime.now(),
      accuracy: 10,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
      floor: 0,
      isMocked: true,
    );
  }
}

class MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}

void main() {
  final runFlowTests = Platform.environment['RUN_APP_FLOWS'] == '1';
  if (!runFlowTests) {
    test(
      'Service request flows skipped (set RUN_APP_FLOWS=1 to run)',
      () {},
      skip: 'Fluxos completos dependem de backend Supabase e dados seed.',
    );
    return;
  }

  late MockClient mockClient;

  setUpAll(() async {
    await initializeSupabaseForTests();
  });

  setUp(() {
    HttpOverrides.global = MockHttpOverrides();
    SharedPreferences.setMockInitialValues({});
    GeolocatorPlatform.instance = MockGeolocatorPlatform();

    mockClient = MockClient((request) async {
      // Mock for reverse geocoding
      if (request.url.path.contains('/geo/reverse')) {
        return http.Response(
          jsonEncode({
            'address': {
              'road': 'Rua Mock',
              'house_number': '123',
              'suburb': 'Centro',
              'city': 'São Paulo',
              'state': 'SP',
            },
            'display_name': 'Rua Mock, 123',
          }),
          200,
        );
      }

      // Mock for service creation
      if (request.url.path.contains('/services') && request.method == 'POST') {
        return http.Response(
          jsonEncode({
            'success': true,
            'service': {'id': 123},
            'id': 123,
          }),
          201,
        );
      }

      // Default mock for token loading or other calls
      if (request.url.path.contains('/auth')) {
        return http.Response(jsonEncode({'token': 'mock_token'}), 200);
      }

      return http.Response('Not Found', 404);
    });

    ApiService().setClient(mockClient);
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  testWidgets(
    'ServiceRequest Mobile flow renders and manual search opens',
    (WidgetTester tester) async {
      // Set screen size
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const ServiceRequestScreen(),
          ),
          GoRoute(
            path: '/payment/:id',
            builder: (context, state) => Scaffold(
              body: Text('Payment Screen ID: ${state.pathParameters['id']}'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.textContaining('Solicitar'), findsWidgets);
      expect(find.text('O que você precisa?'), findsOneWidget);

      final descriptionField = find.widgetWithText(
        TextField,
        'Ex: Pneu furado na rua X...',
      );
      expect(descriptionField, findsOneWidget);
      await tester.enterText(descriptionField, 'Preciso de ajuda com elétrica');
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('O que você precisa?'), findsOneWidget);
    },
  );

  testWidgets('ServiceRequest Fixed flow renders with initial provider', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => ServiceRequestScreen(
            initialProviderId: '101',
            initialProvider: const {
              'id': 101,
              'latitude': -23.5505,
              'longitude': -46.6333,
              'address': 'Rua Mock, 123',
              'full_name': 'Barbearia Mock',
            },
            initialService: const {
              'name': 'Corte de Cabelo',
              'service_type': 'at_provider',
              'price': 35.0,
            },
          ),
        ),
        GoRoute(
          path: '/payment/:id',
          builder: (context, state) => Scaffold(
            body: Text('Payment Screen ID: ${state.pathParameters['id']}'),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Agendamento'), findsOneWidget);
    expect(find.text('Escolha data e horário'), findsOneWidget);
    expect(find.textContaining('Rua Mock'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
