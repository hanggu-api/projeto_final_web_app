import 'package:flutter/material.dart';

import '../../core/utils/fixed_schedule_gate.dart';
import 'home_prestador_fixo.dart';
import 'service_request_screen_mobile.dart';

/// Camada de compatibilidade para testes e fluxos legados.
///
/// O app atual separa o pedido em duas telas:
/// - [ServiceRequestScreenMobile]
/// - [ServiceRequestScreenFixed]
///
/// Este wrapper mantém a API antiga `ServiceRequestScreen`.
class ServiceRequestScreen extends StatelessWidget {
  final String? initialProviderId;
  final Map<String, dynamic>? initialService;
  final Map<String, dynamic>? initialProvider;
  final Map<String, dynamic>? initialData;
  final VoidCallback? onBack;
  final Function(Map<String, dynamic> data)? onSwitchToFixed;

  const ServiceRequestScreen({
    super.key,
    this.initialProviderId,
    this.initialService,
    this.initialProvider,
    this.initialData,
    this.onBack,
    this.onSwitchToFixed,
  });

  Map<String, dynamic> get _flowSeed {
    return <String, dynamic>{
      ...?initialData,
      ...?initialService,
      ...?initialProvider,
      if (initialProviderId != null && initialProviderId!.trim().isNotEmpty)
        'provider_id': initialProviderId,
    };
  }

  bool get _shouldUseFixedFlow {
    final seed = _flowSeed;
    if (seed.isEmpty) return false;
    return isCanonicalFixedServiceRecord(seed);
  }

  @override
  Widget build(BuildContext context) {
    if (_shouldUseFixedFlow) {
      return ServiceRequestScreenFixed(
        initialProviderId: int.tryParse(initialProviderId ?? ''),
        initialService: initialService,
        initialProvider: initialProvider,
        initialData: initialData,
        onBack: onBack,
      );
    }

    return ServiceRequestScreenMobile(
      initialData: initialData,
      onSwitchToFixed: onSwitchToFixed,
    );
  }
}
