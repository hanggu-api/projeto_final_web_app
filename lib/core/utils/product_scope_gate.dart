class ProductScopeGate {
  ProductScopeGate._();

  /// O app está sendo lançado apenas com o fluxo móvel de prestadores.
  static const bool enableSalonScheduling = false;

  static bool get isSalonSchedulingEnabled => enableSalonScheduling;

  static bool get isMobileProviderOnlyMode => !enableSalonScheduling;
}
