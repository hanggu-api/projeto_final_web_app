import 'package:flutter/foundation.dart';
import 'device_capability_service.dart';

/// Gerenciador Global de Inicialização (Semáforo)
/// Controla quando widgets pesados (mapas, vídeos, webviews) podem ser carregados.
class GlobalStartupManager {
  static final GlobalStartupManager instance = GlobalStartupManager._internal();

  // Notifier booleano: false = bloqueado, true = liberado
  final ValueNotifier<bool> canLoadHeavyWidgets = ValueNotifier(false);
  final ValueNotifier<bool> isStartingUp = ValueNotifier(true);

  GlobalStartupManager._internal();

  /// Libera o carregamento de widgets pesados com delay de segurança
  Future<void> unleashTheBeast() async {
    if (canLoadHeavyWidgets.value) return;

    // Pequeno respiro antes de autorizar widgets pesados (evita context loss)
    final delay = DeviceCapabilityService.instance.prefersReducedBackground
        ? const Duration(milliseconds: 1800)
        : const Duration(milliseconds: 500);
    await Future.delayed(delay);

    debugPrint(
      '🦁 [GlobalStartupManager] Liberando a besta! (Widgets pesados autorizados)',
    );
    canLoadHeavyWidgets.value = true;
    isStartingUp.value = false;
  }

  /// (Opcional) Reseta o estado (ex: ao fazer logout)
  void reset() {
    canLoadHeavyWidgets.value = false;
  }
}
