import 'package:flutter/foundation.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_google_genai/genkit_google_genai.dart';

import '../../core/config/genkit_config.dart';

class GenkitService {
  GenkitService._() {
    if (GenkitConfig.isConfigured) {
      _registerFlows();
    }
  }

  static final GenkitService instance = GenkitService._();

  late final Genkit _ai = Genkit(
    plugins: [googleAI(apiKey: GenkitConfig.geminiApiKey)],
  );

  bool _flowsRegistered = false;

  bool get isConfigured => GenkitConfig.isConfigured;
  String get defaultModel => GenkitConfig.defaultModel;

  void initialize() {
    if (!isConfigured) {
      debugPrint(
        '⚠️ [GenkitService] GEMINI_API_KEY ausente. Genkit desativado.',
      );
      return;
    }
    _registerFlows();
  }

  void _registerFlows() {
    if (_flowsRegistered || !isConfigured) return;

    _ai.defineFlow(
      name: 'play101BasicGenerate',
      inputSchema: .string(
        defaultValue: 'Explique o que o app 101 Service faz.',
      ),
      outputSchema: .string(),
      fn: (input, _) async {
        final response = await _ai.generate(
          model: googleAI.gemini(defaultModel),
          prompt: input,
        );
        return response.text;
      },
    );

    _flowsRegistered = true;
    debugPrint('✅ [GenkitService] Flow play101BasicGenerate registrado.');
  }

  Future<String> generateText(String prompt, {String? model}) async {
    final normalizedPrompt = prompt.trim();
    if (!isConfigured) {
      throw StateError('GEMINI_API_KEY não configurada.');
    }
    if (normalizedPrompt.isEmpty) {
      throw ArgumentError('Prompt vazio.');
    }

    final response = await _ai.generate(
      model: googleAI.gemini((model ?? defaultModel).trim()),
      prompt: normalizedPrompt,
    );

    return response.text.trim();
  }
}
