import 'package:flutter/material.dart';

import '../../services/ai/genkit_service.dart';

class GenkitTestScreen extends StatefulWidget {
  const GenkitTestScreen({super.key});

  @override
  State<GenkitTestScreen> createState() => _GenkitTestScreenState();
}

class _GenkitTestScreenState extends State<GenkitTestScreen> {
  final TextEditingController _promptController = TextEditingController(
    text: 'Crie uma apresentação curta do app 101 Service para novos usuários.',
  );
  final GenkitService _genkit = GenkitService.instance;

  bool _loading = false;
  String? _response;
  String? _error;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _runPrompt() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      setState(() => _error = 'Digite um prompt para testar o Genkit.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _response = null;
    });

    try {
      final text = await _genkit.generateText(prompt);
      if (!mounted) return;
      setState(() => _response = text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = _genkit.isConfigured;

    return Scaffold(
      appBar: AppBar(title: const Text('Genkit Test')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    configured
                        ? 'Genkit configurado com sucesso'
                        : 'Genkit ainda não configurado',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: configured ? Colors.green : Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Modelo padrão: ${_genkit.defaultModel}'),
                  const SizedBox(height: 8),
                  const SelectableText(
                    'Para abrir o Dev UI com Flutter:\n'
                    'genkit start:flutter -- -d chrome',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _promptController,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Prompt',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loading || !configured ? null : _runPrompt,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Executar Prompt'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade900),
                ),
              ),
            ),
          ],
          if (_response != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(_response!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
