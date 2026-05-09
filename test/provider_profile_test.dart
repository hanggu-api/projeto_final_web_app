import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/features/provider/provider_profile_content.dart';
import 'package:service_101/services/realtime_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import 'dart:async';

// Mock API Response
class MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return createMockHttpClient(context, (request) {
      // Return Profile Data
      if (request.uri.path.contains('/profile/me')) {
        return HttpClientResponseMock(
          statusCode: 200,
          body:
              '{"id": 123, "name": "Provider Test", "email": "test@provider.com", "role": "provider", "created_at": "2023-01-01", "phone": "11999999999", "document": "12345678900", "address": "Rua Teste"}',
        );
      }
      return HttpClientResponseMock(statusCode: 200, body: '{}');
    });
  }
}

// Simple Mock Response classes (minimal implementation)
class HttpClientResponseMock implements HttpClientResponse {
  @override
  final int statusCode;
  final String body;
  HttpClientResponseMock({required this.statusCode, required this.body});

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  // Removed compressionStateEnum as it's not part of the standard interface or handled by compressionState

  @override
  int get contentLength => body.length;
  @override
  HttpHeaders get headers => _MockHeaders();
  @override
  Stream<S> map<S>(S Function(List<int> event) convert) =>
      Stream.value(body.codeUnits).map(convert);
  @override
  Future<E> drain<E>([E? futureValue]) async => futureValue as E;
  @override
  Stream<S> expand<S>(Iterable<S> Function(List<int> element) convert) =>
      Stream.value(body.codeUnits).expand(convert);

  @override
  bool get isRedirect => false;
  @override
  String get reasonPhrase => 'OK';
  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) async => this;
  @override
  List<RedirectInfo> get redirects => [];
  @override
  Stream<List<int>> handleError(
    Function onError, {
    bool Function(dynamic error)? test,
  }) => Stream.value(body.codeUnits);
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.value(body.codeUnits).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<bool> any(bool Function(List<int> element) test) =>
      Stream.value(body.codeUnits).any(test);
  @override
  Stream<List<int>> asBroadcastStream({
    void Function(StreamSubscription<List<int>> subscription)? onListen,
    void Function(StreamSubscription<List<int>> subscription)? onCancel,
  }) => Stream.value(body.codeUnits).asBroadcastStream();
  @override
  Stream<E> asyncExpand<E>(Stream<E>? Function(List<int> event) convert) =>
      Stream.value(body.codeUnits).asyncExpand(convert);
  @override
  Stream<E> asyncMap<E>(FutureOr<E> Function(List<int> event) convert) =>
      Stream.value(body.codeUnits).asyncMap(convert);
  @override
  Stream<R> cast<R>() => Stream.value(body.codeUnits).cast<R>();
  @override
  Future<bool> contains(Object? needle) =>
      Stream.value(body.codeUnits).contains(needle);
  @override
  Future<List<int>> elementAt(int index) =>
      Stream.value(body.codeUnits).elementAt(index);
  @override
  Future<bool> every(bool Function(List<int> element) test) =>
      Stream.value(body.codeUnits).every(test);
  @override
  Future<List<int>> get first => Stream.value(body.codeUnits).first;
  @override
  Future<List<int>> get last => Stream.value(body.codeUnits).last;
  @override
  Future<List<int>> get single => Stream.value(body.codeUnits).single;
  @override
  Future<List<int>> firstWhere(
    bool Function(List<int> element) test, {
    List<int> Function()? orElse,
  }) => Stream.value(body.codeUnits).firstWhere(test, orElse: orElse);
  @override
  Future<S> fold<S>(
    S initialValue,
    S Function(S previous, List<int> element) combine,
  ) => Stream.value(body.codeUnits).fold(initialValue, combine);
  @override
  Future<void> forEach(void Function(List<int> element) action) =>
      Stream.value(body.codeUnits).forEach(action);
  @override
  Future<String> join([String separator = ""]) =>
      Stream.value(body.codeUnits).join(separator);
  @override
  Future<List<int>> lastWhere(
    bool Function(List<int> element) test, {
    List<int> Function()? orElse,
  }) => Stream.value(body.codeUnits).lastWhere(test, orElse: orElse);
  @override
  Future pipe(StreamConsumer<List<int>> streamConsumer) =>
      Stream.value(body.codeUnits).pipe(streamConsumer);
  @override
  Future<List<int>> reduce(
    List<int> Function(List<int> previous, List<int> element) combine,
  ) => Stream.value(body.codeUnits).reduce(combine);
  @override
  Future<List<int>> singleWhere(
    bool Function(List<int> element) test, {
    List<int> Function()? orElse,
  }) => Stream.value(body.codeUnits).singleWhere(test, orElse: orElse);
  @override
  Stream<List<int>> skip(int count) => Stream.value(body.codeUnits).skip(count);
  @override
  Stream<List<int>> skipWhile(bool Function(List<int> element) test) =>
      Stream.value(body.codeUnits).skipWhile(test);
  @override
  Stream<List<int>> take(int count) => Stream.value(body.codeUnits).take(count);
  @override
  Stream<List<int>> takeWhile(bool Function(List<int> element) test) =>
      Stream.value(body.codeUnits).takeWhile(test);
  @override
  Future<List<List<int>>> toList() => Stream.value(body.codeUnits).toList();
  @override
  Future<Set<List<int>>> toSet() => Stream.value(body.codeUnits).toSet();
  @override
  Stream<S> transform<S>(StreamTransformer<List<int>, S> streamTransformer) =>
      Stream.value(body.codeUnits).transform(streamTransformer);
  @override
  Stream<List<int>> where(bool Function(List<int> event) test) =>
      Stream.value(body.codeUnits).where(test);
  @override
  Stream<List<int>> distinct([
    bool Function(List<int> previous, List<int> next)? equals,
  ]) => Stream.value(body.codeUnits);
  @override
  Stream<List<int>> timeout(
    Duration timeLimit, {
    void Function(EventSink<List<int>> sink)? onTimeout,
  }) => Stream.value(body.codeUnits);

  // Cookies interface
  @override
  List<Cookie> get cookies => [];
  @override
  X509Certificate? get certificate => null;
  @override
  HttpConnectionInfo? get connectionInfo => null;
  @override
  Future<Socket> detachSocket() async => throw UnimplementedError();

  @override
  bool get persistentConnection => true;

  @override
  bool get isBroadcast => false;

  @override
  Future<bool> get isEmpty => Stream.value(body.codeUnits).isEmpty;

  @override
  Future<int> get length => Stream.value(body.codeUnits).length;
}

class _MockHeaders implements HttpHeaders {
  @override
  List<String>? operator [](String name) => [];
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void clear() {}
  @override
  void forEach(void Function(String name, List<String> values) action) {}
  @override
  void noFolding(String name) {}
  @override
  void remove(String name, Object value) {}
  @override
  void removeAll(String name) {}
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  String? value(String name) => null;

  @override
  // ignore: unnecessary_overrides
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Helper to create Mock Client
HttpClient createMockHttpClient(
  SecurityContext? context,
  HttpClientResponse Function(HttpClientRequest request) handler,
) {
  final client = _MockHttpClient(handler);
  return client;
}

class _MockHttpClient implements HttpClient {
  final HttpClientResponse Function(HttpClientRequest request) handler;
  _MockHttpClient(this.handler);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    return _MockHttpClientRequest(url, method, handler);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null; // Proxy
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  final Uri uri;
  @override
  final String method;
  final HttpClientResponse Function(HttpClientRequest request) handler;
  _MockHttpClientRequest(this.uri, this.method, this.handler);

  @override
  HttpHeaders get headers => _MockHeaders();
  @override
  void add(List<int> data) {}
  @override
  void write(Object? object) {}
  @override
  Future<HttpClientResponse> close() async {
    return handler(this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null; // Proxy
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Evita subscriptions/canais do Supabase Realtime em widget tests.
    RealtimeService.mockMode = true;
    SharedPreferences.setMockInitialValues({
      'user_role': 'provider',
      'user_id': 123,
      'auth_token': 'mock_token',
    });
    // Não inicializar Supabase aqui: alguns clientes Realtime criam timers (10s)
    // que causam falha "timersPending" ao final dos widget tests.
  });

  tearDownAll(() {
    RealtimeService.mockMode = false;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_role': 'provider',
      'user_id': 123,
      'auth_token': 'mock_token',
    });
    HttpOverrides.global = MockHttpOverrides(); // Enable Mock
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  testWidgets('ProviderProfileContent renders and shows account actions', (
    WidgetTester tester,
  ) async {
    // Setup Router
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(body: ProviderProfileContent()),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) =>
              const Scaffold(body: Text('Login Screen')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    // Wait for future builder (if any)
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // Verify vital info
    // "Meu Perfil" is usually the title in the screen using this content.
    // In content, we expect fields.

    expect(find.text('Nome'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);

    // Scroll down to the current account action actually exposed by the screen.
    final logoutFinder = find.text('SAIR DA CONTA');
    await tester.dragUntilVisible(
      logoutFinder,
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('DESEMPENHO', skipOffstage: false), findsOneWidget);
    expect(logoutFinder, findsOneWidget);

    // Deixa timers curtos completarem para evitar falha "timersPending" no teardown.
    await tester.pump(const Duration(milliseconds: 600));
    // Força dispose da árvore e mais um pump.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
