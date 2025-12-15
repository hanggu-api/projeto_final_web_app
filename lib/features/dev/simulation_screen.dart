import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
  String _apiUrl = const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:4002');

  void _log(String m) {
    setState(() => _logs.add(m));
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body, {String? token}) async {
    final resp = await http.post(Uri.parse('$_apiUrl$path'), headers: {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    }, body: jsonEncode(body));
    final data = jsonDecode(resp.body);
    if (resp.statusCode >= 200 && resp.statusCode < 300) return data;
    throw Exception(data['message'] ?? 'Erro');
  }


  Future<void> _run() async {
    if (_running) return;
    setState(() { _running = true; _logs.clear(); });
    final clients = <Map<String, dynamic>>[];
    final providers = <Map<String, dynamic>>[];
    final services = <Map<String, dynamic>>[];
    try {
      final clientIndices = List.generate(_clients, (i) => i);
      await _processInBatches(clientIndices, _parallelism, (i) async {
        final email = 'client_${DateTime.now().millisecondsSinceEpoch}_$i@test.com';
        final reg = await _post('/auth/register', {
          'email': email,
          'password': 'securePass123!',
          'name': 'Cliente $i',
          'role': 'client',
          'phone': '1190000${i.toString().padLeft(4, '0')}'
        });
        clients.add({'id': reg['user']['id'], 'token': reg['token'], 'email': email});
        if (i % 25 == 0) _log('Clientes registrados: ${clients.length}');
      });

      final providerIndices = List.generate(_providers, (i) => i);
      await _processInBatches(providerIndices, _parallelism, (i) async {
        final email = 'provider_${DateTime.now().millisecondsSinceEpoch}_$i@test.com';
        final reg = await _post('/auth/register', {
          'email': email,
          'password': 'securePass123!',
          'name': 'Prestador $i',
          'role': 'provider',
          'phone': '1191000${i.toString().padLeft(4, '0')}'
        });
        providers.add({'id': reg['user']['id'], 'token': reg['token'], 'email': email});
        if (i % 25 == 0) _log('Prestadores registrados: ${providers.length}');
      });

      final servicePairs = <Map<String,int>>[];
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
        }, token: c['token'] as String);
        services.add({'id': created['id'], 'clientId': c['id']});
        if (services.length % 50 == 0) _log('Serviços criados: ${services.length}');
      });

      final acceptIndices = List.generate(services.length, (i) => i);
      await _processInBatches(acceptIndices, _parallelism, (i) async {
        final s = services[i];
        final prov = providers[i % providers.length];
        try {
          await _post('/services/${s['id']}/accept', {}, token: prov['token'] as String);
        } catch (_) {}
        if (i % 100 == 0) _log('Aceites: ${i + 1}/${services.length}');
      });

      final chatIndices = List.generate(services.length, (i) => i);
      await _processInBatches(chatIndices, _parallelism, (i) async {
        final s = services[i];
        final prov = providers[i % providers.length];
        final client = clients.firstWhere((c) => c['id'] == s['clientId'], orElse: () => clients.first);
        for (var m = 0; m < _messagesPerService; m++) {
          final isClient = m % 2 == 0;
          final token = isClient ? client['token'] as String : prov['token'] as String;
          await _post('/chat/${s['id']}', {'content': 'Msg ${m + 1} serviço ${s['id']}'}, token: token);
        }
        if (i % 100 == 0) _log('Chats enviados: serviço ${i + 1}/${services.length}');
      });

      _log('Concluído: clientes=${clients.length} prestadores=${providers.length} serviços=${services.length} chats=${services.length * _messagesPerService}');
    } catch (e) {
      _log('Falha: $e');
    } finally {
      setState(() => _running = false);
    }
  }

  @override
  void initState() {
    super.initState();
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
  }

  Future<void> _processInBatches<T>(List<T> items, int batchSize, Future<void> Function(T item) op) async {
    var index = 0;
    while (index < items.length) {
      final end = (index + batchSize) > items.length ? items.length : (index + batchSize);
      final slice = items.sublist(index, end);
      await Future.wait(slice.map(op));
      index = end;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Simulação Frontend')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: TextFormField(initialValue: _apiUrl, onChanged: (v) => _apiUrl = v, decoration: const InputDecoration(labelText: 'API URL'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(initialValue: '$_clients', keyboardType: TextInputType.number, onChanged: (v) => _clients = int.tryParse(v) ?? _clients, decoration: const InputDecoration(labelText: 'Clientes'))),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(initialValue: '$_providers', keyboardType: TextInputType.number, onChanged: (v) => _providers = int.tryParse(v) ?? _providers, decoration: const InputDecoration(labelText: 'Prestadores'))),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(initialValue: '$_servicesPerClient', keyboardType: TextInputType.number, onChanged: (v) => _servicesPerClient = int.tryParse(v) ?? _servicesPerClient, decoration: const InputDecoration(labelText: 'Serviços por cliente'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextFormField(initialValue: '$_messagesPerService', keyboardType: TextInputType.number, onChanged: (v) => _messagesPerService = int.tryParse(v) ?? _messagesPerService, decoration: const InputDecoration(labelText: 'Mensagens por serviço'))),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(initialValue: '$_parallelism', keyboardType: TextInputType.number, onChanged: (v) => _parallelism = int.tryParse(v) ?? _parallelism, decoration: const InputDecoration(labelText: 'Paralelismo'))),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(onPressed: _running ? null : _run, child: Text(_running ? 'Executando...' : 'Executar')),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.all(8),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (_, i) => Text(_logs[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}