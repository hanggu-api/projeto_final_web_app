import 'package:flutter/foundation.dart';

/// Gerenciador Global de Inicialização (Semáforo)
/// Controla quando widgets pesados (mapas, vídeos, webviews) podem ser carregados.
class GlobalStartupManager {
  static final GlobalStartupManager instance = GlobalStartupManager._internal();
  
  // Notifier booleano: false = bloqueado, true = liberado
  final ValueNotifier<bool> canLoadHeavyWidgets = ValueNotifier(false);

  GlobalStartupManager._internal();

  /// Libera o carregamento de widgets pesados
  void unleashTheBeast() {
    if (canLoadHeavyWidgets.value) return;
    
    debugPrint('🦁 [GlobalStartupManager] Liberando a besta! (Widgets pesados autorizados)');
    canLoadHeavyWidgets.value = true;
  }
  
  /// (Opcional) Reseta o estado (ex: ao fazer logout)
  void reset() {
    canLoadHeavyWidgets.value = false;
  }
}
