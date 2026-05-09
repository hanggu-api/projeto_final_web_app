import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter/foundation.dart';

class CNHData {
  final String? nome;
  final String? cpf;
  final String? rg;
  final String? dataNascimento;
  final String? localNascimento;
  final String? pai;
  final String? mae;
  final String? registro;
  final String? validade;
  final String? emissao;
  final String? primeiraHabilitacao;
  final String? categoria;
  final bool isValidCNH;
  final String rawText;

  CNHData({
    this.nome,
    this.cpf,
    this.rg,
    this.dataNascimento,
    this.localNascimento,
    this.pai,
    this.mae,
    this.registro,
    this.validade,
    this.emissao,
    this.primeiraHabilitacao,
    this.categoria,
    this.isValidCNH = false,
    required this.rawText,
  });

  Map<String, dynamic> toMap() {
    return {
      'nome': nome,
      'cpf': cpf,
      'rg': rg,
      'dataNascimento': dataNascimento,
      'localNascimento': localNascimento,
      'pai': pai,
      'mae': mae,
      'registro': registro,
      'validade': validade,
      'emissao': emissao,
      'primeiraHabilitacao': primeiraHabilitacao,
      'categoria': categoria,
      'isValidCNH': isValidCNH,
    };
  }

  @override
  String toString() {
    return 'CNHData(nome: $nome, cpf: $cpf, registro: $registro, valid: $isValidCNH)';
  }
}

class OcrService {
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  Future<CNHData> processCNH(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );

      String fullText = recognizedText.text;
      debugPrint('📄 [OCR Bruto Local]:\n$fullText');

      return _parseCNH(fullText);
    } catch (e) {
      debugPrint('❌ Erro no OCR local: $e');
      return CNHData(rawText: 'Erro: $e');
    }
  }

  CNHData _parseCNH(String text) {
    final lines = text.split('\n').map((e) => e.trim().toUpperCase()).toList();

    String? nome;
    String? cpf;
    String? nasc;
    String? pai;
    String? mae;
    String? registro;
    String? validade;
    String? categoria;
    String? rg;
    String? localNasc;
    String? emissao;
    String? primeiraHab;

    String cleanText = text
        .toUpperCase()
        .replaceAll(',', '.')
        .replaceAll('O', '0')
        .replaceAll('S', '8')
        .replaceAll('I', '1')
        .replaceAll('B', '8')
        .replaceAll('L', '1')
        .replaceAll('Z', '2');

    final dateRegex = RegExp(r'\d{2}/\d{2}/\d{4}');
    final registroRegex = RegExp(r'\d{10,11}');
    final catRegex = RegExp(r'\b[ABCDE]{1,2}\b');

    // Limpeza para CPF (remove espaços e troca vírgula por ponto para o regex)
    // Tenta encontrar o padrão de CPF formatado primeiro ou perto da palavra CPF
    final textForCpf = text.replaceAll(',', '.');
    final cpfMatch = RegExp(
      r'\b\d{3}\.\d{3}\.\d{3}-\d{2}\b',
    ).firstMatch(textForCpf);
    if (cpfMatch != null) {
      cpf = cpfMatch.group(0);
    } else {
      // Fallback para CPF sem formatação mas que não seja o RG (que geralmente começa com 0 ou tem mais dígitos)
      final allNumbers = text.replaceAll(RegExp(r'\D'), '');
      final cpfRegexFlex = RegExp(r'\b\d{11}\b');
      final matches = cpfRegexFlex.allMatches(allNumbers);
      for (var m in matches) {
        final val = m.group(0)!;
        // Se encontramos 11 dígitos e não é o número de registro (que extraímos abaixo)
        if (text.contains('CPF') &&
            text.indexOf('CPF') < text.indexOf(val) + 20) {
          cpf = val;
          break;
        }
      }
    }

    final registroMatch = registroRegex.firstMatch(cleanText);
    if (registroMatch != null) registro = registroMatch.group(0);

    final dateMatches = dateRegex
        .allMatches(text)
        .map((m) => m.group(0))
        .toList();

    if (dateMatches.length >= 4) {
      nasc = dateMatches[0];
      validade = dateMatches[1];
      primeiraHab = dateMatches[2];
      emissao = dateMatches[3];
    } else if (dateMatches.length >= 2) {
      nasc = dateMatches[0];
      validade = dateMatches[1];
    } else if (dateMatches.isNotEmpty) {
      nasc = dateMatches[0];
    }

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.contains('NOME') ||
          line.contains('SOBRENOME') ||
          line.contains('CONDUTOR')) {
        if (i + 1 < lines.length) {
          final possibleName = lines[i + 1];
          if (!possibleName.contains('ASSINATURA') &&
              !possibleName.contains('DATA') &&
              !possibleName.contains('DOC') &&
              possibleName.length > 5) {
            nome = possibleName;
            // Se o nome foi encontrado via rótulo, paramos a busca básica para esse campo
          }
        }
      }

      if (line.contains('CAT') || line.contains('HAB')) {
        final match = catRegex.firstMatch(line);
        if (match != null) {
          categoria = match.group(0);
        } else if (i + 1 < lines.length) {
          final nextMatch = catRegex.firstMatch(lines[i + 1]);
          if (nextMatch != null) categoria = nextMatch.group(0);
        }
      }

      if (line.contains('FILIAÇÃO') ||
          line.contains('PAI') ||
          line.contains('MÃE')) {
        if (i + 1 < lines.length) pai = lines[i + 1];
        if (i + 2 < lines.length) mae = lines[i + 2];
      }

      if (line.contains('DOC') ||
          line.contains('IDENTIDADE') ||
          line.contains('ORG')) {
        final rgMatch = RegExp(r'[\d\-X]{6,}').firstMatch(line);
        if (rgMatch != null) {
          rg = rgMatch.group(0);
        } else if (i + 1 < lines.length) {
          final nextRgMatch = RegExp(r'[\d\-X]{6,}').firstMatch(lines[i + 1]);
          if (nextRgMatch != null) rg = nextRgMatch.group(0);
        }
      }

      if (line.contains('LOCAL') || line.contains('NASCIMENT')) {
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1];
          if (nextLine.length > 3) localNasc = nextLine;
        }
      }
    }

    // Heurística de fallback para nome
    if (nome == null) {
      final commonLabels = [
        'REPUBLICA',
        'REPÚBLICA',
        'FEDERATIVA',
        'MINISTERIO',
        'MINISTÉRIO',
        'CARTEIRA',
        'NACIONAL',
        'HABILITACAO',
        'HABILITAÇÃO',
        'DRIVER',
        'LICENSE',
        'NOME',
        'SOBRENOME',
        'BRASIL',
        'DETRAN',
        'TRANSITO',
        'TRÂNSITO',
        'INFRAESTRUTURA',
        'PERMISO',
        'CONDUCCION',
      ];
      for (var line in lines) {
        if (line.length > 10 &&
            !line.contains(RegExp(r'\d')) &&
            !commonLabels.any((l) => line.contains(l))) {
          nome = line;
          break;
        }
      }
    }

    // Critérios de identificação flexíveis (Heurística de Pontuação)
    int score = 0;

    // 1. Verificar palavras-chave do título/documento
    final docKeywords = [
      'CARTEIRA',
      'NACIONAL',
      'HABILIT',
      'CONDUTOR',
      'PERMISO',
      'LICENSE',
      'DRIVER',
      'DETRAN',
    ];
    for (var kw in docKeywords) {
      if (text.contains(kw)) score += 2;
    }

    // 2. Verificar identificadores governamentais
    final govKeywords = [
      'REPUBLICA',
      'BRASIL',
      'MINISTERIO',
      'TRANSITO',
      'INFRAESTRUTURA',
      'SECRETARIA',
    ];
    for (var kw in govKeywords) {
      if (text.contains(kw)) score += 2;
    }

    // 3. Verificar campos essenciais
    if (registro != null && registro.length >= 9) score += 5;
    if (cpf != null) score += 3;
    if (nome != null && nome.length > 5) score += 3;
    if (categoria != null) score += 2;

    // Um documento é válido se atingir uma pontuação mínima (ex: 12)
    // Isso permite que ele seja validado mesmo se algumas palavras forem mal lidas
    bool isValid = score >= 12;

    debugPrint('📊 [OCR Score]: $score (Min: 12) - Valid: $isValid');

    return CNHData(
      nome: nome,
      cpf: cpf,
      rg: rg,
      dataNascimento: nasc,
      localNascimento: localNasc,
      pai: pai,
      mae: mae,
      registro: registro,
      validade: validade,
      emissao: emissao,
      primeiraHabilitacao: primeiraHab,
      categoria: categoria,
      isValidCNH: isValid,
      rawText: text,
    );
  }

  void dispose() {
    _textRecognizer.close();
  }
}
