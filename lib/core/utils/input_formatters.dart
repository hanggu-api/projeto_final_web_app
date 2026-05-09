import 'package:flutter/services.dart';

import 'package:intl/intl.dart';

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.selection.baseOffset == 0) {
      return newValue;
    }

    double value = double.parse(newValue.text.replaceAll(RegExp(r'[^\d]'), ''));

    final formatter = NumberFormat.simpleCurrency(locale: "pt_BR");
    String newText = formatter.format(value / 100);

    return newValue.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

/// Formata apenas dígitos para exibição (XX) 9XXXX-XXXX (celular com 9).
/// Útil para valor inicial do controller.
String formatPhoneDisplay(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.length > 11) return digits.substring(0, 11);
  final buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i == 0) buffer.write('(');
    if (i == 2) buffer.write(') ');
    if (i == 7) buffer.write('-'); // (XX) 9XXXX-XXXX
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Retorna apenas os dígitos do telefone (11 para móvel).
String phoneDigitsOnly(String? value) {
  if (value == null) return '';
  return value.replaceAll(RegExp(r'[^\d]'), '').length > 11
      ? value.replaceAll(RegExp(r'[^\d]'), '').substring(0, 11)
      : value.replaceAll(RegExp(r'[^\d]'), '');
}

class PhoneInputFormatter extends TextInputFormatter {
  static const Set<String> _validDDDs = {
    '11', '12', '13', '14', '15', '16', '17', '18', '19',
    '21', '22', '24', '27', '28', '31', '32', '33', '34', '35', '37', '38',
    '41', '42', '43', '44', '45', '46', '47', '48', '49',
    '51', '53', '54', '55', '61', '62', '63', '64', '65', '66', '67', '68', '69',
    '71', '73', '74', '75', '77', '79', '81', '82', '83', '84', '85', '86', '87', '88', '89',
    '91', '92', '93', '94', '95', '96', '97', '98', '99'
  };

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    // Permitir backspace/remoção sem bloquear
    if (newValue.text.length < oldValue.text.length) {
      return newValue;
    }

    // Bloqueia se ultrapassar 11 dígitos
    if (digits.length > 11) return oldValue;

    // Validação de DDD (primeiros 2 dígitos)
    if (digits.length >= 1) {
      if (digits[0] == '0') return oldValue; // DDD não começa com 0
    }
    if (digits.length >= 2) {
      final ddd = digits.substring(0, 2);
      if (!_validDDDs.contains(ddd)) return oldValue; // DDD inválido
    }

    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 0) buffer.write('(');
      if (i == 2) buffer.write(') ');
      // Ajuste para celular (11 dígitos) vs telefone fixo (10 dígitos)
      if (digits.length == 11) {
        if (i == 7) buffer.write('-'); // (XX) 9XXXX-XXXX
      } else {
        if (i == 6 && digits.length > 6) buffer.write('-'); // (XX) XXXX-XXXX
      }
      buffer.write(digits[i]);
    }

    final string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }

  /// Verifica se o número (apenas dígitos) tem um DDD válido e tamanho correto.
  static bool isValid(String value) {
    final digits = value.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length < 10 || digits.length > 11) return false;
    if (digits[0] == '0') return false;
    final ddd = digits.substring(0, 2);
    return _validDDDs.contains(ddd);
  }
}

class CpfCnpjInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Remove non-digits
    final newText = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    // Permitir backspace/remoção sem bloquear
    if (newValue.text.length < oldValue.text.length) {
      return newValue;
    }

    // Max length for CNPJ is 14 digits
    if (newText.length > 14) return oldValue;

    final buffer = StringBuffer();

    // CPF: XXX.XXX.XXX-XX (11 digits)
    // CNPJ: XX.XXX.XXX/XXXX-XX (14 digits)

    if (newText.length <= 11) {
      // CPF Mask
      for (int i = 0; i < newText.length; i++) {
        if (i == 3 || i == 6) buffer.write('.');
        if (i == 9) buffer.write('-');
        buffer.write(newText[i]);
      }
    } else {
      // CNPJ Mask
      for (int i = 0; i < newText.length; i++) {
        if (i == 2 || i == 5) buffer.write('.');
        if (i == 8) buffer.write('/');
        if (i == 12) buffer.write('-');
        buffer.write(newText[i]);
      }
    }

    final string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}
