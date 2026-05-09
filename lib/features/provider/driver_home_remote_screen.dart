import 'package:flutter/material.dart';

import '../../core/remote_ui/remote_screen_body.dart';
import 'widgets/driver_home_remote_fallback.dart';

class DriverHomeRemoteScreen extends StatelessWidget {
  const DriverHomeRemoteScreen({
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
    return SafeArea(
      child: RemoteScreenBody(
        screenKey: 'driver_home',
        padding: const EdgeInsets.all(16),
        fallbackBuilder: (_) => DriverHomeRemoteFallback(
          loadOnInit: loadOnInit,
          connectRealtime: connectRealtime,
          initialAvailableServices: initialAvailableServices,
          initialMyServices: initialMyServices,
        ),
      ),
    );
  }
}
