import 'package:flutter_test/flutter_test.dart';
import 'package:service_101/domains/remote_ui/models/remote_screen.dart';

void main() {
  test('parses a valid remote screen contract', () {
    final screen = RemoteScreen.fromJson({
      'version': 1,
      'screen': 'help',
      'revision': 'rev-1',
      'ttl_seconds': 120,
      'features': {
        'enabled': true,
        'kill_switch': false,
        'flags': {'help_screen_v1': true},
      },
      'layout': {'kind': 'scroll'},
      'fallback_policy': {'mode': 'use_cache_then_native', 'allow_cache': true},
      'components': [
        {
          'id': 'c1',
          'type': 'status_block',
          'props': {
            'title': 'Nova corrida',
            'value': 'R\$ 25,00',
            'status': 'aguardando resposta',
          },
          'action': {
            'type': 'command',
            'command_key': 'accept_ride',
            'arguments': {'service_id': 'svc_1'},
          },
        },
      ],
    });

    expect(screen.version, 1);
    expect(screen.screen, 'help');
    expect(screen.revision, 'rev-1');
    expect(screen.ttlSeconds, 120);
    expect(screen.isEnabled, isTrue);
    expect(screen.components, hasLength(1));
    expect(screen.components.first.type, 'status_block');
    expect(screen.components.first.action?.commandKey, 'accept_ride');
  });
}
