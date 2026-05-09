class BackgroundServiceFlags {
  // Hotfix: desabilita o flutter_background_service legado para evitar
  // criação de engines extras e conflitos de isolate.
  static const bool enableLegacyBackgroundService = false;
}

