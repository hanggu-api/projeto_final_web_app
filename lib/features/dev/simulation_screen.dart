import 'dart:convert';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../services/api_service.dart';

class SimulationScreen extends StatefulWidget {
  const SimulationScreen({super.key});

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen> {
  final List<String> _logs = [];
  bool _running = false;
  int _clients = 3;
  int _providers = 3;
  int _servicesPerClient = 2;
  int _messagesPerService = 3;
  int _parallelism = 8;
  String _apiUrl = '';

  @override
  void initState() {
    super.initState();
    try {
      _apiUrl = ApiService.baseUrl;
      // Use Future.microtask to avoid build context issues during init
      Future.microtask(() {
        try {
          if (kIsWeb) {
            _log('Web Mode: Inicializado');
          } else {
            _log('Mobile Mode: Inicializado');
          }
        } catch (e) {
          debugPrint('Error in microtask: $e');
        }
      });

      final base = Uri.base;
      final frag = Uri.tryParse(base.fragment);
      final qp = <String, String>{}
        ..addAll(base.queryParameters)
        ..addAll(frag?.queryParameters ?? {});
      final auto = qp['auto'] == '1';
      final api = qp['api'];
      final c = int.tryParse(qp['clients'] ?? '');
      final p = int.tryParse(qp['providers'] ?? '');
      final spc = int.tryParse(qp['spc'] ?? '');
      final mps = int.tryParse(qp['mps'] ?? '');
      final par = int.tryParse(qp['p'] ?? '');
      if (api != null && api.isNotEmpty) _apiUrl = api;
      if (c != null && c > 0) _clients = c;
      if (p != null && p > 0) _providers = p;
      if (spc != null && spc > 0) _servicesPerClient = spc;
      if (mps != null && mps > 0) _messagesPerService = mps;
      if (par != null && par > 0) _parallelism = par;
      if (auto) Future.microtask(_run);
    } catch (e) {
      debugPrint('Error in initState: $e');
      Future.microtask(() => _log('Erro na inicialização: $e'));
    }
  }

  String _stateName = 'Maranhão';
  String _fromLat = '-5.5264'; // Latitude Centro de Imperatriz
  String _fromLon = '-47.4819'; // Longitude Centro de Imperatriz
  String _toLat =
      '-5.5245'; // Coordenada próxima para cálculo de rota/distância
  String _toLon = '-47.4760'; // Ex: Próximo à Praça de Fátima

  // ==== Video test state ====
  final ImagePicker _picker = ImagePicker();
  XFile? _videoFile;
  VideoPlayerController? _videoController;
  String? _uploadedKey;
  String? _viewUrl;
  bool _uploadingVideo = false;

  // ==== Full Flow Test State ====
  int? _createdServiceId;
  String? _clientToken;
  String? _providerToken;
  int? _providerId;
  bool _simulatingMovement = false;

  // Time for simulation
  TimeOfDay _scheduledTime = const TimeOfDay(hour: 14, minute: 0);

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _scheduledTime,
    );
    if (t != null) setState(() => _scheduledTime = t);
  }

  Future<void> _runFullFlow() async {
    await _createFullFlowService();
    if (_createdServiceId != null) {
      await _acceptServiceFlow();
    }
  }

  Future<void> _createFullFlowService() async {
    try {
      _log('--- Iniciando Fluxo Completo ---');
      final runId = (DateTime.now().millisecondsSinceEpoch % 10000)
          .toString()
          .padLeft(4, '0');

      // 1. Login/Register Client
      final clientEmail =
          'client_flow_${DateTime.now().millisecondsSinceEpoch}@test.com';
      _log('Criando Cliente: $clientEmail');
      final clientReg = await _post('/auth/register', {
        'email': clientEmail,
        'password': 'password123',
        'name': 'Cliente Flow',
        'role': 'client',
        'phone': '1198$runId',
      });
      _clientToken = clientReg['token'];
      _log('Cliente Criado. Token obtido.');

      // 2. Login/Register Provider
      final provEmail =
          'prov_flow_${DateTime.now().millisecondsSinceEpoch}@test.com';
      _log('Criando Prestador: $provEmail');
      final provReg = await _post('/auth/register', {
        'email': provEmail,
        'password': 'password123',
        'name': 'Prestador Flow',
        'role': 'provider',
        'phone': '1197$runId',
      });
      _providerToken = provReg['token'];
      _providerId = provReg['user']['id'];
      _log('Prestador Criado. ID: $_providerId');

      // 3. Create Service (as Client)
      _log('Criando Serviço...');
      final now = DateTime.now();
      final scheduledDate = DateTime(
        now.year,
        now.month,
        now.day,
        _scheduledTime.hour,
        _scheduledTime.minute,
      );

      final serviceRes = await _post('/services', {
        'category_id': 1,
        'description': 'Serviço de Teste Fluxo Completo',
        'latitude': -23.5505,
        'longitude': -46.6333,
        'address': 'Rua Teste, 123',
        'price_estimated': 150.00,
        'price_upfront': 50.00,
        'scheduled_at': scheduledDate.toIso8601String(),
      }, token: _clientToken);

      _createdServiceId = serviceRes['service']['id'];
      _log('Serviço Criado: ID $_createdServiceId');
      setState(() {});
    } catch (e) {
      _log('Erro fluxo criação: $e');
    }
  }

  Future<void> _acceptServiceFlow() async {
    if (_createdServiceId == null || _providerToken == null) {
      _log('Erro: Crie o serviço primeiro.');
      return;
    }
    try {
      _log('Aceitando serviço $_createdServiceId como Prestador...');
      await _post(
        '/services/$_createdServiceId/accept',
        {},
        token: _providerToken,
      );
      _log('Serviço Aceito!');

      // Entra na sala do serviço (via Socket) se possível, mas aqui estamos via HTTP
      // Vamos simular via API
    } catch (e) {
      _log('Erro ao aceitar: $e');
    }
  }

  Future<void> _simulateMovementFlow() async {
    if (_createdServiceId == null || _providerToken == null) {
      _log('Erro: Serviço não aceito ou inexistente.');
      return;
    }
    if (_simulatingMovement) {
      _simulatingMovement = false;
      _log('Parando simulação de movimento.');
      return;
    }

    setState(() => _simulatingMovement = true);
    _log('Iniciando simulação de trajeto (Provider -> Client)...');

    // Simples interpolação linear
    double lat = -23.5590; // Provider start
    double lon = -46.6250;
    final destLat = -23.5505; // Client location
    final destLon = -46.6333;

    final steps = 20;
    final stepLat = (destLat - lat) / steps;
    final stepLon = (destLon - lon) / steps;

    for (int i = 0; i <= steps; i++) {
      if (!_simulatingMovement || !mounted) break;

      lat += stepLat;
      lon += stepLon;

      try {
        // Envia localização via Socket (se estivesse conectado como provider)
        // Como o app está rodando logado como "Dev" ou outro user,
        // vamos usar o RealtimeService para emitir como se fosse o provider,
        // mas precisamos que o socket esteja autenticado como provider.
        // O RealtimeService é Singleton. Vamos tentar emitir o evento 'update_location'
        // Mas o backend valida o socket.user.id?
        // Se sim, precisamos reconectar o socket como o provider.

        // Alternativa: Endpoint HTTP de update location (se existir)
        // Se não existir, vamos apenas logar que "enviaria"

        // Vamos usar o RealtimeService atual apenas para logar na tela
        _log('📍 Movimento [$i/$steps]: $lat, $lon');

        // Se quisermos ver no mapa do cliente, precisaríamos estar na tela de Tracking.
        // Aqui é apenas simulação de backend/log.

        // Mock envio para API (se existisse endpoint de location via HTTP)
        // await _post('/provider/location', {'lat': lat, 'lon': lon}, token: _providerToken);
      } catch (e) {
        _log('Erro mov: $e');
      }

      await Future.delayed(const Duration(seconds: 1));
    }

    if (mounted) {
      setState(() => _simulatingMovement = false);
      _log('Chegou ao destino!');
    }
  }

  Future<void> _simulatePaymentFlow() async {
    if (_createdServiceId == null || _clientToken == null) {
      _log('Erro: Serviço não criado.');
      return;
    }
    try {
      _log('Simulando Pagamento do Serviço $_createdServiceId...');
      // 1. Tokenize Card (Mock MP)
      // Como não temos o SDK JS aqui, vamos usar o endpoint de teste ou simular
      // O PaymentService usa a API do MP. Vamos tentar usar um token de teste.
      final cardToken =
          'tok_test_visa_12345'; // Token fictício para testes mockados

      _log('Token Cartão (Simulado): $cardToken');

      // 2. Process Payment
      // Precisamos chamar o endpoint /payment/process
      // O ApiService já tem o método, mas vamos chamar via _post para usar o token do cliente criado

      final paymentBody = {
        'transaction_amount':
            0.01, // Valor simbólico, backend recalcula com base no serviço
        'token': cardToken,
        'description': 'Pagamento Serviço $_createdServiceId',
        'installments': 1,
        'payment_method_id': 'visa',
        'payer': {'email': 'client_flow@test.com'},
        'service_id': _createdServiceId.toString(),
      };

      _log('Enviando pagamento...');
      final payRes = await _post(
        '/payment/process',
        paymentBody,
        token: _clientToken,
      );

      _log('Pagamento Processado!');
      _log('Status: ${payRes['payment']['status']}');
      _log('ID Transação: ${payRes['payment']['id']}');
    } catch (e) {
      _log('Erro pagamento: $e');
    }
  }

  void _log(String m) {
    if (!mounted) return;
    setState(() => _logs.add(m));
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final resp = await http.post(
      Uri.parse('$_apiUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    final data = jsonDecode(resp.body);
    if (resp.statusCode >= 200 && resp.statusCode < 300) return data;
    throw Exception(data['message'] ?? 'Erro');
  }

  Future<void> _testNotification() async {
    try {
      _log('Solicitando notificação de teste...');
      final api = ApiService();
      final userId = await api.getMyUserId();

      await api.post('/test-notification', {
        'userId': userId,
        'title': 'Teste Local',
        'body': 'Verifique se recebeu o banner!',
        'type': 'test_notification',
      });
      _log('Pedido enviado! Aguarde o banner.');
    } catch (e) {
      _log('Erro ao testar notificação: $e');
    }
  }

  Future<void> _pickVideoCamera() async {
    try {
      final vid = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
      );
      if (vid != null) {
        _setVideoFile(vid);
      }
    } catch (e) {
      _log('Erro ao gravar vídeo: $e');
    }
  }

  Future<void> _pickVideoGallery() async {
    try {
      final vid = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (vid != null) {
        _setVideoFile(vid);
      }
    } catch (e) {
      _log('Erro ao selecionar vídeo: $e');
    }
  }

  Future<void> _setVideoFile(XFile file) async {
    try {
      _videoController?.dispose();
      if (kIsWeb) {
        _videoController = VideoPlayerController.networkUrl(
          Uri.parse(file.path),
        );
      } else {
        _videoController = VideoPlayerController.contentUri(
          Uri.file(file.path),
        );
      }
      await _videoController!.initialize();
      await _videoController!.setLooping(true);
      await _videoController!.play();
      if (!mounted) return;
      setState(() {
        _videoFile = file;
        _uploadedKey = null;
        _viewUrl = null;
      });
    } catch (e) {
      _log('Falha ao inicializar player: $e');
    }
  }

  Future<void> _uploadVideo() async {
    if (_videoFile == null) return;
    if (!mounted) return;
    setState(() {
      _uploadingVideo = true;
      _logs.add('Enviando vídeo...');
    });
    try {
      final api = ApiService();
      String key;
      final bytes = await _videoFile!.readAsBytes();
      key = await api.uploadServiceVideo(bytes, filename: _videoFile!.name);

      if (!mounted) return;
      setState(() {
        _uploadedKey = key;
        _logs.add('Upload OK: key=$key');
      });
    } catch (e) {
      if (mounted) setState(() => _logs.add('Falha upload: $e'));
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  Future<void> _loadViewUrl() async {
    if (_uploadedKey == null) return;
    try {
      final api = ApiService();
      // Use proxy URL to avoid CORS on Web
      final url =
          '${ApiService.baseUrl}/media/content?key=${Uri.encodeComponent(_uploadedKey!)}';

      if (!mounted) return;
      setState(() {
        _viewUrl = url;
        _logs.add('URL carregada (Proxy)');
      });
      // Preview via network controller
      _videoController?.dispose();
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: api.authHeaders,
      );
      await _videoController!.initialize();
      await _videoController!.setLooping(true);
      await _videoController!.play();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _logs.add('Falha ao obter URL: $e'));
    }
  }

  Future<void> _testFuel() async {
    try {
      final api = ApiService();
      final res = await api.fetchFuelPricesByState(_stateName);
      _log('Combustível($_stateName): $res');
    } catch (e) {
      _log('Falha combustível: $e');
    }
  }

  Future<void> _testRoute() async {
    try {
      final api = ApiService();
      final res = await api.getRouteMetrics(
        fromLat: double.parse(_fromLat),
        fromLon: double.parse(_fromLon),
        toLat: double.parse(_toLat),
        toLon: double.parse(_toLon),
      );
      _log('Rota: $res');
    } catch (e) {
      _log('Falha rota: $e');
    }
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _logs.clear();
    });
    final runId = (DateTime.now().millisecondsSinceEpoch % 1000)
        .toString()
        .padLeft(3, '0');
    final clients = <Map<String, dynamic>>[];
    final providers = <Map<String, dynamic>>[];
    final services = <Map<String, dynamic>>[];
    try {
      final clientIndices = List.generate(_clients, (i) => i);
      await _processInBatches(clientIndices, _parallelism, (i) async {
        final email =
            'client_${DateTime.now().millisecondsSinceEpoch}_$i@test.com';
        final reg = await _post('/auth/register', {
          'email': email,
          'password': 'securePass123!',
          'name': 'Cliente $i',
          'role': 'client',
          'phone': '1190$runId${i.toString().padLeft(4, '0')}',
        });
        clients.add({
          'id': reg['user']['id'],
          'token': reg['token'],
          'email': email,
        });
        if (i % 25 == 0) _log('Clientes registrados: ${clients.length}');
      });

      final providerIndices = List.generate(_providers, (i) => i);
      await _processInBatches(providerIndices, _parallelism, (i) async {
        final email =
            'provider_${DateTime.now().millisecondsSinceEpoch}_$i@test.com';
        final reg = await _post('/auth/register', {
          'email': email,
          'password': 'securePass123!',
          'name': 'Prestador $i',
          'role': 'provider',
          'phone': '1191$runId${i.toString().padLeft(4, '0')}',
        });
        providers.add({
          'id': reg['user']['id'],
          'token': reg['token'],
          'email': email,
        });
        if (i % 25 == 0) _log('Prestadores registrados: ${providers.length}');
      });

      final servicePairs = <Map<String, int>>[];
      for (var ci = 0; ci < clients.length; ci++) {
        for (var k = 0; k < _servicesPerClient; k++) {
          servicePairs.add({'ci': ci, 'k': k});
        }
      }
      await _processInBatches(servicePairs, _parallelism, (pair) async {
        final ci = (pair)['ci'] as int;
        final k = (pair)['k'] as int;
        final c = clients[ci];
        final lat = -23.55 + (k + 1) * 0.001;
        final lon = -46.63 + (k + 1) * 0.001;
        final priceEst = 100 + (k * 25);
        final priceUp = (priceEst * 0.3).round();
        final desc = 'Serviço ${k + 1} descrição teste';
        final created = await _post('/services', {
          'category_id': (k % 3) + 1,
          'description': desc,
          'latitude': lat,
          'longitude': lon,
          'address': 'Rua Teste $k, 123',
          'price_estimated': priceEst,
          'price_upfront': priceUp,
          'scheduled_at': DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
            _scheduledTime.hour,
            _scheduledTime.minute,
          ).toIso8601String(),
        }, token: c['token'] as String);
        services.add({'id': created['id'], 'clientId': c['id']});
        if (services.length % 50 == 0) {
          _log('Serviços criados: ${services.length}');
        }
      });

      final acceptIndices = List.generate(services.length, (i) => i);
      await _processInBatches(acceptIndices, _parallelism, (i) async {
        final s = services[i];
        final prov = providers[i % providers.length];
        try {
          await _post(
            '/services/${s['id']}/accept',
            {},
            token: prov['token'] as String,
          );
        } catch (_) {}
        if (i % 100 == 0) _log('Aceites: ${i + 1}/${services.length}');
      });

      final chatIndices = List.generate(services.length, (i) => i);
      await _processInBatches(chatIndices, _parallelism, (i) async {
        final s = services[i];
        final prov = providers[i % providers.length];
        final client = clients.firstWhere(
          (c) => c['id'] == s['clientId'],
          orElse: () => clients.first,
        );
        for (var m = 0; m < _messagesPerService; m++) {
          final isClient = m % 2 == 0;
          final token = isClient
              ? client['token'] as String
              : prov['token'] as String;
          await _post('/chat/${s['id']}', {
            'content': 'Msg ${m + 1} serviço ${s['id']}',
          }, token: token);
        }
        if (i % 100 == 0) {
          _log('Chats enviados: serviço ${i + 1}/${services.length}');
        }
      });

      _log(
        'Concluído: clientes=${clients.length} prestadores=${providers.length} serviços=${services.length} chats=${services.length * _messagesPerService}',
      );
    } catch (e) {
      _log('Falha: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _processInBatches<T>(
    List<T> items,
    int batchSize,
    Future<void> Function(T item) op,
  ) async {
    var index = 0;
    while (index < items.length) {
      final end = (index + batchSize) > items.length
          ? items.length
          : (index + batchSize);
      final slice = items.sublist(index, end);
      await Future.wait(slice.map(op));
      index = end;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Simulação Frontend')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // API URL Config
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: _apiUrl,
                  onChanged: (v) => _apiUrl = v,
                  decoration: const InputDecoration(labelText: 'API URL'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(100, 48),
                  ),
                  onPressed: () async {
                    await ApiService().setBaseUrl(_apiUrl);
                    _log('API_URL aplicado: $_apiUrl');
                  },
                  child: const Text('Aplicar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Fuel/Route Tests
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Teste APIs Combustível e Rota',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: _stateName,
                        onChanged: (v) => _stateName = v,
                        decoration: const InputDecoration(labelText: 'Estado'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(120, 48),
                        ),
                        onPressed: _testFuel,
                        child: const Text('Testar Combustível'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: _fromLat,
                        onChanged: (v) => _fromLat = v,
                        decoration: const InputDecoration(labelText: 'De Lat'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: _fromLon,
                        onChanged: (v) => _fromLon = v,
                        decoration: const InputDecoration(labelText: 'De Lon'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: _toLat,
                        onChanged: (v) => _toLat = v,
                        decoration: const InputDecoration(
                          labelText: 'Para Lat',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: _toLon,
                        onChanged: (v) => _toLon = v,
                        decoration: const InputDecoration(
                          labelText: 'Para Lon',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _testRoute,
                    child: const Text('Testar Rota'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Params
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: '$_clients',
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _clients = int.tryParse(v) ?? _clients,
                  decoration: const InputDecoration(labelText: 'Clientes'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: '$_providers',
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _providers = int.tryParse(v) ?? _providers,
                  decoration: const InputDecoration(labelText: 'Prestadores'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: '$_servicesPerClient',
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _servicesPerClient =
                      int.tryParse(v) ?? _servicesPerClient,
                  decoration: const InputDecoration(labelText: 'Serviços/Cli'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: '$_messagesPerService',
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _messagesPerService =
                      int.tryParse(v) ?? _messagesPerService,
                  decoration: const InputDecoration(labelText: 'Msgs/Serv'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: '$_parallelism',
                  keyboardType: TextInputType.number,
                  onChanged: (v) =>
                      _parallelism = int.tryParse(v) ?? _parallelism,
                  decoration: const InputDecoration(labelText: 'Paralelismo'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: _pickTime,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Horário Agendado',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      '${_scheduledTime.hour.toString().padLeft(2, '0')}:${_scheduledTime.minute.toString().padLeft(2, '0')}',
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Execute Button
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _running ? null : _run,
                child: const Text('Rodar Simulação Carga'),
              ),
              ElevatedButton(
                onPressed: _running ? null : _runFullFlow,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('Rodar Fluxo Completo (Imperatriz)'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (!kIsWeb) {
                    FirebaseCrashlytics.instance.crash();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Crashlytics não suportado na Web'),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Testar Crash (Crashlytics)'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Full Flow Test Section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blueAccent),
              borderRadius: BorderRadius.circular(8),
              color: Colors.blue.withAlpha(13), // ~0.05 opacity
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Simulação de Fluxo Completo (Passo a Passo)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(120, 48),
                      ),
                      onPressed: _createFullFlowService,
                      child: const Text('1. Criar Serviço'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(120, 48),
                      ),
                      onPressed: _createdServiceId == null
                          ? null
                          : _acceptServiceFlow,
                      child: const Text('2. Aceitar Serviço'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(120, 48),
                      ),
                      onPressed: (_createdServiceId == null)
                          ? null
                          : (_simulatingMovement
                                ? null
                                : _simulateMovementFlow),
                      child: Text(
                        _simulatingMovement
                            ? 'Movendo...'
                            : '3. Simular Trajeto',
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(120, 48),
                      ),
                      onPressed: _createdServiceId == null
                          ? null
                          : _simulatePaymentFlow,
                      child: const Text('4. Simular Pagamento'),
                    ),
                  ],
                ),
                if (_createdServiceId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text('Service ID Atual: $_createdServiceId'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Video Test Section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ElevatedButton(
                  onPressed: _testNotification,
                  child: const Text('🔔 Testar Notificação (Local)'),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Teste Upload de Vídeo',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(120, 48),
                      ),
                      onPressed: _pickVideoCamera,
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Câmera'),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(120, 48),
                      ),
                      onPressed: _pickVideoGallery,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Galeria'),
                    ),
                  ],
                ),
                if (_videoFile != null) ...[
                  const SizedBox(height: 8),
                  Text('Selecionado: ${_videoFile!.name}'),
                  const SizedBox(height: 8),
                  if (_videoController != null &&
                      _videoController!.value.isInitialized)
                    AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    ),
                  const SizedBox(height: 8),
                  if (_uploadingVideo)
                    const Center(child: CircularProgressIndicator())
                  else
                    ElevatedButton(
                      onPressed: _uploadVideo,
                      child: const Text('Enviar Vídeo para S3'),
                    ),
                ],
                if (_uploadedKey != null) ...[
                  const SizedBox(height: 8),
                  SelectableText('Key: $_uploadedKey'),
                  ElevatedButton(
                    onPressed: _loadViewUrl,
                    child: const Text('Carregar URL de Visualização'),
                  ),
                ],
                if (_viewUrl != null) ...[
                  const SizedBox(height: 8),
                  SelectableText('URL: $_viewUrl'),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Text('Logs:', style: TextStyle(fontWeight: FontWeight.bold)),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _logs.length,
              itemBuilder: (context, i) => Text(
                _logs[i],
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
