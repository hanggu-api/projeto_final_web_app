import 'package:flutter/material.dart';
import 'service_request_screen_fixed.dart';
import 'service_request_screen_mobile.dart';

class ServiceRequestScreen extends StatefulWidget {
  final int? initialProviderId;
  final Map<String, dynamic>? initialService;
  final Map<String, dynamic>? initialProvider;
  final String? initialPrompt;

  const ServiceRequestScreen({
    super.key,
    this.initialProviderId,
    this.initialService,
    this.initialProvider,
    this.initialPrompt,
  });

  @override
  State<ServiceRequestScreen> createState() => _ServiceRequestScreenState();
}

class _ServiceRequestScreenState extends State<ServiceRequestScreen> {
  // Estado que determina qual tela mostrar.
  // 'mobile' -> Fluxo Imediato/Móvel (Default para genérico)
  // 'fixed' -> Fluxo Agendado (Se provider inicial for fixo ou AI detectar)
  String _currentFlow = 'mobile';

  // Dados transferidos entre as telas caso haja troca de contexto
  Map<String, dynamic>? _transferredData;

  @override
  void initState() {
    super.initState();
    if (widget.initialPrompt != null) {
      _transferredData = {'description': widget.initialPrompt};
    }
    _determineInitialFlow();
  }

  void _determineInitialFlow() {
    // 1. Se veio com Provider ou Serviço inicial, verificamos o tipo
    if (widget.initialService != null) {
      final rawType = widget.initialService!['service_type'];
      if (rawType == 'at_provider') {
        _currentFlow = 'fixed';
        return;
      }
      // Fallback by name
      final name = (widget.initialService!['name'] ?? '')
          .toString()
          .toLowerCase();
      if (_isFixedByName(name)) {
        _currentFlow = 'fixed';
        return;
      }
    }

    if (widget.initialProvider != null) {
      // Check provider traits
      // Se o provider tem endereço fixo cadastrado e serviço "no local", é fixo.
      // Simplificação: Se initialProviderId não é nulo, geralmente no app atual
      // o usuário clicou em "Agendar" num perfil de prestador Fixo (Barbearias).
      // Prestadores móveis são chamados via "Solicitar" genérico.
      // MAS, se tiver borracharia específica...
      // Por enquanto, assumimos que escolher provider específico -> Fluxo Agendado (Fixo UI)
      // A MENOS que seja explicitamente móvel (Uber-like).
      // Vamos assumir 'fixed' se providerId existe, pois Mobile flow é "find random".
      _currentFlow = 'fixed';
    }
  }

  bool _isFixedByName(String name) {
    if (name.contains('barbeiro') ||
        name.contains('cabel') ||
        name.contains('manic') ||
        name.contains('dentista')) {
      return true;
    }
    return false;
  }

  void _switchToFixed(Map<String, dynamic> data) {
    setState(() {
      _currentFlow = 'fixed';
      _transferredData = data;
    });
  }

  void _backToMobile() {
    setState(() {
      _currentFlow = 'mobile';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentFlow == 'fixed') {
      return ServiceRequestScreenFixed(
        initialProviderId: widget.initialProviderId,
        initialService: widget.initialService,
        initialProvider: widget.initialProvider,
        initialData: _transferredData, // PASSANDO DADOS DA IA
        onBack: _backToMobile,
      );
    } else {
      return ServiceRequestScreenMobile(
        initialData: _transferredData,
        onSwitchToFixed: _switchToFixed,
      );
    }
  }
}
