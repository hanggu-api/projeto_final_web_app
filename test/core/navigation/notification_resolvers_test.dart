import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/core/navigation/notification_action_resolver.dart';
import 'package:service_101/core/navigation/notification_navigation_resolver.dart';
import 'package:service_101/services/models/notification_payload.dart';

void main() {
  group('NotificationActionResolver', () {
    NotificationPayload payload(Map<String, dynamic> data) {
      return NotificationPayload.fromMap(data);
    }

    test('abre chat para chat_message com service_id', () {
      final result = NotificationActionResolver.resolve(
        payload({
          'type': 'chat_message',
          'service_id': 'svc-1',
        }),
        role: 'client',
        isProviderLikeRole: false,
        isDriverRole: false,
      );

      expect(result.kind, NotificationActionKind.openChat);
      expect(result.entityId, 'svc-1');
    });

    test('ignora eventos legacy de trip quando runtime está desativado', () {
      final result = NotificationActionResolver.resolve(
        payload({
          'type': 'central_trip_arrived',
          'trip_id': 'trip-1',
        }),
        role: 'driver',
        isProviderLikeRole: true,
        isDriverRole: true,
      );

      expect(result.kind, NotificationActionKind.none);
    });

    test('abre modal de oferta para provider em service_offered', () {
      final result = NotificationActionResolver.resolve(
        payload({
          'type': 'service_offered',
          'service_id': 'svc-2',
        }),
        role: 'provider',
        isProviderLikeRole: true,
        isDriverRole: false,
      );

      expect(result.kind, NotificationActionKind.openServiceOfferModal);
      expect(result.entityId, 'svc-2');
    });

    test('processa ação explícita da oferta', () {
      final result = NotificationActionResolver.resolve(
        payload({
          'type': 'service.offered',
          'service_id': 'svc-3',
          'notification_action': 'service_accept',
        }),
        role: 'provider',
        isProviderLikeRole: true,
        isDriverRole: false,
      );

      expect(result.kind, NotificationActionKind.processServiceOfferAction);
      expect(result.entityId, 'svc-3');
    });

    test('resolve rota de lifecycle para service_completed', () {
      final result = NotificationActionResolver.resolve(
        payload({
          'type': 'service_completed',
          'service_id': 'svc-4',
        }),
        role: 'client',
        isProviderLikeRole: false,
        isDriverRole: false,
      );

      expect(result.kind, NotificationActionKind.resolveServiceLifecycleRoute);
      expect(result.entityId, 'svc-4');
    });
  });

  group('NotificationNavigationResolver', () {
    test('scheduleConfirmed envia provider para provider-active com replace', () {
      final target = NotificationNavigationResolver.scheduleConfirmed(
        role: 'provider',
        serviceId: 'svc-10',
      );

      expect(target.route, '/provider-active/svc-10');
      expect(target.replace, isTrue);
    });

    test('homeForRole envia client para home', () {
      final target = NotificationNavigationResolver.homeForRole('client');

      expect(target.route, '/home');
      expect(target.replace, isTrue);
    });

    test('serviceLifecycleFallback envia client para service-tracking', () {
      final target = NotificationNavigationResolver.serviceLifecycleFallback(
        role: 'client',
        serviceId: 'svc-20',
      );

      expect(target.route, '/service-tracking/svc-20');
      expect(target.replace, isFalse);
    });

    test('serviceLifecycleFromDetails envia provider fixo para provider-home', () {
      final target = NotificationNavigationResolver.serviceLifecycleFromDetails(
        role: 'provider',
        serviceId: 'svc-30',
        details: {'is_fixed': true, 'at_provider': true},
      );

      expect(target.route, '/provider-home');
      expect(target.replace, isTrue);
    });
  });
}
