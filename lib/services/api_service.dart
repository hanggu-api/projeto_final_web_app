import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String _envApiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://cardapyia.com/api');
  static String get baseUrl {
    if (_envApiUrl.isNotEmpty) {
      return _envApiUrl;
    }
    if (kIsWeb) {
      return 'http://localhost:4001';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:4001';
    }
    return 'http://localhost:4001';
  }
  
  String? _token;
  String? _role;
  static final Map<String, Future<Uint8List>> _mediaBytesCache = {};

  // Singleton
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // Carregar token salvo
  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    _role = prefs.getString('user_role');
  }

  // Salvar token
  Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  // Limpar token (logout)
  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  bool get isLoggedIn => _token != null;
  String? get role => _role;

  // Headers padrão
  Map<String, String> get _headers {
    final headers = {'Content-Type': 'application/json'};
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  // POST genérico
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> body) async {
    debugPrint('[POST] $baseUrl$endpoint');
    final response = await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: _headers,
      body: jsonEncode(body),
    );
    debugPrint('[POST] status ${response.statusCode}');
    return _handleResponse(response);
  }

  // GET genérico
  Future<Map<String, dynamic>> get(String endpoint) async {
    debugPrint('[GET] $baseUrl$endpoint');
    final response = await http.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: _headers,
    );
    debugPrint('[GET] status ${response.statusCode}');
    return _handleResponse(response);
  }

  Future<http.Response> getRaw(String endpoint, {Map<String, String>? extraHeaders}) async {
    final headers = {..._headers, if (extraHeaders != null) ...extraHeaders};
    debugPrint('[GET RAW] $baseUrl$endpoint');
    final response = await http.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
    );
    debugPrint('[GET RAW] status ${response.statusCode}');
    return response;
  }

  // Tratamento de resposta
  Map<String, dynamic> _handleResponse(http.Response response) {
    Map<String, dynamic> data = {};
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      data = {'raw': response.body};
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }
    if (response.statusCode == 401) {
      clearToken();
    }
    final msg = (data['message'] ?? data['error'] ?? data['errors'] ?? data['raw'] ?? 'Erro desconhecido').toString();
    throw ApiException(message: msg, statusCode: response.statusCode);
  }

  // ========== AUTH ==========
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
    required String role, // 'client' ou 'provider'
    String? phone,
  }) async {
    final result = await post('/auth/register', {
      'email': email,
      'password': password,
      'name': name,
      'role': role,
      'phone': phone,
    });
    
    if (result['token'] != null) {
      await saveToken(result['token']);
    }
    if (result['user'] != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('user_id', result['user']['id']);
      await prefs.setString('user_role', result['user']['role']);
    }
    
    return result;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final result = await post('/auth/login', {
      'email': email,
      'password': password,
    });
    
    if (result['token'] != null) {
      await saveToken(result['token']);
    }
    if (result['user'] != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('user_id', result['user']['id']);
      await prefs.setString('user_role', result['user']['role']);
    }
    
    return result;
  }

  Future<int?> getMyUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id');
  }

  // ========== SERVICES ==========
  Future<Map<String, dynamic>> createService({
    required int categoryId,
    required String description,
    required double latitude,
    required double longitude,
    required String address,
    required double priceEstimated,
    required double priceUpfront,
    List<String> imageKeys = const [],
    String? videoKey,
    List<String> audioKeys = const [],
  }) async {
    await loadToken();
    final body = {
      'category_id': categoryId,
      'description': description,
      'latitude': double.parse(latitude.toStringAsFixed(8)),
      'longitude': double.parse(longitude.toStringAsFixed(8)),
      'address': address,
      'price_estimated': double.parse(priceEstimated.toStringAsFixed(2)),
      'price_upfront': double.parse(priceUpfront.toStringAsFixed(2)),
      if (imageKeys.isNotEmpty) 'images': imageKeys,
      if (videoKey != null) 'video': videoKey,
      if (audioKeys.isNotEmpty) 'audios': audioKeys,
    };
    return await post('/services', body);
  }

  // Retorna serviços pedidos (cliente) OU serviços aceitos (prestador)
  Future<List<dynamic>> getMyServices() async {
    final result = await get('/services/my');
    return result['services'] ?? [];
  }

  // Apenas para prestadores verem o que está livre
  Future<List<dynamic>> getAvailableServices() async {
    final result = await get('/services/available');
    return result['services'] ?? [];
  }

  Future<Map<String, dynamic>> getServiceDetails(String serviceId) async {
    final result = await get('/services/$serviceId');
    return result['service'];
  }

  Future<void> acceptService(String serviceId) async {
    await post('/services/$serviceId/accept', {});
  }

  Future<void> startService(String serviceId) async {
    await post('/services/$serviceId/start', {});
  }

  Future<void> completeService(String serviceId) async {
    await post('/services/$serviceId/complete', {});
  }

  // ========== CHAT ==========
  Future<List<dynamic>> getChatMessages(String serviceId) async {
    final result = await get('/chat/$serviceId');
    return result['messages'] ?? [];
  }

  Future<void> sendMessage(String serviceId, String content, {String type = 'text'}) async {
    await post('/chat/$serviceId', {
      'content': content,
      'type': type,
    });
  }

  Future<Map<String, dynamic>> uploadMultipart(
    String endpoint,
    String fieldName,
    List<int> bytes, {
    String filename = 'file',
    String mimeType = 'application/octet-stream',
    Map<String, String>? fields,
  }) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final request = http.MultipartRequest('POST', uri);
    if (_token == null) {
      await loadToken();
    }
    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    final parts = mimeType.split('/');
    request.files.add(
      http.MultipartFile.fromBytes(
        fieldName,
        bytes,
        filename: filename,
        contentType: MediaType(parts[0], parts[1]),
      ),
    );
    if (fields != null) {
      request.fields.addAll(fields);
    }
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return _handleResponse(response);
  }

  Future<String> uploadChatImage(String serviceId, List<int> bytes, {String filename = 'image'}) async {
    final resp = await uploadMultipart('/media/chat/image', 'file', bytes, filename: filename, mimeType: 'application/octet-stream', fields: {
      'serviceId': serviceId,
    });
    return resp['key'];
  }

  Future<String> uploadChatAudioMp3(String serviceId, List<int> bytes, {String filename = 'audio.mp3'}) async {
    final resp = await uploadMultipart('/media/chat/audio', 'file', bytes, filename: filename, mimeType: 'audio/mpeg', fields: {
      'serviceId': serviceId,
    });
    return resp['key'];
  }

  Future<String> uploadChatAudio(String serviceId, List<int> bytes, {String filename = 'audio', String mimeType = 'audio/mpeg'}) async {
    final resp = await uploadMultipart('/media/chat/audio', 'file', bytes, filename: filename, mimeType: mimeType, fields: {
      'serviceId': serviceId,
    });
    return resp['key'];
  }

  Future<String> getMediaViewUrl(String key) async {
    final resp = await get('/media/view?key=${Uri.encodeComponent(key)}');
    return resp['url'];
  }

  Future<Uint8List> getMediaBytes(String key) async {
    return _mediaBytesCache.putIfAbsent(key, () async {
      final response = await getRaw('/media/content?key=${Uri.encodeComponent(key)}');
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      if (response.statusCode == 401) {
        await clearToken();
      }
      throw ApiException(message: 'Falha ao obter mídia', statusCode: response.statusCode);
    });
  }

  Future<String> uploadServiceImage(List<int> bytes, {String filename = 'image'}) async {
    final resp = await uploadMultipart('/media/service/image', 'file', bytes, filename: filename, mimeType: 'application/octet-stream');
    return resp['key'];
  }

  Future<String> uploadServiceVideo(List<int> bytes, {String filename = 'video.mp4'}) async {
    final resp = await uploadMultipart('/media/service/video', 'file', bytes, filename: filename, mimeType: 'video/mp4');
    return resp['key'];
  }

  Future<String> uploadServiceAudio(List<int> bytes, {String filename = 'audio.m4a', String mimeType = 'audio/mp4'}) async {
    final resp = await uploadMultipart('/media/service/audio', 'file', bytes, filename: filename, mimeType: mimeType);
    return resp['key'];
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException({required this.message, required this.statusCode});

  @override
  String toString() => message;
}
