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
import 'package:lucide_icons/lucide_icons.dart';
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
    'Pedreiro Flow: Profession -> Description -> Location -> Review',
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

      // STEP 1: Profession
      expect(find.text('Qual profissional você precisa?'), findsOneWidget);

      // Enter "Ped" to trigger autocomplete
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'Ped');
      await tester.pump(); // trigger listeners
      await tester.pump(
        const Duration(milliseconds: 500),
      ); // debounce/animation

      // Select "Pedreiro"
      final pedreiroOption = find.text('Pedreiro');
      await tester.ensureVisible(pedreiroOption);
      await tester.tap(pedreiroOption);
      await tester.pumpAndSettle();

      // Verify selection and click Continue
      expect(find.text('Selecionado: Pedreiro'), findsOneWidget);
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      // STEP 2: Description (Specific to Pedreiro)
      expect(find.text('Descreva o problema'), findsOneWidget);
      expect(
        find.text('Adicionar Mídia (Opcional)'),
        findsOneWidget,
      ); // Media widgets should be present

      final descriptionField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText ==
                'Ex: Chuveiro da suíte não esquenta...',
      );
      await tester.enterText(descriptionField, 'Parede com infiltração');
      await tester.pumpAndSettle();

      final continueBtnStep2 = find.text('Continuar');
      await tester.ensureVisible(continueBtnStep2);
      await tester.tap(continueBtnStep2);
      await tester.pumpAndSettle();

      // STEP 3: Location (Specific to Pedreiro)
      expect(find.text('Onde é o serviço?'), findsOneWidget);
      // Wait for geolocator mock
      await tester.pumpAndSettle();
      expect(find.textContaining('Rua Mock'), findsOneWidget);

      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      // STEP 4: Review
      expect(find.text('Confirmar pedido'), findsOneWidget);
      expect(find.text('Pedreiro'), findsOneWidget);
      // Check 30% calculation
      // _priceEstimated = 150.00
      // _priceUpfront = 45.00 (30%)
      expect(find.textContaining('R\$ 150,00'), findsOneWidget); // Total
      expect(find.textContaining('R\$ 45,00'), findsOneWidget); // Upfront

      // Submit
      final submitBtn = find.text('Confirmar Pedido');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Should navigate to payment
      expect(find.text('Payment Screen ID: 123'), findsOneWidget);
    },
  );

  testWidgets('Barbeiro Flow: Profession -> Service -> Schedule -> Review', (
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

    // STEP 1: Profession
    final searchField = find.byType(TextField);
    await tester.enterText(searchField, 'Bar');
    await tester.pump(const Duration(milliseconds: 500));

    final barbeiroOption = find.text('Barbeiro');
    await tester.ensureVisible(barbeiroOption);
    await tester.tap(barbeiroOption);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    // STEP 2: Service List (Specific to Barbeiro)
    expect(find.text('Escolha o serviço'), findsOneWidget);
    expect(find.text('Corte de Cabelo'), findsOneWidget);

    await tester.tap(find.text('Corte de Cabelo'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    // STEP 3: Schedule (Specific to Barbeiro)
    expect(find.text('Agendamento'), findsOneWidget);
    expect(find.text('Local do Serviço'), findsOneWidget);

    // Check for "Ver no Mapa" button (Route button)
    expect(find.text('Ver no Mapa'), findsOneWidget);
    expect(find.byIcon(LucideIcons.map), findsOneWidget);

    // Select Time Slot
    await tester.tap(find.text('10:00'));
    await tester.pumpAndSettle();

    final confirmBtn = find.text('Confirmar Agendamento');
    await tester.ensureVisible(confirmBtn);

    // Verify button is enabled (has onPressed)
    final btnWidget = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Confirmar Agendamento'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(
      btnWidget.onPressed,
      isNotNull,
      reason: "Confirmar Agendamento button should be enabled",
    );

    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    // Check for error snackbar
    if (find.text('Selecione data e horário.').evaluate().isNotEmpty) {
      fail("Snackbar 'Selecione data e horário.' appeared");
    }

    // STEP 4: Review
    expect(find.text('Confirmar pedido'), findsOneWidget);
    expect(find.text('Barbeiro'), findsOneWidget);
    expect(find.text('Corte de Cabelo'), findsOneWidget);

    // Check 30% calculation for Service (35.00)
    // 30% of 35.00 = 10.50
    expect(find.textContaining('R\$ 35,00'), findsOneWidget); // Total
    expect(
      find.textContaining('R\$ 10,50'),
      findsWidgets,
    ); // Upfront (Found in highlight and description)

    // Submit
    await tester.tap(find.text('Confirmar Pedido'));
    await tester.pumpAndSettle();

    expect(find.text('Payment Screen ID: 123'), findsOneWidget);
  });
}
