import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/runtime/app_runtime_service.dart';
import '../services/remote_config_service.dart';

class AppRuntimeDiagnosticBanner extends StatelessWidget {
  const AppRuntimeDiagnosticBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final shouldShow =
        kDebugMode ||
        RemoteConfigService.getBool(
          'flag.runtime_diagnostics.visible',
          defaultValue: false,
        );
    if (!shouldShow) {
      return const SizedBox.shrink();
    }

    final runtime = AppRuntimeService.instance.snapshot;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.08))),
      ),
      child: Text(
        'store ${runtime.storeVersion} | patch ${runtime.patchVersion} | env ${runtime.environment}',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF51606F),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
