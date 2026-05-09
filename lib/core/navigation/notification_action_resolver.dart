import '../../services/models/notification_payload.dart';
import '../utils/notification_type_helper.dart';
import 'notification_navigation_resolver.dart';

enum NotificationActionKind {
  none,
  navigate,
  openChat,
  openProviderArrivedModal,
  openTimeToLeaveModal,
  openServiceOfferModal,
  openScheduledStartedModal,
  processServiceOfferAction,
  openDriverTripOffer,
  resolveServiceLifecycleRoute,
}

class NotificationActionResolution {
  final NotificationActionKind kind;
  final NotificationNavigationTarget? navigationTarget;
  final String? entityId;

  const NotificationActionResolution({
    required this.kind,
    this.navigationTarget,
    this.entityId,
  });

  const NotificationActionResolution.none()
    : kind = NotificationActionKind.none,
      navigationTarget = null,
      entityId = null;
}

class NotificationActionResolver {
  static const bool _tripRuntimeEnabled = false;

  static NotificationActionResolution resolve(
    NotificationPayload payload, {
    required String? role,
    required bool isProviderLikeRole,
    required bool isDriverRole,
  }) {
    final type = payload.type;
    final entityId = payload.entityId;
    final action = payload.data['notification_action']?.toString().trim() ?? '';

    if ((type == 'chat_message' || type == 'chat') && entityId != null) {
      return NotificationActionResolution(
        kind: NotificationActionKind.openChat,
        entityId: entityId,
      );
    }

    if (!_tripRuntimeEnabled &&
        (type == 'central_trip_offer' ||
            type == 'central_trip_accepted' ||
            type == 'central_trip_arrived' ||
            type == 'central_trip_started' ||
            type == 'central_trip_completed' ||
            type == 'central_trip_cancelled')) {
      return const NotificationActionResolution.none();
    }

    if (type == 'central_trip_offer' && isDriverRole) {
      return NotificationActionResolution(
        kind: NotificationActionKind.openDriverTripOffer,
        entityId: entityId,
      );
    }

    if (_isServiceOfferType(type) && action.isNotEmpty) {
      return NotificationActionResolution(
        kind: NotificationActionKind.processServiceOfferAction,
        entityId: entityId,
      );
    }

    if ((type == 'central_trip_accepted' ||
            type == 'central_trip_arrived' ||
            type == 'central_trip_started') &&
        entityId != null) {
      return NotificationActionResolution(
        kind: NotificationActionKind.navigate,
        navigationTarget: NotificationNavigationTarget(
          route: '/uber-tracking/$entityId',
          replace: true,
        ),
        entityId: entityId,
      );
    }

    if ((type == 'central_trip_completed' ||
        type == 'central_trip_cancelled')) {
      if (entityId != null && role == 'driver') {
        return NotificationActionResolution(
          kind: NotificationActionKind.navigate,
          navigationTarget: const NotificationNavigationTarget(
            route: '/uber-driver',
            replace: true,
          ),
          entityId: entityId,
        );
      }
      return NotificationActionResolution(
        kind: NotificationActionKind.navigate,
        navigationTarget: const NotificationNavigationTarget(
          route: '/home',
          replace: true,
        ),
      );
    }

    if (type == 'schedule_proposal') {
      return NotificationActionResolution(
        kind: NotificationActionKind.navigate,
        navigationTarget: NotificationNavigationResolver.homeForRole(role),
        entityId: entityId,
      );
    }

    if ((type == 'schedule_confirmed' || type == 'schedule_30m_reminder') &&
        entityId != null) {
      return NotificationActionResolution(
        kind: NotificationActionKind.navigate,
        navigationTarget: NotificationNavigationResolver.scheduleConfirmed(
          role: role,
          serviceId: entityId,
        ),
        entityId: entityId,
      );
    }

    if (type == 'schedule_proposal_expired') {
      return NotificationActionResolution(
        kind: NotificationActionKind.navigate,
        navigationTarget: NotificationNavigationResolver.homeForRole(role),
      );
    }

    if (type == 'provider_arrived' && entityId != null) {
      return NotificationActionResolution(
        kind: NotificationActionKind.openProviderArrivedModal,
        entityId: entityId,
      );
    }

    if (type == 'time_to_leave') {
      return const NotificationActionResolution(
        kind: NotificationActionKind.openTimeToLeaveModal,
      );
    }

    if (_isServiceOfferType(type)) {
      if (!isProviderLikeRole) {
        return const NotificationActionResolution.none();
      }
      if (isDriverRole) {
        return NotificationActionResolution(
          kind: NotificationActionKind.openDriverTripOffer,
          entityId: entityId,
        );
      }
      if (entityId != null) {
        return NotificationActionResolution(
          kind: NotificationActionKind.openServiceOfferModal,
          entityId: entityId,
        );
      }
    }

    if (type == 'scheduled_started' && entityId != null) {
      return NotificationActionResolution(
        kind: NotificationActionKind.openScheduledStartedModal,
        entityId: entityId,
      );
    }

    if ((type == 'service_started' ||
            type == 'service_completed' ||
            type == 'status_update' ||
            type == 'payment_approved') &&
        entityId != null) {
      return NotificationActionResolution(
        kind: NotificationActionKind.resolveServiceLifecycleRoute,
        entityId: entityId,
      );
    }

    return const NotificationActionResolution.none();
  }

  static bool _isServiceOfferType(String? type) {
    return isServiceOfferNotificationType(type);
  }
}
