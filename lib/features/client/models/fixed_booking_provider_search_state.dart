class FixedBookingProviderSearchState {
  List<Map<String, dynamic>> providers;
  List<Map<String, dynamic>> unavailableProviders;
  final List<Map<String, dynamic>> pendingProviders;
  final List<Map<String, dynamic>> pendingUnavailableProviders;
  bool loadingProviders;
  bool loadingMoreProviders;
  bool isRevealingMoreProviders;
  bool providerSearchCompleted;
  bool providerSearchHasAnyMatch;
  String providerSearchMessage;
  String providerSearchDetail;
  int providersRequestId;
  int? expandedProviderId;

  FixedBookingProviderSearchState({
    List<Map<String, dynamic>>? providers,
    List<Map<String, dynamic>>? unavailableProviders,
    List<Map<String, dynamic>>? pendingProviders,
    List<Map<String, dynamic>>? pendingUnavailableProviders,
    this.loadingProviders = false,
    this.loadingMoreProviders = false,
    this.isRevealingMoreProviders = false,
    this.providerSearchCompleted = false,
    this.providerSearchHasAnyMatch = false,
    this.providerSearchMessage = 'Buscando prestadores mais próximos...',
    this.providerSearchDetail =
        'Estamos localizando salões fixos próximos a você.',
    this.providersRequestId = 0,
    this.expandedProviderId,
  }) : providers = providers ?? [],
       unavailableProviders = unavailableProviders ?? [],
       pendingProviders = pendingProviders ?? [],
       pendingUnavailableProviders = pendingUnavailableProviders ?? [];

  void resetForNewSearch({
    required bool preserveExpandedProvider,
    int? preservedExpandedProviderId,
  }) {
    loadingProviders = true;
    loadingMoreProviders = false;
    providerSearchCompleted = false;
    providerSearchHasAnyMatch = false;
    providerSearchMessage = 'Buscando prestadores mais próximos...';
    providerSearchDetail = 'Estamos localizando salões fixos próximos a você.';
    providers = [];
    unavailableProviders = [];
    pendingProviders.clear();
    pendingUnavailableProviders.clear();
    expandedProviderId = preserveExpandedProvider
        ? preservedExpandedProviderId
        : null;
  }
}
