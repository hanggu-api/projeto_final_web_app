import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ServiceIconMapper {
  ServiceIconMapper._();

  static IconData fromService({
    String? taskName,
    String? professionName,
    String? keywords,
  }) {
    final text = '${taskName ?? ''} ${professionName ?? ''} ${keywords ?? ''}'
        .toLowerCase();

    if (_hasAny(text, const ['chave', 'fechadura', 'cadeado'])) {
      return LucideIcons.key;
    }
    if (_hasAny(text, const ['eletric', 'tomada', 'disjuntor', 'fiação'])) {
      return LucideIcons.zap;
    }
    if (_hasAny(text, const ['encan', 'hidrau', 'vazamento', 'pia', 'ralo'])) {
      return LucideIcons.droplets;
    }
    if (_hasAny(text, const ['grama', 'jardim', 'poda', 'paisag'])) {
      return LucideIcons.leaf;
    }
    if (_hasAny(text, const ['limpeza', 'faxina', 'diarista'])) {
      return LucideIcons.sprayCan;
    }
    if (_hasAny(text, const ['barbeir', 'cabelo', 'salão', 'salao', 'corte'])) {
      return LucideIcons.scissors;
    }
    if (_hasAny(text, const ['manicure', 'pedicure', 'unha'])) {
      return LucideIcons.hand;
    }
    if (_hasAny(text, const ['estetic', 'beleza', 'sobrancelha', 'maqui'])) {
      return LucideIcons.sparkles;
    }
    if (_hasAny(text, const ['mecan', 'automot', 'carro', 'moto'])) {
      return LucideIcons.car;
    }
    if (_hasAny(text, const ['informática', 'informatica', 'pc', 'notebook'])) {
      return LucideIcons.laptop;
    }
    if (_hasAny(text, const ['pintura', 'pintor', 'tinta'])) {
      return LucideIcons.paintbrush;
    }
    if (_hasAny(text, const ['frete', 'mudança', 'mudanca', 'entrega'])) {
      return LucideIcons.truck;
    }
    if (_hasAny(text, const ['costura', 'roupa', 'ajuste'])) {
      return LucideIcons.shirt;
    }

    return LucideIcons.briefcase;
  }

  static bool _hasAny(String text, List<String> tokens) {
    for (final token in tokens) {
      if (text.contains(token)) return true;
    }
    return false;
  }
}

