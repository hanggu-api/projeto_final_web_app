import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/features/provider/provider_home_mobile.dart';
import 'package:service_101/features/provider/widgets/provider_service_card.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    const geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(geolocatorChannel, (call) async {
          if (call.method == 'getCurrentPosition') {
            return {
              'latitude': -5.5262,
              'longitude': -47.4747,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'accuracy': 1.0,
              'altitude': 0.0,
              'heading': 0.0,
              'speed': 0.0,
              'speed_accuracy': 0.0,
            };
          }
          if (call.method == 'checkPermission') return 3;
          if (call.method == 'isLocationServiceEnabled') return true;
          return null;
        });
  });

  Widget buildCard({
    required Map<String, dynamic> service,
    bool showScheduleAction = false,
    bool isFocusMode = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ProviderServiceCard(
          service: service,
          showScheduleAction: showScheduleAction,
          isFocusMode: isFocusMode,
          onSchedule: (_, _) async {},
        ),
      ),
    );
  }

  Map<String, dynamic> serviceWithStatus(String status) => {
    'id': 'svc-$status',
    'status': status,
    'task_name': 'Copia de Chave Tetra',
    'description': 'Copia de Chave Tetra',
    'address': 'Rua Para 639',
    'price_estimated': 38.25,
    'provider_id': 123,
  };

  testWidgets('mostra agendamento em disponiveis mesmo com provider_id', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildCard(
        showScheduleAction: true,
        service: serviceWithStatus('open_for_schedule'),
      ),
    );

    expect(find.text('AGENDAR SERVIÇO'), findsOneWidget);
  });

  testWidgets('mostra agendamento para aliases de oportunidade disponivel', (
    tester,
  ) async {
    for (final status in const [
      'pending',
      'searching',
      'searching_provider',
      'waiting_provider',
    ]) {
      await tester.pumpWidget(
        buildCard(showScheduleAction: true, service: serviceWithStatus(status)),
      );

      expect(find.text('AGENDAR SERVIÇO'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('nao mostra agendamento para proposta enviada pelo prestador', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildCard(
        showScheduleAction: true,
        service: {
          ...serviceWithStatus('schedule_proposed'),
          'provider_id': 123,
          'schedule_proposed_by_user_id': 123,
          'scheduled_at': '2026-05-09T17:10:00Z',
        },
      ),
    );

    expect(find.text('AGENDAR SERVIÇO'), findsNothing);
    expect(find.text('ALTERAR AGENDAMENTO'), findsNothing);
  });

  testWidgets('nao mostra agendamento quando limite do prestador acabou', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildCard(
        showScheduleAction: true,
        service: {
          ...serviceWithStatus('open_for_schedule'),
          'schedule_provider_rounds': 5,
          'remainingProviderRounds': 0,
        },
      ),
    );

    expect(find.text('AGENDAR SERVIÇO'), findsNothing);
  });

  testWidgets('mostra alterar agendamento para contraproposta do cliente', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildCard(
        service: {
          ...serviceWithStatus('schedule_proposed'),
          'provider_id': 123,
          'schedule_proposed_by_user_id': 456,
          'scheduled_at': '2026-05-09T17:10:00Z',
        },
      ),
    );

    expect(find.text('ALTERAR AGENDAMENTO'), findsOneWidget);
  });

  testWidgets('no tracking nao duplica bloco de contraproposta do cliente', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildCard(
        isFocusMode: true,
        service: {
          ...serviceWithStatus('schedule_proposed'),
          'provider_id': 123,
          'schedule_proposed_by_user_id': 456,
          'scheduled_at': '2026-05-09T17:10:00Z',
          'schedule_expires_at': '2026-05-09T17:40:00Z',
        },
      ),
    );

    expect(find.textContaining('Cliente propôs:'), findsNothing);
    expect(find.text('ALTERAR AGENDAMENTO'), findsNothing);
    expect(find.text('CONTRA-PROPOSTA DO CLIENTE'), findsOneWidget);
    expect(find.text('ACEITAR AGENDAMENTO'), findsOneWidget);
  });

  test('filtra negociacoes de agenda da lista de disponiveis', () {
    final filtered = filterProviderMobileAvailableItems([
      {'id': 'available', 'status': 'open_for_schedule'},
      {'id': 'proposal', 'status': 'schedule_proposed'},
      {'id': 'scheduled', 'status': 'scheduled'},
      {'id': 'running', 'status': 'in_progress', 'provider_id': 123},
      {
        'id': 'confirming',
        'status': 'awaiting_confirmation',
        'provider_id': 123,
      },
    ]);

    expect(filtered.map((item) => item['id']), ['available']);
  });

  test('permite recuperar tracking quando home volta para o mesmo servico', () {
    expect(
      shouldRedirectProviderMobileToActiveService(
        lastRedirectedServiceId: 'svc-1',
        selectedServiceId: 'svc-1',
        currentLocation: '/provider-home',
        targetLocation: '/provider-active/svc-1',
      ),
      isTrue,
    );

    expect(
      shouldRedirectProviderMobileToActiveService(
        lastRedirectedServiceId: 'svc-1',
        selectedServiceId: 'svc-1',
        currentLocation: '/provider-active/svc-1',
        targetLocation: '/provider-active/svc-1',
      ),
      isFalse,
    );
  });
}
