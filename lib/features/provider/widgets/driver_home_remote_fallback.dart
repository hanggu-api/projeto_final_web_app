import 'package:flutter/material.dart';

import '../provider_home_mobile.dart';

class DriverHomeRemoteFallback extends StatelessWidget {
  const DriverHomeRemoteFallback({
    super.key,
    required this.loadOnInit,
    required this.connectRealtime,
    required this.initialAvailableServices,
    required this.initialMyServices,
  });

  final bool loadOnInit;
  final bool connectRealtime;
  final List<dynamic>? initialAvailableServices;
  final List<dynamic>? initialMyServices;

  @override
  Widget build(BuildContext context) {
    return ProviderHomeMobile(
      loadOnInit: loadOnInit,
      connectRealtime: connectRealtime,
      initialAvailableServices: initialAvailableServices,
      initialMyServices: initialMyServices,
    );
  }
}
