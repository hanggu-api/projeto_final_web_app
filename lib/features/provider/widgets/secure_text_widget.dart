import 'package:flutter/material.dart';

/// Widget simples para exibir textos.
/// A proteção de tela foi removida para garantir compatibilidade com todos os ambientes.
class SecureTextWidget extends StatelessWidget {
  final String text;
  final TextStyle style;
  final int? maxLines;

  const SecureTextWidget({
    super.key,
    required this.text,
    required this.style,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : null,
    );
  }
}
