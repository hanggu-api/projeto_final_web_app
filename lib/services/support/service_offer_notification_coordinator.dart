import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/notification_navigation_resolver.dart';
import '../../features/provider/widgets/service_offer_modal.dart';

class ServiceOfferNotificationCoordinator {
  static Future<void> openDriverFlow(
    BuildContext context, {
    required Map<String, dynamic> data,
    required bool tripRuntimeEnabled,
  }) async {
    if (!tripRuntimeEnabled) return;
    GoRouter.of(context).go('/uber-driver', extra: {'initialTripOffer': data});
  }

  static Widget buildProviderOfferModal({
    required String serviceId,
    required Map<String, dynamic> data,
    required VoidCallback navigateToAcceptedService,
  }) {
    return ServiceOfferModal(
      serviceId: serviceId,
      initialData: data,
      onAccepted: navigateToAcceptedService,
    );
  }

  static void navigateProviderAcceptedService(
    BuildContext context, {
    required String serviceId,
  }) {
    final target = NotificationNavigationResolver.providerAcceptedService(
      serviceId: serviceId,
    );
    GoRouter.of(context).go(target.route);
  }
}
