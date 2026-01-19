import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'realtime_service.dart';
import 'notification_service.dart';
import 'permissions_service.dart';
import 'analytics_service.dart';
import '../core/utils/logger.dart';

class ApiService {
  // URLs Legadas (Mantidas comentadas para referência se necessário)
  // static const String _androidEmulatorApiUrl = 'http://10.0.2.2:4011/api';
  // static const String _iosRealDeviceApiUrl = 'http://localhost:4011/api';
  
  // static const String _vercelApiUrl = 'https://backend-pi-ivory-11.vercel.app';
  // static const String _prodApiUrl = _vercelApiUrl;



  static String get baseUrl {
    // URL do Cloudflare Worker (Produção)
    const productionUrl = 'https://projeto-central-backend.carrobomebarato.workers.dev/api';
    
    // URL do Instância Local do Worker (usando wrangler dev --remote)
    // 10.0.2.2 é o IP especial do host visto pelo emulador Android
    const localWorkerUrl = 'http://10.0.2.2:4011/api';

    // Mude para 'true' para testar com o Worker rodando localmente no PC
    const useLocalWorker = false; // <--- SWITCHED TO PRODUCTION (Cloudflare)

    if (kDebugMode && useLocalWorker) {
      return localWorkerUrl;
    }
    
    return productionUrl;
  }

  static String fixUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    // Como estamos 100% online, não precisamos mais trocar localhost por IPs de emulador
    return url;
  }

  String? _token;
  Completer<String?>? _tokenCompleter; // Evita chamadas paralelas ao token
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
      } else {
        _token = null;
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

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<List<Map<String, dynamic>>> getProviderSlots(
    int providerId, {
    String? date,
  }) async {
    final token = await _getToken();
    final uri = Uri.parse(
      '$baseUrl/appointments/$providerId/slots',
    ).replace(queryParameters: date != null ? {'date': date} : null);

    final response = await _client.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    }
    throw Exception('Failed to load slots: ${response.statusCode}');
  }

  Future<void> markSlotBusy(DateTime startTime) async {
    final token = await _getToken();
    final response = await _client.post(
      Uri.parse('$baseUrl/appointments/busy'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'start_time': startTime.toIso8601String()}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to mark slot busy');
    }
  }

  Future<void> bookSlot(int providerId, DateTime startTime) async {
    final token = await _getToken();
    final response = await _client.post(
      Uri.parse('$baseUrl/appointments/book'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'provider_id': providerId,
        'start_time': startTime.toIso8601String(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to book slot');
    }
  }

  Future<void> confirmSchedule(String serviceId, DateTime time) async {
    await post('/services/$serviceId/confirm-schedule', {
      'scheduled_at': time.toIso8601String(),
    });
  }

  Future<void> markClientDeparting(String serviceId) async {
    print('📍 [ApiService] Marking client departing for service: $serviceId');
    await post('/services/$serviceId/depart', {});
  }

  Future<void> markClientArrived(String serviceId) async {
    print('📍 [ApiService] Marking client arrived for service: $serviceId');
    await post('/services/$serviceId/arrived_client', {});
  }

  Future<void> confirmPaymentManual(String serviceId) async {
    print('💰 [ApiService] Confirming manual payment for service: $serviceId');
    await post('/services/$serviceId/confirm-payment', {});
  }

  Future<void> deleteAppointment(int appointmentId) async {
    final token = await _getToken();
    final response = await _client.delete(
      Uri.parse('$baseUrl/appointments/$appointmentId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete appointment');
    }
  }

  Future<List<Map<String, dynamic>>> getScheduleConfig() async {
    final token = await _getToken();
    final response = await _client.get(
      Uri.parse('$baseUrl/appointments/config'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    }
    throw Exception('Failed to load config');
  }

  Future<void> saveScheduleConfig(List<Map<String, dynamic>> configs) async {
    final token = await _getToken();
    final response = await _client.post(
      Uri.parse('$baseUrl/appointments/config'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(configs),
    );

    if (response.statusCode != 200) {
      debugPrint('Failed to save config: ${response.body}');
      throw Exception('Failed to save config: ${response.body}');
    }
  }

  Future<List<Map<String, dynamic>>> getScheduleExceptions() async {
    final token = await _getToken();
    final response = await _client.get(
      Uri.parse('$baseUrl/provider/schedule/exceptions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(decoded['exceptions'] ?? decoded);
    }
    return [];
  }

  Future<void> saveScheduleExceptions(List<dynamic> exceptions) async {
    final token = await _getToken();
    final response = await _client.post(
      Uri.parse('$baseUrl/provider/schedule/exceptions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'exceptions': exceptions}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to save exceptions');
    }
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

  Future<Map<String, dynamic>> _getCachedFuel(String key, Future<Map<String, dynamic>> Function() fetcher) async {
    final now = DateTime.now();
    if (_fuelCache.containsKey(key)) {
      final item = _fuelCache[key]!;
      if (now.isBefore(item.expiry)) {
        return item.data;
      }
    }
    final data = await fetcher();
    if (data.isNotEmpty) {
      _fuelCache[key] = _FuelCacheItem(data: data, expiry: now.add(_fuelCacheTTL));
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
        await post('/auth/logout', {});
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

  bool get isLoggedIn =>
      Supabase.instance.client.auth.currentUser != null;

  Map<String, String> get authHeaders => _headers;

  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  /// Fetches the structured list of Professions -> Services from the Backend
  /// Returns a `Map<String, List<Map<String, dynamic>>>`
  Future<Map<String, List<Map<String, dynamic>>>> getServicesMap() async {
    try {
      final response = await get('/services/professions');

      final Map<String, List<Map<String, dynamic>>> result = {};
      
      response.forEach((key, value) {
         if (value is List) {
            // Safely cast each item in the list to Map<String, dynamic>
            result[key.toString()] = value.map((e) {
               if (e is Map) {
                  return Map<String, dynamic>.from(e);
               }
               return <String, dynamic>{};
            }).where((e) => e.isNotEmpty).toList();
         }
      });

      return result;
    } on TimeoutException {
      throw ApiException(
        message: 'Servidor demorou a responder',
        statusCode: 408,
      );
    } catch (e) {
      debugPrint('Error fetching professions: $e');
      return {}; 
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

  Future<Map<String, dynamic>> delete(String endpoint, {Map<String, dynamic>? body}) async {
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
    return await _client.post(
      Uri.parse('$baseUrl$endpoint'), 
      headers: _headers,
      body: jsonEncode(batchBody)
    ).timeout(const Duration(seconds: 30));
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
      final payload = await PermissionsService().buildRegistrationPayload(
        fcmToken: token,
        latitude: latitude,
        longitude: longitude,
      );
      await post('/notifications/register-token', payload);
    } catch (e) {
      debugPrint('Error registering device token: $e');
      // Don't rethrow, as this is a background task
    }
  }

  Future<void> unregisterDeviceToken(String token) async {
    try {
      await delete('/notifications/token', body: {'token': token});
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
    final url = await uploadToCloud(
      fileBytes,
      filename: filename,
      serviceId: serviceId,
      type: 'contest',
    );

    // Link evidence to service contest in MySQL
    await post('/services/$serviceId/contest/evidence', {
      'type': type,
      'url': url, // Backend now expects 'url' instead of 'key'
    });
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (e) {
      final bodyPrefix = response.body.length > 500 ? response.body.substring(0, 500) : response.body;
      // Log reduced for production
      debugPrint(
        'ERRO DECODE JSON [${response.request?.url}] (Status ${response.statusCode}): $bodyPrefix',
      );
      throw ApiException(
        message: 'Resposta inválida do servidor (Status ${response.statusCode})',
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


  // ========== AUTH ==========
  Future<Map<String, dynamic>> register({
    required String token, // Firebase ID Token
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
  }) async {
    // Clean professions if needed
    List<dynamic>? cleaned;
    if (professions != null) {
      cleaned = professions.map((p) {
        if (p is Map) return {'id': p['id'], 'name': p['name']};
        return p;
      }).toList();
    }

    final body = {
      'token': token,
      'name': name,
      'email': email,
      'role': role,
      'phone': ?phone,
      'document_type': ?documentType,
      'document_value': ?documentValue,
      'commercial_name': ?commercialName,
      'address': ?address,
      'latitude': ?latitude,
      'longitude': ?longitude,
      if (cleaned != null && cleaned.isNotEmpty) 'professions': cleaned,
    };

    final result = await post('/auth/register', body);

    if (result['user'] != null) {
      final prefs = await SharedPreferences.getInstance();
      final user = result['user'] as Map<String, dynamic>;
      _userId = user['id'] as int;
      await prefs.setInt('user_id', _userId!);
      _role = user['role'].toString();
      await prefs.setString('user_role', _role!);

      _isMedical = user['is_medical'] == true;
      await prefs.setBool('is_medical', _isMedical);
      
      _isFixedLocation = user['is_fixed_location'] == true;
      await prefs.setBool('is_fixed_location', _isFixedLocation);
    }

    return result;
  }

  Future<Map<String, dynamic>> checkUnique({
    String? email,
    String? phone,
    String? document,
  }) async {
    final qp = [
      if (email != null && email.isNotEmpty) 'email=$email',
      if (phone != null && phone.isNotEmpty) 'phone=$phone',
      if (document != null && document.isNotEmpty) 'document=$document',
    ].join('&');
    return await get('/auth/check${qp.isNotEmpty ? '?$qp' : ''}');
  }

  Future<List<dynamic>> getProfessions() async {
    final result = await get('/auth/professions');
    return (result['professions'] as List?) ?? [];
  }

  Future<List<dynamic>> getProfessionTasks(int professionId) async {
    try {
      final result = await get('/services/professions/$professionId/tasks');
      return (result['tasks'] as List?) ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveProviderSchedule(
    List<Map<String, dynamic>> schedules,
  ) async {
    final t = _token;
    if (t == null) throw Exception('Not authenticated');

    final response = await _client.post(
      Uri.parse('$baseUrl/provider/schedule'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $t',
      },
      body: jsonEncode({'schedules': schedules}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to save schedule: ${response.body}');
    }
  }

  Future<void> saveProviderService(Map<String, dynamic> service) async {
    final t = _token;
    if (t == null) throw Exception('Not authenticated');

    final response = await _client.post(
      Uri.parse('$baseUrl/provider/services'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $t',
      },
      body: jsonEncode(service),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to save service: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> login(String firebaseToken) async {
    final result = await post('/auth/login', {'token': firebaseToken});

    if (result['user'] != null) {
      final prefs = await SharedPreferences.getInstance();
      final user = result['user'] as Map<String, dynamic>;
      _userId = user['id'] as int;
      await prefs.setInt('user_id', _userId!);
      _role = user['role'].toString();
      await prefs.setString('user_role', _role!);

      _isMedical = user['is_medical'] == true;
      await prefs.setBool('is_medical', _isMedical);

      _isFixedLocation = user['is_fixed_location'] == true;
      await prefs.setBool('is_fixed_location', _isFixedLocation);

      // ✅ SYNC FCM TOKEN ON LOGIN (User requested fresh token)
      unawaited(NotificationService().syncToken());
      
      // ✅ Log de Analytics
      AnalyticsService().logEvent('APP_LOGGED_IN', details: {
         'user_id': _userId,
         'role': _role,
      });
    }

    return result;
  }

  /// Logger for Dispatch Audit (v11)
  Future<void> logServiceEvent(String serviceId, String action, [String? details]) async {
    try {
      final user = await getUserData();
      if (user == null) return;
      
      final providerId = user['id'];
      
      final url = Uri.parse('$baseUrl/service/log-event');
      await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({
          'serviceId': serviceId,
          'providerId': providerId,
          'action': action,
          'details': details
        })
      );
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
    return await get('/profile/me');
  }

  Future<void> loginWithFirebase(
    String idToken, {
    String? role,
    String? phone,
    String? name,
    Map<String, dynamic>? humanMetrics,
  }) async {
    final response = await post('/auth/login', {
      'token': idToken,
      'role': ?role,
      'phone': ?phone,
      'name': ?name,
      'human_metrics': ?humanMetrics,
    });

    if (response['success'] == true && response['user'] != null) {
      _role = response['user']['role'];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_role', _role!);
      _userId = response['user']['id'];
      await prefs.setInt('user_id', _userId!);
      _isMedical = response['user']['is_medical'] == true;
      await prefs.setBool('is_medical', _isMedical);
      
      _isFixedLocation = response['user']['is_fixed_location'] == true;
      await prefs.setBool('is_fixed_location', _isFixedLocation);

      // Authenticate Realtime Service immediately
      RealtimeService().authenticate(response['user']['id']);
    }
  }

  Future<void> updateProfile({
    String? name,
    String? email,
    String? phone,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (email != null) body['email'] = email;
    if (phone != null) body['phone'] = phone;

    if (body.isNotEmpty) {
      await put('/profile/me', body);
    }
  }

  Future<void> updateProviderProfile({
    String? documentType,
    String? documentValue,
    String? commercialName,
    List<String>? professions,
  }) async {
    await put('/profile/provider', {
      'document_type': documentType,
      'document_value': documentValue,
      'commercial_name': commercialName,
      'professions': professions,
    });
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

  // ========== PROFILE ==========
  Future<Map<String, dynamic>> getMyProfile() async {
    final result = await get('/profile/me');
    final user = (result['user'] as Map<String, dynamic>?) ?? {};

    debugPrint('DEBUG: getMyProfile fetched user: ${jsonEncode(user)}');
    debugPrint('DEBUG: is_fixed_location from backend: ${user['is_fixed_location']}');

    // Update local state based on fresh profile data
    if (user.isNotEmpty) {
      _isMedical = _parseBool(user['is_medical']);
      _isFixedLocation = _parseBool(user['is_fixed_location']);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_medical', _isMedical);
      await prefs.setBool('is_fixed_location', _isFixedLocation);
    }

    return user;
  }

  Future<List<String>> getProviderSpecialties() async {
    final result = await get('/profile/specialties');
    return (result['specialties'] as List?)?.map((e) {
          if (e is Map) {
            return e['name']?.toString() ?? '';
          }
          return e.toString();
        }).toList() ??
        [];
  }

  Future<Map<String, dynamic>> getProviderProfile(int providerId) async {
    final result = await get('/providers/$providerId/profile');
    return result['profile'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> searchProviders(
      {String? term, double? lat, double? lon}) async {
    final queryParams = <String, String>{};
    if (term != null) queryParams['term'] = term;
    if (lat != null) queryParams['lat'] = lat.toString();
    if (lon != null) queryParams['lon'] = lon.toString();

    final queryString = Uri(queryParameters: queryParams).query;
    final result = await get('/providers/search?$queryString');

    // Se o backend retornar um array direto, _handleResponse o envolve em 'raw'
    if (result.containsKey('raw') && result['raw'] is List) {
      return (result['raw'] as List).cast<Map<String, dynamic>>();
    }

    // Caso o resultado já seja uma lista (fallback caso get mude no futuro)
    if (result is List) {
      return (result as List).cast<Map<String, dynamic>>();
    }

    // Caso o backend retorne { 'providers': [...] }
    if (result.containsKey('providers') && result['providers'] is List) {
      return (result['providers'] as List).cast<Map<String, dynamic>>();
    }

    return [];
  }

  Future<void> addProviderSpecialty(String name) async {
    await post('/profile/specialties', {'name': name});
  }

  Future<void> removeProviderSpecialty(String name) async {
    await _client
        .delete(
          Uri.parse('$baseUrl/profile/specialties/$name'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 15))
        .then((res) => _handleResponse(res));
  }

  Future<void> deleteAccount() async {
    await delete('/profile/me');
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
      throw const ApiException(message: 'Usuário não autenticado', statusCode: 401);
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
      if (profession != null) 'profession': profession,
      if (professionId != null) 'profession_id': professionId,
      'location_type': locationType,
      if (providerId != null) 'provider_id': providerId,
      if (scheduledAt != null) 'scheduled_at': scheduledAt.toIso8601String(),
      if (taskId != null) 'task_id': taskId,
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
          'end_time': scheduledAt.add(const Duration(hours: 1)).toIso8601String(),
          'status': 'waiting_payment',
        };
        await supabase.from('appointments').insert(apptBody);
      }

      return {'success': true, 'serviceId': serviceId, 'service': response};
    } catch (e) {
      debugPrint('❌ [CREATE SERVICE SUPABASE SDK] Erro: $e');
      throw ApiException(message: 'Falha ao criar serviço: $e', statusCode: 500);
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
    
    final double price = double.tryParse(raw['price_estimated']?.toString() ?? '0') ?? 0.0;
    mapped['provider_amount'] = double.parse((price * 0.85).toStringAsFixed(2));
    
    return mapped;
  }

  Future<List<dynamic>> getMyServices() async {
    if (_userId == null) return [];
    try {
      final query = Supabase.instance.client
          .from('service_requests_new')
          .select('*, users!client_id(full_name, avatar_url), providers!provider_id(users!user_id(full_name, avatar_url)), service_categories!category_id(name)');
          
      final response = _role == 'provider'
          ? await query.eq('provider_id', _userId!).order('created_at', ascending: false)
          : await query.eq('client_id', _userId!).order('created_at', ascending: false);
          
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
          .select('*, users!client_id(full_name, avatar_url), service_categories!category_id(name)')
          .inFilter('status', ['pending', 'open_for_schedule'])
          .is_('provider_id', null)
          .order('created_at', ascending: false);
          
      return response.map((s) => _mapServiceData(s)).toList();
    } catch(e) {
      debugPrint('Erro no getAvailableServices direto do supabase: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getServiceDetails(String serviceId) async {
    try {
      final response = await Supabase.instance.client
          .from('service_requests_new')
          .select('*, users!client_id(full_name, avatar_url), providers!provider_id(users!user_id(full_name, avatar_url)), service_categories!category_id(name)')
          .eq('id', serviceId)
          .maybeSingle();
          
      if (response != null) {
        return _mapServiceData(response);
      }
      throw Exception('Service not found');
    } catch(e) {
      debugPrint('Erro via getServiceDetails Supabase DB SDK: $e');
      rethrow;
    }
  }

  Future<void> acceptService(String serviceId) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('service_requests_new').update({
        'provider_id': _userId,
        'status': 'accepted',
        'status_updated_at': DateTime.now().toIso8601String()
      }).eq('id', serviceId);
    } catch (e) {
      throw ApiException(message: 'Erro ao aceitar: $e');
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
      throw ApiException(message: 'Erro ao rejeitar: $e');
    }
  }

  Future<void> updateServiceStatus(String serviceId, String status) async {
    if (status == 'in_progress') {
      await startService(serviceId);
    } else if (status == 'completed') {
      await completeService(serviceId);
    } else {
      await Supabase.instance.client.from('service_requests_new').update({'status': status}).eq('id', serviceId);
    }
  }

  Future<void> startService(String serviceId) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('service_requests_new').update({
        'status': 'in_progress',
        'started_at': DateTime.now().toIso8601String(),
        'status_updated_at': DateTime.now().toIso8601String()
      }).eq('id', serviceId);
    } catch (e) {
      throw ApiException(message: 'Erro ao iniciar: $e');
    }
  }

  Future<void> completeService(
    String serviceId, {
    String? proofCode,
    String? proofPhoto,
    String? proofVideo,
  }) async {
    await confirmServiceCompletion(serviceId, code: proofCode, proofVideo: proofVideo);
  }

  Future<void> requestServiceCompletion(String serviceId) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.rpc('rpc_request_completion', params: {'p_service_id': serviceId});
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(message: 'Erro ao solicitar a conclusão: $e', statusCode: 500);
    }
  }

  Future<void> submitReview({
    required String serviceId,
    required int rating,
    String? comment,
  }) async {
    final token = await _getToken();
    final response = await _client.post(
      Uri.parse('$baseUrl/services/$serviceId/review'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'rating': rating, 'comment': comment}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to submit review: ${response.statusCode}');
    }
  }

  Future<void> arriveService(String serviceId) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('service_requests_new').update({
        'status': 'waiting_payment_remaining',
        'arrived_at': DateTime.now().toIso8601String(),
        'status_updated_at': DateTime.now().toIso8601String()
      }).eq('id', serviceId);
    } catch (e) {
      throw ApiException(message: 'Erro ao registrar chegada: $e');
    }
  }

  Future<void> contestService(String serviceId, String reason) async {
    // Ideally this inserts the reason into a service_disputes table, but we stick to update for now
    await Supabase.instance.client.from('service_requests_new').update({
      'status': 'contested',
      'status_updated_at': DateTime.now().toIso8601String()
    }).eq('id', serviceId);
  }

  Future<void> cancelService(String serviceId) async {
    await Supabase.instance.client.from('service_requests_new').update({
      'status': 'cancelled',
      'status_updated_at': DateTime.now().toIso8601String()
    }).eq('id', serviceId);
  }

  Future<void> requestServiceEdit({
    required String serviceId,
    required String newDescription,
    required double newPrice,
  }) async {
    await post('/services/$serviceId/edit_request', {
      'description': newDescription,
      'price': newPrice,
    });
  }

  Future<Map<String, dynamic>> fetchFuelPricesByState(String state) async {
    return _getCachedFuel('state_$state', () async {
      try {
        return await get('/fuel/price?state=$state');
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
        return await get('/fuel/price?city=$city&state=$state');
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
      final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4().substring(0, 8)}.$ext';
      final path = '$typePath/$uniqueName';

      final supabase = Supabase.instance.client;
      await supabase.storage.from(bucket).uploadBinary(
        path,
        Uint8List.fromList(bytes),
        fileOptions: FileOptions(contentType: contentType ?? 'application/octet-stream'),
      );

      final publicUrl = supabase.storage.from(bucket).getPublicUrl(path);
      debugPrint('[Supabase Storage] File uploaded successfully: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('❌ [Supabase Storage] Upload error: $e');
      throw ApiException(message: 'Falha no upload para o Supabase: $e', statusCode: 500);
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
    return _directUpload('service_media', 'videos', bytes, filename, mimeType ?? 'video/mp4');
  }

  Future<String> uploadServiceAudio(
    List<int> bytes, {
    String filename = 'audio.m4a',
  }) async {
    return _directUpload('service_media', 'audios', bytes, filename, 'audio/mp4');
  }

  Future<String> uploadChatImage(
    String serviceId,
    List<int> bytes, {
    String filename = 'chat.jpg',
  }) async {
    return _directUpload('chat_media', serviceId, bytes, filename, 'image/jpeg');
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
    return _directUpload('chat_media', serviceId, bytes, filename, mimeType ?? 'video/mp4');
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
      onProgress: onProgress
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
    await Supabase.instance.client.from('service_requests_new').update({
      'payment_remaining_status': 'paid_manual'
    }).eq('id', serviceId);
  }

  Future<void> notifyClientArrived(String serviceId) async {
    await Supabase.instance.client.from('service_requests_new').update({
      'status': 'client_arrived',
      'status_updated_at': DateTime.now().toIso8601String()
    }).eq('id', serviceId);
  }

  // --- Scheduling Flow ---

  Future<List<dynamic>> getAvailableForSchedule() async {
    try {
      final response = await Supabase.instance.client
          .from('service_requests_new')
          .select('*, users!client_id(full_name, avatar_url), service_categories!category_id(name)')
          .inFilter('status', ['pending', 'open_for_schedule'])
          .is_('provider_id', null)
          .order('created_at', ascending: false);
          
      return response.map((s) => _mapServiceData(s)).toList();
    } catch(e) {
      debugPrint('Erro no getAvailableForSchedule direto do supabase: $e');
      return [];
    }
  }

  Future<void> proposeSchedule(String serviceId, DateTime scheduledAt) async {
    await post('/services/$serviceId/propose-schedule', {
      'scheduled_at': scheduledAt.toIso8601String(),
    });
  }

  // confirmSchedule already defined above

  // --- Test & Dev Helpers ---

  Future<void> testApprovePayment(String serviceId) async {
    await post('/test/approve-payment/$serviceId', {});
  }

  // --- Location Search (Mapbox) ---
  
  Future<List<dynamic>> searchLocation(String query, {double? lat, double? lon}) async {
    try {
      String url = '/location/search?q=${Uri.encodeComponent(query)}';
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

  Future<Map<String, dynamic>?> reverseGeocode(double lat, double lon) async {
    try {
      final dynamic res = await get('/location/reverse?lat=$lat&lon=$lon');
      if (res is Map<String, dynamic>) return res;
      return null;
    } catch (e) {
      debugPrint('ReverseGeocode error: $e');
      return null;
    }
  }
  // --- Notifications ---

  Future<void> markNotificationRead(int id) async {
    await put('/notifications/$id/read', {});
  }

  Future<void> markAllNotificationsRead() async {
    await put('/notifications/read-all', {});
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
