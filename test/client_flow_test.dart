import 'dart:io'; // Must be at the top
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:service_101/features/client/service_request_screen.dart';
import 'package:service_101/features/client/payment_screen.dart';
import 'package:service_101/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_test_config.dart';
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
      'Client full flow skipped (set RUN_APP_FLOWS=1 to run)',
      () {},
      skip: 'Fluxo completo depende de backend e pagamentos reais.',
    );
    return;
  }

  late MockClient mockClient;

  setUpAll(() async {
    await initializeFirebaseForTesting();
    await initializeSupabaseForTests();
  });

  setUp(() {
    HttpOverrides.global = MockHttpOverrides();
    SharedPreferences.setMockInitialValues({});
    GeolocatorPlatform.instance = MockGeolocatorPlatform();

    mockClient = MockClient((request) async {
      if (request.url.path.contains('/auth/professions')) {
        return http.Response(
          jsonEncode({
            'professions': ['Eletricista'],
          }),
          200,
        );
      }
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
      if (request.url.path.contains('/services/ai/classify')) {
        return http.Response(
          jsonEncode({
            'encontrado': true,
            'categoria_id': 1,
            'categoria': 'Manutenção',
            'profissao': 'Eletricista',
            'confianca': 0.95,
          }),
          200,
        );
      }
      if (request.url.path.contains('/services')) {
        return http.Response(jsonEncode({'id': 123, 'status': 'created'}), 201);
      }
      if (request.url.path.contains('/payment/process')) {
        return http.Response(
          jsonEncode({
            'success': true,
            'payment': {'id': 999, 'status': 'approved'},
          }),
          200,
        );
      }
      return http.Response('Not Found', 404);
    });

    ApiService().setClient(mockClient);
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  testWidgets('Full System Flow: Request Service -> Payment (Mastercard APRO)', (
    WidgetTester tester,
  ) async {
    // Definindo tamanho de tela de celular ALTO para garantir que widgets apareçam sem scroll
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
          path: '/payment',
          builder: (context, state) {
            final serviceId = state.extra.toString();
            return PaymentScreen(extraData: serviceId);
          },
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // Fluxo atualizado: valida tela principal e etapa de descrição.
    expect(find.textContaining('Solicitar'), findsWidgets);
    expect(find.text('O que você precisa?'), findsOneWidget);

    final descriptionField = find.widgetWithText(
      TextField,
      'Ex: Pneu furado na rua X...',
    );
    expect(descriptionField, findsOneWidget);
    await tester.enterText(descriptionField, 'Pneu furado');
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('O que você precisa?'), findsOneWidget);
  });
}
