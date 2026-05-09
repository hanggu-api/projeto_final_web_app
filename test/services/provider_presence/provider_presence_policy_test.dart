import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/services/provider_presence/provider_presence_policy.dart';

void main() {
  group('ProviderPresencePolicy', () {
    test('prestador movel online com coordenada envia heartbeat', () {
      final decision = ProviderPresencePolicy.resolve(
        onlineForDispatch: true,
        isFixedLocation: false,
        canAttemptBackend: true,
        hasCoords: true,
      );

      expect(decision.result, ProviderPresenceTickResult.sent);
      expect(decision.shouldSendHeartbeat, isTrue);
      expect(decision.shouldTouchLastSeen, isFalse);
      expect(decision.keepsProviderOnline, isTrue);
    });

    test('prestador movel online sem coordenada mantem presenca sem GPS', () {
      final decision = ProviderPresencePolicy.resolve(
        onlineForDispatch: true,
        isFixedLocation: false,
        canAttemptBackend: true,
        hasCoords: false,
      );

      expect(decision.result, ProviderPresenceTickResult.missingCoords);
      expect(decision.shouldSendHeartbeat, isFalse);
      expect(decision.shouldTouchLastSeen, isTrue);
      expect(decision.keepsProviderOnline, isTrue);
    });

    test('prestador fixo online nao envia GPS periodico', () {
      final decision = ProviderPresencePolicy.resolve(
        onlineForDispatch: true,
        isFixedLocation: true,
        canAttemptBackend: true,
        hasCoords: true,
      );

      expect(decision.result, ProviderPresenceTickResult.skippedFixedProvider);
      expect(decision.shouldSendHeartbeat, isFalse);
      expect(decision.shouldTouchLastSeen, isTrue);
      expect(decision.keepsProviderOnline, isTrue);
    });

    test('prestador offline nao chama backend nem mantem online', () {
      final decision = ProviderPresencePolicy.resolve(
        onlineForDispatch: false,
        isFixedLocation: false,
        canAttemptBackend: true,
        hasCoords: true,
      );

      expect(decision.result, ProviderPresenceTickResult.skippedOffline);
      expect(decision.shouldSendHeartbeat, isFalse);
      expect(decision.shouldTouchLastSeen, isFalse);
      expect(decision.keepsProviderOnline, isFalse);
    });

    test('falha de rede nao desliga o prestador localmente', () {
      final decision = ProviderPresencePolicy.resolve(
        onlineForDispatch: true,
        isFixedLocation: false,
        canAttemptBackend: false,
        hasCoords: true,
      );

      expect(decision.result, ProviderPresenceTickResult.networkUnavailable);
      expect(decision.shouldSendHeartbeat, isFalse);
      expect(decision.shouldTouchLastSeen, isFalse);
      expect(decision.keepsProviderOnline, isTrue);
    });
  });
}
