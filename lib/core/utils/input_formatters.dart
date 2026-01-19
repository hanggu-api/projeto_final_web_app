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

class PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Remove non-digits
    final newText = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    // Determine max length (11 digits for mobile: (XX) XXXXX-XXXX)
    if (newText.length > 11) return oldValue;

    final buffer = StringBuffer();

    for (int i = 0; i < newText.length; i++) {
      if (i == 0) buffer.write('(');
      if (i == 2) buffer.write(') ');
      if (i == 7 && newText.length > 10) {
        buffer.write('-'); // Mobile: (XX) XXXXX-XXXX
      } else if (i == 6 && newText.length <= 10) {
        buffer.write('-'); // Landline: (XX) XXXX-XXXX
      }

      buffer.write(newText[i]);
    }

    final string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
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
