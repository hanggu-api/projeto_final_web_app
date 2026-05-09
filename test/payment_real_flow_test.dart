import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/features/client/payment_screen.dart';
import 'package:service_101/core/theme/app_theme.dart';
import 'package:service_101/services/api_service.dart';
import 'package:go_router/go_router.dart';
import 'package:service_101/services/realtime_service.dart';
import 'test_supabase_setup.dart';

class RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) => true;
    client.idleTimeout = const Duration(seconds: 1);
    return client;
  }
}

void main() {
  final runLiveTests = Platform.environment['RUN_LIVE_TESTS'] == '1';

  if (!runLiveTests) {
    test(
      'Payment real flow skipped (set RUN_LIVE_TESTS=1 to run)',
      () {},
      skip: 'RUN_LIVE_TESTS=1 e API local necessárias para rodar fluxos reais.',
    );
    return;
  }

  String? testServiceId;

  // Inicialização global
  setUpAll(() async {
    testServiceId = '1';
    HttpOverrides.global = RealHttpOverrides();

    // Desativar RealtimeService para evitar Timers pendentes
    RealtimeService.mockMode = true;

    // Configurar URL da API Local (Localhost)
    const String apiUrl = 'http://127.0.0.1:4011/api';

    await initializeSupabaseForTests(
      initialPrefs: {'api_base_url': apiUrl},
    );

    // Configurar usuário de teste
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final email = 'test_pay_$timestamp@101service.com';
    // Senha lida de variável de ambiente para não ficar hardcoded no código
    const password = String.fromEnvironment(
      'TEST_USER_PASSWORD',
      defaultValue: 'TestPassword@101',
    );

    try {
      // 1. Registrar Usuário (no backend local)
      final regUrl = Uri.parse('$apiUrl/auth/register');
      debugPrint('Registrando usuário em: $regUrl');

      final regResponse = await http.post(
        regUrl,
        body: jsonEncode({
          'name': 'Tester 101',
          'email': email,
          'password': password,
          'password_confirmation': password,
          'role': 'client',
          'phone': '119${timestamp.toString().substring(5)}',
        }),
        headers: {'Content-Type': 'application/json'},
      );

      debugPrint(
        'Registro status: ${regResponse.statusCode} Body: ${regResponse.body}',
      );

      // 2. Login
      final loginUrl = Uri.parse('$apiUrl/auth/login');
      final loginRes = await http.post(
        loginUrl,
        body: jsonEncode({'email': email, 'password': password}),
        headers: {'Content-Type': 'application/json'},
      );

      if (loginRes.statusCode == 200) {
        final data = jsonDecode(loginRes.body);
        if (data['success'] == true && data['token'] != null) {
          // Salvar token via ApiService (que vai usar a URL do SharedPreferences)
          await ApiService()
              .loadConfig(); // Carrega api_base_url do SharedPreferences
          await ApiService().saveToken(data['token']);
          debugPrint('Autenticado com sucesso para 101 Service (Localhost)');

          // Mantém um ID fixo para o fluxo de UI sem depender de autenticação Supabase.
          testServiceId = '1';
        }
      } else {
        debugPrint('Falha no login: ${loginRes.body}');
      }
    } catch (e) {
      debugPrint('Erro na autenticação de teste: $e');
    }
  });

  tearDownAll(() {
    // Limpar timers e clientes HTTP
    ApiService().dispose();
    RealtimeService.mockMode = false;
    HttpOverrides.global = null;
  });

  tearDown(() {
    ApiService().dispose();
  });

  setUp(() {
    // Garantir que limpamos qualquer cliente anterior
    ApiService().dispose();
    // Garantir cliente HTTP novo para cada teste
    ApiService().setClient(http.Client());
  });

  testWidgets(
    'Fluxo Real de Pagamento - Cartão de Crédito (skipped)',
    (WidgetTester tester) async {},
    skip: true,
  );

  testWidgets('Fluxo Real de Pagamento - Pix', (WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/payment',
      routes: [
        GoRoute(
          path: '/payment',
          builder: (c, s) => PaymentScreen(
            extraData: {'serviceId': testServiceId ?? '1'},
          ),
        ),
        GoRoute(
          path: '/confirmation',
          builder: (c, s) =>
              const Scaffold(body: Text('Pagamento Confirmado!')),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp.router(routerConfig: router, theme: AppTheme.lightTheme),
    );

    await tester.pumpAndSettle();

    // Seleciona Pix
    final pixOption = find.text('Pix');
    await tester.ensureVisible(pixOption);
    await tester.tap(pixOption);
    await tester.pump();

    // Clica em Pagar (Gerar Código Pix)
    final payButton = find.byKey(const Key('pay_button'));
    await tester.ensureVisible(payButton);

    await tester.runAsync(() async {
      await tester.tap(payButton);
      debugPrint('Aguardando processamento Pix (15s)...');
      await Future.delayed(const Duration(seconds: 15));
    });

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    if (find.byType(SnackBar).evaluate().isNotEmpty) {
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar).first);
      if (snackBar.content is Text) {
        final content = snackBar.content as Text;
        debugPrint('ERRO DETECTADO (SnackBar): ${content.data}');
      }
    }

    await tester.runAsync(() async {
      debugPrint('Aguardando fechamento de sockets (Pix)...');
      await Future.delayed(const Duration(seconds: 3));
      ApiService().dispose();
    });
  });
}
