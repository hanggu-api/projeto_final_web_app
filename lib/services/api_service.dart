import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:uuid/uuid.dart';
import 'realtime_service.dart';
import 'notification_service.dart';
import 'analytics_service.dart';
import '../core/utils/logger.dart';
import '../core/config/supabase_config.dart';
import 'remote_config_service.dart';

class ApiService {
  // URLs Legadas (Mantidas comentadas para referência se necessário)
  // static const String _androidEmulatorApiUrl = 'http://10.0.2.2:4011/api';
  // static const String _iosRealDeviceApiUrl = 'http://localhost:4011/api';

  // static const String _vercelApiUrl = 'https://backend-pi-ivory-11.vercel.app';
  // static const String _prodApiUrl = _vercelApiUrl;

  static String get baseUrl {
    // URL das Edge Functions do Supabase (Novo)
    return 'https://mroesvsmylnaxelrhqtl.supabase.co/functions/v1';
  }

  static String fixUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    // Como estamos 100% online, não precisamos mais trocar localhost por IPs de emulador
    return url;
  }

  String? _token;
  String? _role;
  int? _userId;
  bool _isMedical = false;
  bool _isFixedLocation = false;

  // FCM Token
  String? _fcmToken;
  String? get fcmToken => _fcmToken;
  void setFcmToken(String token) => _fcmToken = token;

  final _secureStorage = const FlutterSecureStorage();
  final String _tokenKey = 'auth_token';

  // Cache for media bytes
  final Map<String, Future<Uint8List>> _mediaBytesCache = {};

  bool get isMedical => _isMedical;
  bool get isFixedLocation => _isFixedLocation;
  String? get role => _role;
  int? get userId => _userId;
  int? get currentUserId => _userId;

  http.Client _client = http.Client();

  /// Sets a custom HTTP client (useful for testing)
  void setClient(http.Client client) {
    _client = client;
  }

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() {
    // Escuta mudanças de sessão no Supabase Auth
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        _token = session.accessToken;

        // Se o userId local estiver nulo e temos uma sessão,
        // ou se acabou de ocorrer um login (ex: Google OAuth), sincronizamos.
        if (_userId == null || data.event == AuthChangeEvent.signedIn) {
          debugPrint(
            '🔄 [ApiService] Auto-syncing user profile after Auth event: ${data.event}',
          );
          loginWithFirebase(session.accessToken).catchError((e) {
            debugPrint('❌ [ApiService] Erro no auto-sync: $e');
          });
        }
      } else {
        _token = null;
        _userId = null;
        _role = null;
      }
    });
  }

  Future<String?> _getToken() async {
    // Return cached token se disponível (Supabase SDK cuida do refresh p/ nós majoritariamente)
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      _token = session.accessToken;
      return _token;
    }

    // Fallback: tentar ler do storage caso o SDK do Supabase não inicializou a frio ainda
    _token ??= await _secureStorage.read(key: _tokenKey);
    return _token;
  }

  // --- Appointments / Scheduling ---

  Future<List<Map<String, dynamic>>> getProviderSlots(
    int providerId, {
    String? date,
  }) async {
    // Agora buscamos direto na tabela de agendamentos do Supabase
    final response = await Supabase.instance.client
        .from('appointments')
        .select('*')
        .eq('provider_id', providerId)
        .gte(
          'start_time',
          date ?? DateTime.now().toIso8601String().split('T')[0],
        );

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> markSlotBusy(DateTime startTime) async {
    if (_userId == null) throw Exception('Not authenticated');
    await Supabase.instance.client.from('appointments').insert({
      'provider_id': _userId,
      'start_time': startTime.toIso8601String(),
      'end_time': startTime.add(const Duration(hours: 1)).toIso8601String(),
      'status': 'confirmed', // Marcar como ocupado
    });
  }

  Future<void> bookSlot(int providerId, DateTime startTime) async {
    if (_userId == null) throw Exception('Not authenticated');
    await Supabase.instance.client.from('appointments').insert({
      'provider_id': providerId,
      'client_id': _userId,
      'start_time': startTime.toIso8601String(),
      'end_time': startTime.add(const Duration(hours: 1)).toIso8601String(),
      'status': 'waiting_payment',
    });
  }

  Future<void> confirmSchedule(String serviceId, DateTime time) async {
    await Supabase.instance.client
        .from('service_requests_new')
        .update({
          'scheduled_at': time.toIso8601String(),
          'status': 'scheduled',
          'status_updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', serviceId);
  }

  Future<void> markClientDeparting(String serviceId) async {
    debugPrint(
      '📍 [ApiService] Marking client departing for service: $serviceId',
    );
    await Supabase.instance.client
        .from('service_requests_new')
        .update({
          'status': 'client_departing',
          'status_updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', serviceId);
  }

  Future<void> markClientArrived(String serviceId) async {
    debugPrint(
      '📍 [ApiService] Marking client arrived for service: $serviceId',
    );
    await Supabase.instance.client
        .from('service_requests_new')
        .update({
          'status': 'client_arrived',
          'arrived_at': DateTime.now().toIso8601String(),
          'status_updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', serviceId);
  }

  Future<void> confirmPaymentManual(String serviceId) async {
    debugPrint(
      '💰 [ApiService] Confirming manual payment for service: $serviceId',
    );
    await Supabase.instance.client
        .from('service_requests_new')
        .update({
          'payment_remaining_status': 'paid_manual',
          'status_updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', serviceId);
  }

  Future<void> deleteAppointment(String appointmentId) async {
    await Supabase.instance.client
        .from('appointments')
        .delete()
        .eq('id', appointmentId);
  }

  Future<List<Map<String, dynamic>>> getScheduleConfig() async {
    if (_userId == null) return [];
    final response = await Supabase.instance.client
        .from('providers')
        .select('schedule_configs')
        .eq('user_id', _userId!)
        .single();

    final configs = response['schedule_configs'];
    if (configs is List) {
      return List<Map<String, dynamic>>.from(configs);
    }
    return [];
  }

  Future<void> saveScheduleConfig(List<Map<String, dynamic>> configs) async {
    if (_userId == null) throw Exception('Not authenticated');
    await Supabase.instance.client
        .from('providers')
        .update({'schedule_configs': configs})
        .eq('user_id', _userId!);
  }

  Future<List<Map<String, dynamic>>> getScheduleExceptions() async {
    if (_userId == null) return [];
    final response = await Supabase.instance.client
        .from('provider_schedule_exceptions')
        .select('*')
        .eq('provider_id', _userId!);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> saveScheduleExceptions(List<dynamic> exceptions) async {
    if (_userId == null) throw Exception('Not authenticated');

    // Primeiro limpamos as antigas para este prestador (opcional, ou upsert)
    // Para simplificar, faremos um fresh insert das novas
    await Supabase.instance.client
        .from('provider_schedule_exceptions')
        .delete()
        .eq('provider_id', _userId!);

    final rows = exceptions
        .map(
          (e) => {
            'provider_id': _userId,
            'date': e['date'],
            'is_available': e['is_available'] ?? false,
            'reason': e['reason'],
          },
        )
        .toList();

    await Supabase.instance.client
        .from('provider_schedule_exceptions')
        .insert(rows);
  }

  Future<void> autoDetectBaseUrl() async {
    // FORCE PRODUCTION URL FOR DEBUG APK AS REQUESTED
    /*
    debugPrint(
      'API Service: Auto-detect disabled. Using production URL: https://cardapyia.com/api',
    );
    return;
    */

    /*
    if (kIsWeb) return; // No auto-detect for web
    if (_overrideBaseUrl != null) return;

    final candidates = [
      'http://10.0.2.2:4011/api', // Android Emulator
      'http://localhost:4011/api', // iOS Simulator / ADB reverse
      // 'http://192.168.1.4:4011/api', // IP da máquina local (detectado)
      // 'http://192.168.1.X:4011/api', // Caso o IP mude, ajuste aqui
    ];

    debugPrint('API Service: Auto-detecting base URL...');

    for (final url in candidates) {
      try {
        debugPrint('API Service: Testing $url...');
        final res = await _client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 2));

        // Se receber qualquer resposta (mesmo erro de auth/404), o servidor está lá
        if (res.statusCode < 503) {
          debugPrint('API Service: Found active server at $url');
          await setBaseUrl(url);
          return;
        }
      } catch (_) {
        // Ignora erros de conexão/timeout e tenta o próximo
      }
    }

    debugPrint('API Service: No local server found, keeping default.');
    */
  }

  Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', url);
  }

  String? get currentToken => _token;

  Future<void> loadConfig() async {
    // FORCE VERCEL URL - Ignore stored local IP
    /*
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('api_base_url');
    if (url != null) {
      _overrideBaseUrl = url;
    }
    */
  }

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = await _secureStorage.read(key: _tokenKey);
    _userId = prefs.getInt('user_id');
    _role = prefs.getString('user_role');
    _isMedical = prefs.getBool('is_medical') ?? false;
    _isFixedLocation = prefs.getBool('is_fixed_location') ?? false;
  }

  // Fuel price cache
  final Map<String, _FuelCacheItem> _fuelCache = {};
  static const Duration _fuelCacheTTL = Duration(hours: 6);

  Future<Map<String, dynamic>> _getCachedFuel(
    String key,
    Future<Map<String, dynamic>> Function() fetcher,
  ) async {
    final now = DateTime.now();
    if (_fuelCache.containsKey(key)) {
      final item = _fuelCache[key]!;
      if (now.isBefore(item.expiry)) {
        return item.data;
      }
    }
    final data = await fetcher();
    if (data.isNotEmpty) {
      _fuelCache[key] = _FuelCacheItem(
        data: data,
        expiry: now.add(_fuelCacheTTL),
      );
    }
    return data;
  }

  Future<void> saveToken(String token) async {
    _token = token;
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  void setUserId(int id) {
    _userId = id;
  }

  Future<void> clearToken() async {
    try {
      if (_token != null) {
        // await post('/auth/logout', {}); // Legacy 404 - Supabase handles logout
        // Fire & Forget: Remova token do FCM do db
        final fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null) {
          unawaited(unregisterDeviceToken(fcmToken));
        }
      }
    } catch (_) {}

    AnalyticsService().logEvent('APP_LOGGED_OUT');
    await AnalyticsService().clearSession();

    // 1. Unregister device token BEFORE logging out
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await unregisterDeviceToken(token);
      }
      await NotificationService().deleteToken();
    } catch (e) {
      debugPrint('ApiService: Error unregistering token before logout: $e');
    }

    _token = null;
    _userId = null;
    _role = null;
    _isMedical = false;
    _isFixedLocation = false;

    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.delete(key: _tokenKey);
    await prefs.remove('user_id');
    await prefs.remove('user_role');
    await prefs.remove('is_medical');
    await prefs.remove('is_fixed_location');
  }

  void dispose() {
    _client.close();
  }

  bool get isLoggedIn => Supabase.instance.client.auth.currentUser != null;

  /// Classifica um texto usando a Edge Function ai-classify (Sprint 2: substitui POST /services/ai/classify)
  Future<Map<String, dynamic>> classifyService(String text) async {
    return await invokeEdgeFunction('ai-classify', {'text': text});
  }

  /// Geocodificação reversa via Edge Function geo (Sprint 2: substitui GET /geo/reverse)
  Future<Map<String, dynamic>> reverseGeocode(double lat, double lon) async {
    final result = await invokeEdgeFunction('geo', null, {
      'lat': lat.toString(),
      'lon': lon.toString(),
      'path': 'reverse',
    });
    if (result is Map<String, dynamic>) return result;
    return {};
  }

  /// Busca de endereços via Edge Function geo (Sprint 2: substitui GET /geo/search)
  Future<List<dynamic>> searchAddress(
    String query, {
    double? lat,
    double? lon,
    double? radiusKm,
  }) async {
    final params = <String, String>{'q': query, 'path': 'search'};
    if (lat != null && lon != null) {
      params['proximity'] = '$lat,$lon';
      params['radius'] = (radiusKm ?? 50).toString();
    }
    final result = await invokeEdgeFunction('geo', null, params);
    if (result is List) return result;
    return [];
  }

  /// Registra um endereço selecionado no banco de dados próprio (Crowdsourcing)
  Future<void> registerAddressInRegistry({
    required String fullAddress,
    String? streetName,
    String? streetNumber,
    String? neighborhood,
    String? city,
    String? stateCode,
    String? poiName,
    required double lat,
    required double lon,
    String? category,
  }) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;

      await client.from('addresses_registry').upsert({
        'full_address': fullAddress,
        'street_name': streetName,
        'street_number': streetNumber,
        'neighborhood': neighborhood,
        'city': city ?? 'Imperatriz',
        'state_code': stateCode ?? 'MA',
        'poi_name': poiName,
        'lat': lat,
        'lon': lon,
        'category': category,
        'contributor_id': userId,
        'last_seen': DateTime.now().toIso8601String(),
      }, onConflict: 'lat,lon');

      debugPrint('📍 [GeoRegistry] Local registrado/atualizado: $fullAddress');
    } catch (e) {
      // Falha silenciosa para não interromper a UX do usuário
      debugPrint('⚠️ [GeoRegistry] Erro ao registrar local: $e');
    }
  }

  Map<String, String> get authHeaders => _headers;

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
      headers['apikey'] = SupabaseConfig.anonKey;
    } else {
      // Fallback para endpoints públicos como /geo
      headers['Authorization'] = 'Bearer ${SupabaseConfig.anonKey}';
      headers['apikey'] = SupabaseConfig.anonKey;
    }
    return headers;
  }

  /// Fetches the structured list of Professions -> Services from the Backend
  /// Returns a `Map<String, List<Map<String, dynamic>>>`
  Future<Map<String, List<Map<String, dynamic>>>> getServicesMap() async {
    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('professions')
          .select('id, name, service_categories!inner(name)');

      final Map<String, List<Map<String, dynamic>>> result = {};

      for (var item in (response as List)) {
        final categoryName =
            item['service_categories']?['name']?.toString() ?? 'Geral';
        if (!result.containsKey(categoryName)) {
          result[categoryName] = [];
        }
        result[categoryName]!.add({'id': item['id'], 'name': item['name']});
      }

      return result;
    } catch (e) {
      debugPrint('Error fetching services map: $e');
      return {};
    }
  }

  Future<List<dynamic>> getServices() async {
    try {
      if (_userId == null) return [];

      final client = Supabase.instance.client;
      final response = await client
          .from('service_requests_new')
          .select(
            '*, client:users!client_id(*), provider:providers!provider_id(users!user_id(*)), category:service_categories!category_id(name)',
          )
          .or('client_id.eq.$_userId,provider_id.eq.$_userId')
          .order('created_at', ascending: false);

      return response as List<dynamic>;
    } catch (e) {
      debugPrint('Error fetching services: $e');
      return [];
    }
  }

  /// Invoca uma Supabase Edge Function
  /// [functionName] é o nome da função (ex: 'ai-classify', 'geo')
  /// [body] é o JSON body (para POST)
  /// [queryParams] são parâmetros de query (para GET)
  Future<dynamic> invokeEdgeFunction(
    String functionName, [
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
  ]) async {
    try {
      final client = Supabase.instance.client;
      final response = await client.functions
          .invoke(
            functionName,
            body: body,
            queryParameters: queryParams,
            method: body != null ? HttpMethod.post : HttpMethod.get,
          )
          .timeout(const Duration(seconds: 30));

      return response.data;
    } on TimeoutException {
      throw ApiException(
        message: 'A função $functionName demorou muito a responder (Timeout)',
        statusCode: 408,
      );
    } catch (e) {
      AppLogger.erro('❌ [EdgeFn] $functionName falhou', e);
      throw ApiException(
        message: 'Erro ao processar serviço inteligente ($functionName)',
        statusCode: 500,
      );
    }
  }

  Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      // Ensure token is fresh before request
      await _getToken();

      AppLogger.api('🚀 [POST] $endpoint');
      // debugPrint('🚀 [POST] Body: ${jsonEncode(body)}'); // Apenas se necessário

      final response = await _client
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));

      AppLogger.sucesso('✅ [POST] $endpoint (Status: ${response.statusCode})');
      return _handleResponse(response);
    } on TimeoutException {
      throw ApiException(
        message: 'Servidor demorou a responder',
        statusCode: 408,
      );
    } catch (e) {
      AppLogger.erro('❌ [POST] $endpoint Falhou', e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> put(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    try {
      // Ensure token is fresh before request
      await _getToken();

      final response = await _client
          .put(
            Uri.parse('$baseUrl$endpoint'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } on TimeoutException {
      throw ApiException(
        message: 'Servidor demorou a responder',
        statusCode: 408,
      );
    }
  }

  Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      // Ensure token is fresh before request
      await _getToken();

      final response = await _client
          .get(Uri.parse('$baseUrl$endpoint'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } on TimeoutException {
      throw ApiException(
        message: 'Servidor demorou a responder',
        statusCode: 408,
      );
    }
  }

  Future<Map<String, dynamic>> delete(
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    try {
      // Ensure token is fresh before request
      await _getToken();

      final response = await _client
          .delete(
            Uri.parse('$baseUrl$endpoint'),
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } on TimeoutException {
      throw ApiException(
        message: 'Servidor demorou a responder',
        statusCode: 408,
      );
    }
  }

  Future<http.Response> postRaw(
    String endpoint,
    List<Map<String, dynamic>> batchBody,
  ) async {
    await _getToken();
    return await _client
        .post(
          Uri.parse('$baseUrl$endpoint'),
          headers: _headers,
          body: jsonEncode(batchBody),
        )
        .timeout(const Duration(seconds: 30));
  }

  Future<http.Response> getRaw(
    String endpoint, {
    Map<String, String>? extraHeaders,
  }) async {
    final headers = {..._headers, if (extraHeaders != null) ...extraHeaders};
    return await http.get(Uri.parse('$baseUrl$endpoint'), headers: headers);
  }

  // --- Media & Storage ---

  // Duplicate methods removed to fix conflict
  // uploadServiceImage, uploadServiceVideo, uploadServiceAudio are defined with more options below

  Future<void> registerDeviceToken(
    String token,
    String platform, {
    double? latitude,
    double? longitude,
  }) async {
    try {
      if (_userId == null) return;

      final client = Supabase.instance.client;
      await client
          .from('users')
          .update({
            'fcm_token': token,
            'last_seen_at': DateTime.now().toIso8601String(),
          })
          .eq('id', _userId!);

      // Também atualizar a tabela de localização se for prestador (provider)
      // Motoristas (driver) usam a tabela driver_locations via UberService
      if (_role == 'provider' || _isMedical || _isFixedLocation) {
        await client.from('provider_locations').upsert({
          'provider_id': _userId!,
          'latitude': latitude,
          'longitude': longitude,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('Error registering device token: $e');
    }
  }

  Future<void> unregisterDeviceToken(String token) async {
    try {
      if (_userId == null) return;
      await Supabase.instance.client
          .from('users')
          .update({'fcm_token': null})
          .eq('id', _userId!);
    } catch (e) {
      debugPrint('Error unregistering device token: $e');
    }
  }

  // uploadChatMedia removed (unused)

  Future<void> uploadContestEvidence(
    String serviceId, {
    required String type, // 'photo', 'video', 'audio'
    required List<int> fileBytes,
    required String filename,
    required String mimeType,
  }) async {
    // Fase 7: Usar Supabase Storage + SDK em vez do backend legado
    final url = await uploadToCloud(
      fileBytes,
      filename: filename,
      serviceId: serviceId,
      type: 'contest',
    );

    // Registrar evidência diretamente na tabela service_disputes
    if (_userId != null) {
      try {
        await Supabase.instance.client.from('service_disputes').upsert({
          'service_id': serviceId,
          'type': type,
          'evidence_url': url,
          'user_id': _userId,
          'created_at': DateTime.now().toIso8601String(),
        });
        debugPrint(
          '✅ [ApiService] Evidência de contestação registrada no Supabase',
        );
      } catch (e) {
        debugPrint('⚠️ [ApiService] Erro ao salvar evidência no Supabase: $e');
        // Não re-throw: upload já foi feito, salvar é secundário
      }
    }
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (e) {
      final bodyPrefix = response.body.length > 500
          ? response.body.substring(0, 500)
          : response.body;
      // Log reduced for production
      debugPrint(
        'ERRO DECODE JSON [${response.request?.url}] (Status ${response.statusCode}): $bodyPrefix',
      );
      throw ApiException(
        message:
            'Resposta inválida do servidor (Status ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    Map<String, dynamic> data;

    if (decoded is Map<String, dynamic>) {
      data = decoded;
    } else {
      data = <String, dynamic>{'raw': decoded};
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    if (response.statusCode == 401) {
      unawaited(clearToken());
    }

    final msg =
        (data['message'] ?? data['error'] ?? 'Erro ${response.statusCode}')
            .toString();
    throw ApiException(message: msg, statusCode: response.statusCode);
  }

  // Removed manual check helpers as logic moved to backend

  Future<Map<String, dynamic>> register({
    required String
    token, // Token não mais estritamente necessário se já logado
    required String name,
    required String email,
    String? phone,
    String role = 'client',
    String? documentType,
    String? documentValue,
    String? commercialName,
    String? address,
    double? latitude,
    double? longitude,
    List<dynamic>? professions,
    int? vehicleTypeId,
    String? vehicleBrand,
    String? vehicleModel,
    int? vehicleYear,
    String? vehicleColor,
    int? vehicleColorHex,
    String? vehiclePlate,
    String? pixKey,
  }) async {
    final client = Supabase.instance.client;
    final currentUser = client.auth.currentUser;
    if (currentUser == null) throw Exception('Não logado no Supabase');

    try {
      // 1. Inserir/Atualizar em public.users
      // Usar supabase_uid como chave de conflito, pois o trigger handle_new_user
      // já insere por supabase_uid.
      final userRow = await client
          .from('users')
          .upsert({
            'supabase_uid': currentUser.id,
            'email': email,
            'full_name': name,
            'role': role,
            'phone': phone,
            if (pixKey != null && pixKey.isNotEmpty) 'pix_key': pixKey,
          }, onConflict: 'supabase_uid')
          .select()
          .single();

      _userId = userRow['id'];
      _role =
          role; // Usar o role que foi enviado, não o que retornou (pode estar desatualizado)

      // Garantir que o role foi realmente salvo (fallback direto)
      if (userRow['role'] != role) {
        debugPrint(
          '⚠️ Role mismatch: expected=$role, got=${userRow['role']}. Forcing update...',
        );
        await client
            .from('users')
            .update({'role': role})
            .eq('supabase_uid', currentUser.id);
        _role = role;
      }

      // 2. Se for prestador, criar entrada em providers
      if (role == 'provider') {
        await client.from('providers').upsert({
          'user_id': _userId,
          'commercial_name': commercialName,
          'address': address,
          'latitude': latitude,
          'longitude': longitude,
          'document_type': documentType,
          'document_value': documentValue,
        });

        // 3. Vincular profissões
        if (professions != null && professions.isNotEmpty) {
          for (var p in professions) {
            final String pName = (p is Map) ? p['name'] : p.toString();
            final profData = await client
                .from('professions')
                .select('id')
                .ilike('name', pName)
                .maybeSingle();

            if (profData != null) {
              await client.from('provider_professions').upsert({
                'provider_user_id': _userId,
                'profession_id': profData['id'],
              });
            }
          }
        }
      }

      // 4. Se for motorista, criar entrada em vehicles com dados detalhados
      if (role == 'driver' && vehicleTypeId != null) {
        final plate = (vehiclePlate != null && vehiclePlate.isNotEmpty)
            ? vehiclePlate
            : 'TEMP-${(1000 + (userId ?? 0) % 9000)}';
        final model = (vehicleModel != null && vehicleModel.isNotEmpty)
            ? '${vehicleBrand ?? ''} $vehicleModel'.trim()
            : ((vehicleTypeId == 3) ? 'Moto' : 'Carro');

        await client.from('vehicles').upsert({
          'driver_id': _userId,
          'model': model,
          'plate': plate,
          'vehicle_type_id': vehicleTypeId,
          'color': vehicleColor,
          'color_hex': vehicleColorHex,
          'year': vehicleYear,
        }, onConflict: 'driver_id');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_role', _role!);
      await prefs.setInt('user_id', _userId!);

      _isMedical = userRow['is_medical'] == true;
      _isFixedLocation = userRow['is_fixed_location'] == true;
      await prefs.setBool('is_medical', _isMedical);
      await prefs.setBool('is_fixed_location', _isFixedLocation);

      return {'success': true, 'user': userRow};
    } catch (e) {
      debugPrint('❌ [ApiService] Erro no registro: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> checkUnique({
    String? email,
    String? phone,
    String? document,
  }) async {
    final client = Supabase.instance.client;
    try {
      if (email != null) {
        final res = await client
            .from('users')
            .select('id')
            .eq('email', email)
            .maybeSingle();
        if (res != null) return {'exists': true, 'field': 'email'};
      }
      if (phone != null) {
        final res = await client
            .from('users')
            .select('id')
            .eq('phone', phone)
            .maybeSingle();
        if (res != null) return {'exists': true, 'field': 'phone'};
      }
      if (document != null) {
        final res = await client
            .from('providers')
            .select('user_id')
            .eq('document_value', document)
            .maybeSingle();
        if (res != null) return {'exists': true, 'field': 'document'};
      }
      return {'exists': false};
    } catch (e) {
      debugPrint('Error checking uniqueness: $e');
      return {'exists': false}; // Fallback to allow progress if check fails
    }
  }

  Future<List<dynamic>> getProfessions() async {
    try {
      final response = await Supabase.instance.client
          .from('professions')
          .select('*');
      return response;
    } catch (e) {
      debugPrint('Erro ao buscar profissões: $e');
      return [];
    }
  }

  Future<List<dynamic>> getProfessionTasks(int professionId) async {
    try {
      final response = await Supabase.instance.client
          .from('task_catalog')
          .select('*')
          .eq('profession_id', professionId);
      return response;
    } catch (e) {
      debugPrint('Erro ao buscar tarefas da profissão: $e');
      return [];
    }
  }

  Future<void> saveProviderSchedule(
    List<Map<String, dynamic>> schedules,
  ) async {
    if (_userId == null) throw Exception('Not authenticated');

    await Supabase.instance.client
        .from('providers')
        .update({'schedule_configs': schedules})
        .eq('user_id', _userId!);
  }

  Future<void> saveProviderService(Map<String, dynamic> service) async {
    if (_userId == null) throw Exception('Not authenticated');

    // Fetch provider's first profession to link the service
    final professions = await Supabase.instance.client
        .from('provider_professions')
        .select('profession_id')
        .eq('provider_user_id', _userId!)
        .limit(1)
        .maybeSingle();

    final professionId = professions?['profession_id'];

    await Supabase.instance.client.from('task_catalog').insert({
      'profession_id': professionId,
      'name': service['name'],
      'unit_price': service['price'],
      'unit_name': 'unidade',
      // Outros campos como duration seriam salvos em uma tabela de extensão ou JSON se necessário
    });
  }

  /// Login legado mantido por compatibilidade, mas agora usa Supabase diretamente.
  /// O fluxo principal já usa loginWithFirebase().
  Future<Map<String, dynamic>> login(String firebaseToken) async {
    // Não chama mais o backend legado (/auth/login)
    // Sinc com Supabase via loginWithFirebase
    debugPrint(
      '⚠️ [ApiService] login() chamado — redirecionando para loginWithFirebase()',
    );
    await loginWithFirebase(firebaseToken);
    return {
      'success': true,
      'user': {
        'id': _userId,
        'role': _role,
        'is_medical': _isMedical,
        'is_fixed_location': _isFixedLocation,
      },
    };
  }

  /// Logger for Dispatch Audit (v11)
  Future<void> logServiceEvent(
    String serviceId,
    String action, [
    String? details,
  ]) async {
    try {
      if (_userId == null) return;

      await Supabase.instance.client.from('service_logs').insert({
        'service_id': serviceId,
        'provider_id': _userId,
        'action': action,
        'details': details,
      });
      debugPrint('✅ [ApiService] Logged event $action for service $serviceId');
    } catch (e) {
      debugPrint('❌ [ApiService] Failed to log event: $e');
    }
  }

  // Alias for getProfile to maintain compatibility
  Future<Map<String, dynamic>> getProfile() async {
    final data = await getUserData();
    if (data == null) throw Exception('Profile not found');
    return data;
  }

  Future<Map<String, dynamic>?> getUserData() async {
    final client = Supabase.instance.client;
    final currentUser = client.auth.currentUser;
    if (currentUser == null) return null;

    try {
      final response = await client
          .from('users')
          .select()
          .eq('supabase_uid', currentUser.id)
          .single();
      return response;
    } catch (e) {
      debugPrint('Erro ao buscar dados do usuário: $e');
      return null;
    }
  }

  Future<void> loginWithFirebase(
    String idToken, {
    String? role,
    String? phone,
    String? name,
  }) async {
    final client = Supabase.instance.client;
    final currentUser = client.auth.currentUser;

    if (currentUser == null) throw Exception('Não logado no Supabase');

    try {
      // 1. Buscar usuário existente pelo supabase_uid para preservar o role
      var userRow = await client
          .from('users')
          .select()
          .eq('supabase_uid', currentUser.id)
          .maybeSingle();

      if (userRow == null) {
        // Usuário novo — criar com role padrão
        final email = currentUser.email;
        final fullName =
            name ??
            currentUser.userMetadata?['full_name'] ??
            email?.split('@')[0] ??
            'Usuário';

        userRow = await client
            .from('users')
            .upsert({
              'supabase_uid': currentUser.id,
              'email': email,
              'full_name': fullName,
              'role': role ?? 'client',
              'phone': phone,
            }, onConflict: 'supabase_uid')
            .select()
            .single();
      } else {
        // Usuário existente — atualizar apenas nome/email, NÃO sobrescrever o role
        final updates = <String, dynamic>{};
        if (name != null) updates['full_name'] = name;
        if (phone != null) updates['phone'] = phone;

        if (updates.isNotEmpty) {
          await client
              .from('users')
              .update(updates)
              .eq('supabase_uid', currentUser.id);
        }
      }

      // 3. Atualizar estado local com o role do BANCO (preserva driver/provider)
      _role = userRow['role'];
      _userId = userRow['id'];
      _isMedical = userRow['is_medical'] == true;
      _isFixedLocation = userRow['is_fixed_location'] == true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_role', _role ?? 'client');
      if (_userId != null) await prefs.setInt('user_id', _userId!);
      await prefs.setBool('is_medical', _isMedical);
      await prefs.setBool('is_fixed_location', _isFixedLocation);

      // Authenticate Realtime Service
      if (_userId != null) RealtimeService().authenticate(_userId!);

      // Update FCM Token se disponível
      if (_fcmToken != null) {
        await registerDeviceToken(_fcmToken!, Platform.operatingSystem);
      }
    } catch (e) {
      debugPrint('❌ [ApiService] Erro ao sincronizar usuário: $e');
      rethrow;
    }
  }

  Future<void> updateProfile({
    String? name,
    String? email,
    String? phone,
    Map<String, dynamic>? customFields,
  }) async {
    final client = Supabase.instance.client;
    final currentUser = client.auth.currentUser;
    if (currentUser == null) return;

    final body = <String, dynamic>{};
    if (name != null) body['full_name'] = name;
    if (email != null) body['email'] = email;
    if (phone != null) body['phone'] = phone;
    if (customFields != null) body.addAll(customFields);

    if (body.isNotEmpty) {
      await client
          .from('users')
          .update(body)
          .eq('supabase_uid', currentUser.id);
    }
  }

  Future<void> updateProviderProfile({
    String? documentType,
    String? documentValue,
    String? commercialName,
    List<String>? professions,
  }) async {
    final client = Supabase.instance.client;
    if (_userId == null) return;

    // Atualiza tabela providers
    await client
        .from('providers')
        .update({
          'document_type': documentType,
          'document_value': documentValue,
          'commercial_name': commercialName,
        })
        .eq('user_id', _userId!);

    // Professions logic (opcional: pode precisar de lógica de delete/insert no provider_professions)
  }

  Future<int?> getMyUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id');
  }

  bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value == 1; // 1 is true, 0 is false
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    return false;
  }

  Future<Map<String, dynamic>> getMyProfile() async {
    final client = Supabase.instance.client;
    final currentUser = client.auth.currentUser;
    if (currentUser == null) throw Exception('Não autenticado');

    final user = await client
        .from('users')
        .select('*, providers(*)')
        .eq('supabase_uid', currentUser.id)
        .single();

    debugPrint('DEBUG: getMyProfile fetched user: ${jsonEncode(user)}');

    // Update local state based on fresh profile data
    _isMedical = _parseBool(user['is_medical']);
    _isFixedLocation = _parseBool(user['is_fixed_location']);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_medical', _isMedical);
    await prefs.setBool('is_fixed_location', _isFixedLocation);

    return user;
  }

  Future<List<String>> getProviderSpecialties() async {
    if (_userId == null) return [];

    final response = await Supabase.instance.client
        .from('provider_professions')
        .select('professions(name)')
        .eq('provider_user_id', _userId!);

    return (response as List)
        .map((e) => e['professions']['name'].toString())
        .toList();
  }

  Future<Map<String, dynamic>> getProviderProfile(int providerId) async {
    final response = await Supabase.instance.client
        .from('users')
        .select('*, providers(*)')
        .eq('id', providerId)
        .single();
    return response;
  }

  Future<List<Map<String, dynamic>>> searchProviders({
    String? term,
    double? lat,
    double? lon,
  }) async {
    final client = Supabase.instance.client;
    var query = client
        .from('users')
        .select('*, providers(*)')
        .eq('role', 'provider');

    if (term != null && term.isNotEmpty) {
      query = query.ilike('full_name', '%$term%');
    }

    final response = await query;
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> addProviderSpecialty(String name) async {
    if (_userId == null) return;

    // Buscar ID da profissão pelo nome
    final prof = await Supabase.instance.client
        .from('professions')
        .select('id')
        .ilike('name', name)
        .maybeSingle();

    if (prof != null) {
      await Supabase.instance.client.from('provider_professions').upsert({
        'provider_user_id': _userId,
        'profession_id': prof['id'],
      });
    }
  }

  Future<void> removeProviderSpecialty(String name) async {
    if (_userId == null) return;

    final prof = await Supabase.instance.client
        .from('professions')
        .select('id')
        .ilike('name', name)
        .maybeSingle();

    if (prof != null) {
      await Supabase.instance.client
          .from('provider_professions')
          .delete()
          .match({'provider_user_id': _userId!, 'profession_id': prof['id']});
    }
  }

  Future<void> deleteAccount() async {
    if (_userId == null) return;
    await Supabase.instance.client.from('users').delete().eq('id', _userId!);
    await clearToken();
  }

  Future<void> requestWithdrawal(String pixKey, double amount) async {
    // Mock implementation for now
    await Future.delayed(const Duration(seconds: 1));
    debugPrint('Mock Withdrawal Request: PIX=$pixKey, Amount=$amount');
    // In a real implementation, this would be:
    // await post('/wallet/withdraw', {'pix_key': pixKey, 'amount': amount});
  }

  // ========== SERVICES ==========
  Future<Map<String, dynamic>> createService({
    required int categoryId,
    required String description,
    required dynamic latitude,
    required dynamic longitude,
    required String address,
    required dynamic priceEstimated,
    required dynamic priceUpfront,
    List<String> imageKeys = const [],
    String? videoKey,
    List<String> audioKeys = const [],
    String? profession,
    int? professionId,
    String locationType = 'client',
    int? providerId,
    DateTime? scheduledAt,
    int? taskId,
  }) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null || _userId == null) {
      throw ApiException(message: 'Usuário não autenticado', statusCode: 401);
    }

    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) {
        return double.tryParse(value.replaceAll(',', '.')) ?? 0.0;
      }
      return 0.0;
    }

    final double lat = parseDouble(latitude);
    final double lon = parseDouble(longitude);
    final double pEst = parseDouble(priceEstimated);
    final double pUp = parseDouble(priceUpfront);

    // Gerar ID UUID v4 do serviço baseado num UUID.
    // Como o SDK Supabase pode não gerar UUID client-side fácil sem pacote extra, deixamos o BD gerar se possível, ou usamos o gen_random_uuid().
    // O SDK tem .insert() que retorna o item inserido.

    final body = <String, dynamic>{
      'client_id': _userId, // Inteiro
      'category_id': categoryId,
      'description': description,
      'latitude': double.parse(lat.toStringAsFixed(8)),
      'longitude': double.parse(lon.toStringAsFixed(8)),
      'address': address,
      'price_estimated': double.parse(pEst.toStringAsFixed(2)),
      'price_upfront': double.parse(pUp.toStringAsFixed(2)),
      'status': 'waiting_payment', // Padrão
      'profession': profession,
      'profession_id': professionId,
      'location_type': locationType,
      'provider_id': providerId,
      'scheduled_at': scheduledAt?.toIso8601String(),
      'task_id': taskId,
    };

    debugPrint('📤 [CREATE SERVICE SUPABASE SDK] Body: ${jsonEncode(body)}');

    try {
      final response = await supabase
          .from('service_requests_new')
          .insert(body)
          .select()
          .single();

      final serviceId = response['id'];

      // Se for presencial/agendado e já tiver provider, precisa criar também o Appt.
      if (scheduledAt != null && providerId != null) {
        final apptBody = {
          'service_request_id': serviceId,
          'provider_id': providerId,
          'client_id': _userId,
          'start_time': scheduledAt.toIso8601String(),
          'end_time': scheduledAt
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'status': 'waiting_payment',
        };
        await supabase.from('appointments').insert(apptBody);
      }

      return {'success': true, 'serviceId': serviceId, 'service': response};
    } catch (e) {
      debugPrint('❌ [CREATE SERVICE SUPABASE SDK] Erro: $e');
      throw ApiException(
        message: 'Falha ao criar serviço: $e',
        statusCode: 500,
      );
    }
  }

  // Helper to map Supabase relation objects into flattened keys as expected by UI
  Map<String, dynamic> _mapServiceData(Map<String, dynamic> raw) {
    final Map<String, dynamic> mapped = Map<String, dynamic>.from(raw);

    if (raw['users'] != null) {
      mapped['client_name'] = raw['users']['full_name'];
      mapped['client_avatar'] = raw['users']['avatar_url'];
    }

    if (raw['providers'] != null && raw['providers']['users'] != null) {
      mapped['provider_name'] = raw['providers']['users']['full_name'];
      mapped['provider_avatar'] = raw['providers']['users']['avatar_url'];
    }

    if (raw['service_categories'] != null) {
      mapped['category_name'] = raw['service_categories']['name'];
    }

    final double price =
        double.tryParse(raw['price_estimated']?.toString() ?? '0') ?? 0.0;
    mapped['provider_amount'] = double.parse((price * 0.85).toStringAsFixed(2));

    return mapped;
  }

  Future<List<dynamic>> getMyServices() async {
    if (_userId == null) return [];
    try {
      final query = Supabase.instance.client
          .from('service_requests_new')
          .select(
            '*, users!client_id(full_name, avatar_url), providers!provider_id(users!user_id(full_name, avatar_url)), service_categories!category_id(name)',
          );

      final response = _role == 'provider'
          ? await query
                .eq('provider_id', _userId!)
                .order('created_at', ascending: false)
          : await query
                .eq('client_id', _userId!)
                .order('created_at', ascending: false);

      return response.map((s) => _mapServiceData(s)).toList();
    } catch (e) {
      debugPrint('Erro no getMyServices direto do supabase: $e');
      return [];
    }
  }

  Future<List<dynamic>> getAvailableServices() async {
    try {
      final response = await Supabase.instance.client
          .from('service_requests_new')
          .select(
            '*, users!client_id(full_name, avatar_url), service_categories!category_id(name)',
          )
          .inFilter('status', ['pending', 'open_for_schedule'])
          .isFilter('provider_id', null)
          .order('created_at', ascending: false);

      return response.map((s) => _mapServiceData(s)).toList();
    } catch (e) {
      debugPrint('Erro no getAvailableServices direto do supabase: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getServiceDetails(String serviceId) async {
    try {
      final response = await Supabase.instance.client
          .from('service_requests_new')
          .select(
            '*, users!client_id(full_name, avatar_url), providers!provider_id(users!user_id(full_name, avatar_url)), service_categories!category_id(name)',
          )
          .eq('id', serviceId)
          .maybeSingle();

      if (response != null) {
        return _mapServiceData(response);
      }
      throw Exception('Service not found');
    } catch (e) {
      debugPrint('Erro via getServiceDetails Supabase DB SDK: $e');
      rethrow;
    }
  }

  Future<void> acceptService(String serviceId) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('service_requests_new')
          .update({
            'provider_id': _userId,
            'status': 'accepted',
            'status_updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', serviceId);
    } catch (e) {
      throw ApiException(message: 'Erro ao aceitar: $e', statusCode: 500);
    }
  }

  Future<void> rejectService(String serviceId) async {
    // Para simplificar a rejeição (que tem lógica de dispatcher), ainda chamamos o node_js se for o caso
    // ou inserimos na tabela service_rejections
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('service_rejections').insert({
        'service_id': serviceId,
        'provider_id': _userId,
      });
    } catch (e) {
      throw ApiException(message: 'Erro ao rejeitar: $e', statusCode: 500);
    }
  }

  Future<void> updateServiceStatus(String serviceId, String status) async {
    if (status == 'in_progress') {
      await startService(serviceId);
    } else if (status == 'completed') {
      await completeService(serviceId);
    } else {
      await Supabase.instance.client
          .from('service_requests_new')
          .update({'status': status})
          .eq('id', serviceId);
    }
  }

  Future<void> startService(String serviceId) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('service_requests_new')
          .update({
            'status': 'in_progress',
            'started_at': DateTime.now().toIso8601String(),
            'status_updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', serviceId);
    } catch (e) {
      throw ApiException(message: 'Erro ao iniciar: $e', statusCode: 500);
    }
  }

  Future<bool> verifyServiceCode(String serviceId, String code) async {
    try {
      final response = await Supabase.instance.client
          .from('service_requests_new')
          .select('verification_code')
          .eq('id', serviceId)
          .maybeSingle();

      if (response == null) return false;
      return response['verification_code'] == code;
    } catch (e) {
      debugPrint('Error verifying code: $e');
      return false;
    }
  }

  Future<void> confirmServiceCompletion(
    String serviceId, {
    String? code,
    String? proofVideo,
  }) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('service_requests_new')
          .update({
            'status': 'completed',
            'status_updated_at': DateTime.now().toIso8601String(),
            'proof_video': ?proofVideo,
          })
          .eq('id', serviceId);

      await logServiceEvent(
        serviceId,
        'COMPLETED',
        'Service confirmed completed by provider',
      );
    } catch (e) {
      throw ApiException(message: 'Erro ao concluir: $e', statusCode: 500);
    }
  }

  Future<void> confirmFinalService(
    String serviceId, {
    int? rating,
    String? comment,
  }) async {
    try {
      final client = Supabase.instance.client;

      // 1. Atualizar status para finalizado
      await client
          .from('service_requests_new')
          .update({
            'status': 'finished',
            'status_updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', serviceId);

      // 2. Se houver avaliação, inserir na tabela de reviews
      if (rating != null) {
        await client.from('reviews').insert({
          'service_id': serviceId,
          'rating': rating,
          'comment': comment,
          'user_id': _userId, // Quem avaliou (cliente)
        });
      }

      await logServiceEvent(
        serviceId,
        'FINISHED',
        'Service confirmed finished by client with rating $rating',
      );
    } catch (e) {
      throw ApiException(
        message: 'Erro ao finalizar serviço: $e',
        statusCode: 500,
      );
    }
  }

  // --- Novos Métodos para Migração 100% Online ---

  /// Busca configurações globais da tabela app_configs
  Future<Map<String, dynamic>> getAppConfig() async {
    try {
      final client = Supabase.instance.client;
      final List<dynamic> data = await client.from('app_configs').select();

      final Map<String, dynamic> configMap = {};
      for (var item in data) {
        configMap[item['key']] = item['value'];
      }
      return configMap;
    } catch (e) {
      debugPrint('Error fetching app config: $e');
      return {};
    }
  }

  /// Classifica serviço via Edge Function
  Future<Map<String, dynamic>> classifyServiceAi(String text) async {
    final Map<String, dynamic> result = await invokeEdgeFunction(
      'ai-classify',
      {'text': text},
    );
    return result;
  }

  /// Calcula tarifa Uber via Edge Function geo
  Future<dynamic> calculateUberFare({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    required int vehicleTypeId,
  }) async {
    final client = Supabase.instance.client;
    final response = await client.functions.invoke(
      'geo/calculate-fare',
      body: {
        'pickup_lat': pickupLat,
        'pickup_lng': pickupLng,
        'dropoff_lat': dropoffLat,
        'dropoff_lng': dropoffLng,
        'vehicle_type_id': vehicleTypeId,
      },
    );

    if (response.status != 200) {
      throw Exception('Falha ao calcular tarifa Uber: ${response.status}');
    }

    debugPrint(
      '📊 [EdgeFn] Dados completos da API de tarifa: ${response.data}',
    );
    return response.data['fare'];
  }

  Future<void> completeService(
    String serviceId, {
    String? proofCode,
    String? proofPhoto,
    String? proofVideo,
  }) async {
    await confirmServiceCompletion(
      serviceId,
      code: proofCode,
      proofVideo: proofVideo,
    );
  }

  Future<void> requestServiceCompletion(String serviceId) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.rpc(
        'rpc_request_completion',
        params: {'p_service_id': serviceId},
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: 'Erro ao solicitar a conclusão: $e',
        statusCode: 500,
      );
    }
  }

  Future<void> submitReview({
    required String serviceId,
    required int rating,
    String? comment,
  }) async {
    final client = Supabase.instance.client;
    if (_userId == null) throw Exception('Não autenticado');

    try {
      // 1. Buscar o serviço para saber quem é o prestador (reviewee)
      final service = await client
          .from('service_requests_new')
          .select('provider_id, client_id')
          .eq('id', serviceId)
          .single();

      final providerId = service['provider_id'];
      final clientId = service['client_id'];

      // Determinar quem está avaliando quem (Assume-se que cliente avalia prestador se _role == 'client')
      final revieweeId = (_role == 'client') ? providerId : clientId;

      if (revieweeId == null) {
        throw Exception('Não foi possível identificar o avaliado');
      }

      // 2. Inserir a avaliação
      await client.from('reviews').upsert({
        'service_id': serviceId,
        'reviewer_id': _userId,
        'reviewee_id': revieweeId,
        'rating': rating,
        'comment': comment,
      });

      debugPrint('✅ [ApiService] Avaliação enviada com sucesso!');
    } catch (e) {
      debugPrint('❌ [ApiService] Erro ao enviar avaliação: $e');
      rethrow;
    }
  }

  Future<void> arriveService(String serviceId) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('service_requests_new')
          .update({
            'status': 'waiting_payment_remaining',
            'arrived_at': DateTime.now().toIso8601String(),
            'status_updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', serviceId);
    } catch (e) {
      throw ApiException(
        message: 'Erro ao registrar chegada: $e',
        statusCode: 500,
      );
    }
  }

  Future<void> contestService(String serviceId, String reason) async {
    // Ideally this inserts the reason into a service_disputes table, but we stick to update for now
    await Supabase.instance.client
        .from('service_requests_new')
        .update({
          'status': 'contested',
          'status_updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', serviceId);
  }

  Future<void> cancelService(String serviceId) async {
    await Supabase.instance.client
        .from('service_requests_new')
        .update({
          'status': 'cancelled',
          'status_updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', serviceId);
  }

  Future<void> requestServiceEdit({
    required String serviceId,
    required String newDescription,
    required double newPrice,
  }) async {
    // This could also be a direct update if allowed by RLS,
    // but usually needs review. We'll use a transaction/RPC or just update status to 'edit_requested'
    await Supabase.instance.client
        .from('service_requests_new')
        .update({
          'description': newDescription,
          'price_estimated': newPrice,
          'status': 'edit_requested',
          'status_updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', serviceId);
  }

  Future<Map<String, dynamic>> fetchFuelPricesByState(String state) async {
    return _getCachedFuel('state_$state', () async {
      try {
        return await get('/geo/fuel?state=$state');
      } catch (_) {
        return {};
      }
    });
  }

  Future<Map<String, dynamic>> fetchFuelPriceByCityState(
    String city,
    String state,
  ) async {
    return _getCachedFuel('city_${city}_$state', () async {
      try {
        return await get('/geo/fuel?city=$city&state=$state');
      } catch (_) {
        return {};
      }
    });
  }

  Future<Map<String, dynamic>> reverseCityStateFromCoords(
    double lat,
    double lon,
  ) async {
    try {
      return await get('/geo/reverse?lat=$lat&lon=$lon');
    } catch (_) {
      return {'city': 'Unknown', 'state': 'XX'};
    }
  }

  Future<String> reverseStateFromCoords(double lat, double lon) async {
    final res = await reverseCityStateFromCoords(lat, lon);
    return (res['state'] ?? '').toString();
  }

  Future<Map<String, dynamic>> getRouteMetrics({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async {
    try {
      return await post('/geo/route', {
        'from': {'lat': fromLat, 'lon': fromLon},
        'to': {'lat': toLat, 'lon': toLon},
      });
    } catch (_) {
      return {'distance_km': 0.0, 'duration_min': 0.0};
    }
  }

  // ========== MEDIA ==========

  Future<String> _directUpload(
    String bucket,
    String typePath,
    List<int> bytes,
    String filename,
    String? contentType,
  ) async {
    try {
      final ext = filename.split('.').last;
      final uniqueName =
          '${DateTime.now().millisecondsSinceEpoch}_${Uuid().v4().substring(0, 8)}.$ext';
      final path = '$typePath/$uniqueName';

      final supabase = Supabase.instance.client;
      await supabase.storage
          .from(bucket)
          .uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(
              contentType: contentType ?? 'application/octet-stream',
            ),
          );

      final publicUrl = supabase.storage.from(bucket).getPublicUrl(path);
      debugPrint('[Supabase Storage] File uploaded successfully: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('❌ [Supabase Storage] Upload error: $e');
      throw ApiException(
        message: 'Falha no upload para o Supabase: $e',
        statusCode: 500,
      );
    }
  }

  Future<String> uploadServiceImage(
    List<int> bytes, {
    String filename = 'image.jpg',
    String mimeType = 'image/jpeg',
  }) async {
    return _directUpload('service_media', 'images', bytes, filename, mimeType);
  }

  Future<String> uploadServiceVideo(
    List<int> bytes, {
    String filename = 'video.mp4',
    String? mimeType,
    void Function(double)? onProgress,
  }) async {
    return _directUpload(
      'service_media',
      'videos',
      bytes,
      filename,
      mimeType ?? 'video/mp4',
    );
  }

  Future<String> uploadServiceAudio(
    List<int> bytes, {
    String filename = 'audio.m4a',
  }) async {
    return _directUpload(
      'service_media',
      'audios',
      bytes,
      filename,
      'audio/mp4',
    );
  }

  Future<String> uploadChatImage(
    String serviceId,
    List<int> bytes, {
    String filename = 'chat.jpg',
  }) async {
    return _directUpload(
      'chat_media',
      serviceId,
      bytes,
      filename,
      'image/jpeg',
    );
  }

  Future<String> uploadChatAudio(
    String serviceId,
    List<int> bytes, {
    String filename = 'audio.m4a',
    String mimeType = 'audio/mp4',
  }) async {
    return _directUpload('chat_media', serviceId, bytes, filename, mimeType);
  }

  Future<String> uploadChatVideo(
    String serviceId,
    List<int> bytes, {
    String filename = 'video.mp4',
    String? mimeType,
  }) async {
    return _directUpload(
      'chat_media',
      serviceId,
      bytes,
      filename,
      mimeType ?? 'video/mp4',
    );
  }

  Future<String> uploadMediaFromPath(
    String path, {
    required String filename,
    String? serviceId,
    String type = 'image',
    String? mimeType,
    void Function(double)? onProgress,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('Arquivo não encontrado: $path');
    }
    final bytes = await file.readAsBytes();
    final bucket = type == 'service' ? 'service_media' : 'chat_media';
    final sId = serviceId ?? 'general';
    return _directUpload(bucket, sId, bytes, filename, mimeType);
  }

  Future<String> uploadServiceVideoFromPath(
    String path, {
    String filename = 'video.mp4',
    String? mimeType,
    void Function(double)? onProgress,
  }) async {
    return uploadMediaFromPath(
      path,
      filename: filename,
      type: 'service',
      mimeType: mimeType,
      onProgress: onProgress,
    );
  }

  Future<String> uploadToCloud(
    List<int> bytes, {
    required String filename,
    String? serviceId,
    String type = 'image',
  }) async {
    // Adapter to avoid breaking old Cloudflare R2 specific calls
    final bucket = type == 'chat' ? 'chat_media' : 'service_media';
    final sId = serviceId ?? 'general';
    return _directUpload(bucket, sId, bytes, filename, null);
  }

  Future<String> getMediaViewUrl(String key) async {
    if (key.startsWith('http')) return key;
    return key; // With Supabase we store direct URLs.
  }

  String getMediaUrl(String key) {
    if (key.isEmpty) return '';
    if (key.startsWith('http')) return key;
    // Fallback if needed
    return key;
  }

  Future<Uint8List> getMediaBytes(String key) {
    if (_mediaBytesCache.containsKey(key)) {
      return _mediaBytesCache[key]!;
    }
    final future = _fetchBytes(key);
    _mediaBytesCache[key] = future;
    return future;
  }

  Future<Uint8List> _fetchBytes(String key) async {
    try {
      // Direct URL support (R2/Public)
      if (key.startsWith('http')) {
        final response = await http.get(Uri.parse(key));
        if (response.statusCode == 200) {
          return response.bodyBytes;
        }
        throw Exception('Status ${response.statusCode} fetching $key');
      }

      // Legacy key support (via backend proxy)
      // Use proxy route to avoid CORS issues on Web and ensure Auth
      final response = await getRaw(
        '/media/chat/raw?key=${Uri.encodeComponent(key)}',
      );
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      throw Exception('Status ${response.statusCode}');
    } catch (e) {
      unawaited(_mediaBytesCache.remove(key));
      rethrow;
    }
  }

  Future<void> notifyProviderArrived(String serviceId) async {
    await arriveService(serviceId);
  }

  Future<void> payRemainingService(String serviceId) async {
    await Supabase.instance.client
        .from('service_requests_new')
        .update({'payment_remaining_status': 'paid_manual'})
        .eq('id', serviceId);
  }

  Future<void> notifyClientArrived(String serviceId) async {
    await Supabase.instance.client
        .from('service_requests_new')
        .update({
          'status': 'client_arrived',
          'status_updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', serviceId);
  }

  // --- Scheduling Flow ---

  Future<List<dynamic>> getAvailableForSchedule() async {
    try {
      final response = await Supabase.instance.client
          .from('service_requests_new')
          .select(
            '*, users!client_id(full_name, avatar_url), service_categories!category_id(name)',
          )
          .inFilter('status', ['pending', 'open_for_schedule'])
          .isFilter('provider_id', null)
          .order('created_at', ascending: false);

      return response.map((s) => _mapServiceData(s)).toList();
    } catch (e) {
      debugPrint('Erro no getAvailableForSchedule direto do supabase: $e');
      return [];
    }
  }

  Future<void> proposeSchedule(String serviceId, DateTime scheduledAt) async {
    await Supabase.instance.client
        .from('service_requests_new')
        .update({
          'scheduled_at': scheduledAt.toIso8601String(),
          'status':
              'open_for_schedule', // Mudamos o status para indicar que há proposta
          'status_updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', serviceId);
  }

  // confirmSchedule already defined above

  // --- Test & Dev Helpers ---

  Future<void> testApprovePayment(String serviceId) async {
    // Agora fazemos o update direto no status para teste
    await Supabase.instance.client
        .from('service_requests_new')
        .update({
          'status': 'accepted',
          'payment_remaining_status': 'paid_manual',
          'status_updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', serviceId);
  }

  // --- Location Search (Mapbox) ---

  Future<List<dynamic>> searchLocation(
    String query, {
    double? lat,
    double? lon,
  }) async {
    try {
      String url = '/geo/search?q=${Uri.encodeComponent(query)}';

      // Adicionar raio de busca do app_configs
      final radius = RemoteConfigService.searchRadiusKm;
      url += '&radius=$radius';

      if (lat != null && lon != null) {
        url += '&proximity=$lat,$lon';
      }
      final dynamic res = await get(url);
      if (res is List) return res;
      if (res is Map && res['raw'] is List) return res['raw'];
      return [];
    } catch (e) {
      debugPrint('SearchLocation error: $e');
      return [];
    }
  }

  // --- Notifications ---

  Future<void> markNotificationRead(int id) async {
    // Fase 2: Usar Supabase SDK em vez do backend legado
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'read': true})
          .eq('id', id);
    } catch (e) {
      debugPrint('⚠️ [ApiService] Erro ao marcar notificação como lida: $e');
    }
  }

  Future<void> markAllNotificationsRead() async {
    // Fase 2: Usar Supabase SDK em vez do backend legado
    if (_userId == null) return;
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'read': true})
          .eq('user_id', _userId!);
    } catch (e) {
      debugPrint(
        '⚠️ [ApiService] Erro ao marcar todas notificações como lidas: $e',
      );
    }
  }

  // Locais Salvos
  Future<List<Map<String, dynamic>>> getSavedPlaces() async {
    if (_userId == null) return [];
    try {
      final response = await Supabase.instance.client
          .from('user_saved_places')
          .select('*')
          .eq('user_id', _userId!)
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('⚠️ [ApiService] Erro ao buscar locais salvos: $e');
      // Fallback para mock se a tabela não existir
      return [
        {'title': 'Casa', 'address': 'Rua das Flores, 123', 'icon': 'home'},
        {
          'title': 'Trabalho',
          'address': 'Av. Paulista, 1500',
          'icon': 'briefcase',
        },
      ];
    }
  }

  Future<void> saveSavedPlace(Map<String, dynamic> place) async {
    if (_userId == null) throw Exception('Não autenticado');
    try {
      await Supabase.instance.client.from('user_saved_places').upsert({
        ...place,
        'user_id': _userId,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('⚠️ [ApiService] Erro ao salvar local: $e');
      rethrow;
    }
  }
}

class _FuelCacheItem {
  final Map<String, dynamic> data;
  final DateTime expiry;
  _FuelCacheItem({required this.data, required this.expiry});
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException({required this.message, required this.statusCode});
  @override
  String toString() => '$message (Status: $statusCode)';
}
