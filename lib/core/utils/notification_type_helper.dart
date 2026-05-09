const String kCanonicalServiceOfferType = 'service_offer';

bool isLegacyTripNotificationType(String? type) {
  if (type == null) return false;
  return type.startsWith('central_trip_') ||
      type.startsWith('central_') ||
      type.startsWith('trip_');
}

bool isServiceOfferNotificationType(String? type) {
  return type == kCanonicalServiceOfferType ||
      type == 'new_service' ||
      type == 'offer' ||
      type == 'service_offered' ||
      type == 'service.offered' ||
      type == 'manual_visual_test' ||
      type == 'SERVICE_REQUEST';
}

String? normalizeNotificationType(String? type) {
  if (isServiceOfferNotificationType(type)) {
    return kCanonicalServiceOfferType;
  }
  return type;
}
