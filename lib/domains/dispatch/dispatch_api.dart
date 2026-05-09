import 'models/service_offer_state.dart';

typedef RawServiceOfferStateLoader =
    Future<Map<String, dynamic>?> Function(String serviceId);
typedef AcceptDispatchService = Future<Map<String, dynamic>> Function(
  String serviceId,
);
typedef RejectDispatchService = Future<void> Function(String serviceId);

class DispatchApi {
  final RawServiceOfferStateLoader _loadActiveProviderOfferState;
  final AcceptDispatchService _acceptService;
  final RejectDispatchService _rejectService;

  const DispatchApi({
    required RawServiceOfferStateLoader loadActiveProviderOfferState,
    required AcceptDispatchService acceptService,
    required RejectDispatchService rejectService,
  }) : _loadActiveProviderOfferState = loadActiveProviderOfferState,
       _acceptService = acceptService,
       _rejectService = rejectService;

  Future<ServiceOfferState?> getActiveProviderOfferState(String serviceId) async {
    final raw = await _loadActiveProviderOfferState(serviceId);
    if (raw == null) return null;
    return ServiceOfferState.fromMap(serviceId, raw);
  }

  Future<Map<String, dynamic>> acceptService(String serviceId) {
    return _acceptService(serviceId);
  }

  Future<void> rejectService(String serviceId) {
    return _rejectService(serviceId);
  }
}
