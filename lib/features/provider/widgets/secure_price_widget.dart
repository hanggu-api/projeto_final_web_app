import 'package:flutter/material.dart';

/// Widget simples para exibir preços.
/// A proteção de tela foi removida para garantir compatibilidade com todos os ambientes.
class SecurePriceWidget extends StatelessWidget {
  final double value;
  final TextStyle style;
  final String currency;

  const SecurePriceWidget({
    super.key,
    required this.value,
    this.style = const TextStyle(
      color: Colors.black87,
      fontSize: 24,
      fontWeight: FontWeight.bold,
    ),
    this.currency = 'R\$',
  });

  @override
  Widget build(BuildContext context) {
    final text =
        '$currency ${value.toStringAsFixed(2).replaceAll('.', ',')}';
    return Text(text, style: style);
  }
}
